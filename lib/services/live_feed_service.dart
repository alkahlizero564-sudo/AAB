import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models.dart';
import 'settings_service.dart';

/// Real-time price ticks.
///  • Forex / gold  → Tiingo FX WebSocket (every top-of-book change)
///  • Other symbols → Twelve Data WebSocket (needs a plan that includes WS)
///  • Fallback      → Twelve Data /price polling every [AppSettings.pollSec]
class LiveFeed {
  LiveFeed({required this.onTick, required this.onStatus});

  final void Function(Tick) onTick;
  final void Function(String status, String source) onStatus;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _hb, _retry, _poll;
  int _gen = 0;
  int _attempt = 0;
  MarketSymbol? _sym;
  AppSettings? _s;
  final http.Client _http = http.Client();
  KeyPool? _pool;
  String _poolSig = '';

  KeyPool _poolFor(AppSettings s) {
    final sig = s.twelveKeys.join('|');
    if (_pool == null || sig != _poolSig) {
      _pool = KeyPool(s.twelveKeys);
      _poolSig = sig;
    }
    return _pool!;
  }

  void start(MarketSymbol sym, AppSettings s) {
    stop();
    _sym = sym;
    _s = s;
    _attempt = 0;
    if (!s.liveWs || (!s.hasTiingo && !s.hasTwelve)) {
      onStatus('off', 'REST');
      return;
    }
    _connect(_gen);
  }

  void stop() {
    _gen++;
    _hb?.cancel();
    _retry?.cancel();
    _poll?.cancel();
    _sub?.cancel();
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _sub = null;
  }

  Future<void> _connect(int gen) async {
    final sym = _sym!, s = _s!;
    if (sym.tiingo && s.hasTiingo) {
      await _tiingoWs(gen, sym, s);
    } else if (s.hasTwelve) {
      await _twelveWs(gen, sym, s);
    } else {
      onStatus('off', 'REST');
    }
  }

  void _gotTick(int gen, Tick t, String src) {
    if (gen != _gen) return;
    if (_attempt != 0) _attempt = 0;
    if (src != 'Polling') _poll?.cancel();
    onTick(t);
    onStatus(src == 'Polling' ? 'poll' : 'live', src == 'Polling' ? 'Twelve Data' : src);
  }

  // ───────────── Tiingo FX WebSocket ─────────────
  Future<void> _tiingoWs(int gen, MarketSymbol sym, AppSettings s) async {
    onStatus('connecting', 'Tiingo');
    try {
      final ch = WebSocketChannel.connect(Uri.parse('wss://api.tiingo.com/fx'));
      await ch.ready;
      if (gen != _gen) {
        ch.sink.close();
        return;
      }
      _ch = ch;
      ch.sink.add(jsonEncode({
        'eventName': 'subscribe',
        'authorization': s.tiingoKey.trim(),
        'eventData': {
          'thresholdLevel': 5,
          'tickers': [sym.tiingoTicker],
        },
      }));
      _sub = ch.stream.listen((raw) {
        if (gen != _gen) return;
        try {
          final j = jsonDecode(raw as String);
          final type = j['messageType'];
          if (type == 'A') {
            final d = j['data'] as List;
            if (d.length >= 8 && d[0] == 'Q') {
              final bid = (d[4] as num).toDouble();
              final ask = (d[7] as num).toDouble();
              final mid = d[5] is num ? (d[5] as num).toDouble() : (bid + ask) / 2;
              _gotTick(gen, Tick(sym.code, mid, DateTime.now().toUtc()), 'Tiingo');
            }
          } else if (type == 'E') {
            final msg = j['response'] is Map ? j['response']['message'] : null;
            onStatus('error', 'Tiingo: ${msg ?? 'خطأ'}');
          }
        } catch (_) {}
      }, onError: (_) => _scheduleRetry(gen), onDone: () => _scheduleRetry(gen));
    } catch (e) {
      onStatus('error', 'Tiingo: $e');
      _scheduleRetry(gen);
    }
  }

  // ───────────── Twelve Data WebSocket ─────────────
  Future<void> _twelveWs(int gen, MarketSymbol sym, AppSettings s) async {
    final key = _poolFor(s).next();
    if (key == null) {
      _startPolling(gen);
      return;
    }
    onStatus('connecting', 'Twelve Data');
    try {
      final ch = WebSocketChannel.connect(
          Uri.parse('wss://ws.twelvedata.com/v1/quotes/price?apikey=$key'));
      await ch.ready;
      if (gen != _gen) {
        ch.sink.close();
        return;
      }
      _ch = ch;
      ch.sink.add(jsonEncode({
        'action': 'subscribe',
        'params': {'symbols': sym.code},
      }));
      _hb?.cancel();
      _hb = Timer.periodic(const Duration(seconds: 10), (_) {
        try {
          ch.sink.add(jsonEncode({'action': 'heartbeat'}));
        } catch (_) {}
      });
      _sub = ch.stream.listen((raw) {
        if (gen != _gen) return;
        try {
          final j = jsonDecode(raw as String);
          final ev = j['event'];
          if (ev == 'price') {
            final p = double.tryParse('${j['price']}');
            if (p != null) {
              _gotTick(gen, Tick(sym.code, p, DateTime.now().toUtc()), 'Twelve Data WS');
            }
          } else if (ev == 'subscribe-status') {
            final fails = j['fails'];
            if (fails is List && fails.isNotEmpty) {
              // plan does not include WebSocket for this symbol → poll instead
              try {
                ch.sink.close();
              } catch (_) {}
              _startPolling(gen);
            }
          }
        } catch (_) {}
      }, onError: (_) => _scheduleRetry(gen), onDone: () => _scheduleRetry(gen));
    } catch (_) {
      _startPolling(gen);
    }
  }

  // ───────────── Polling fallback ─────────────
  void _startPolling(int gen) {
    final s = _s!, sym = _sym!;
    final pool = _poolFor(s);
    if (pool.isEmpty) {
      onStatus('off', 'REST');
      return;
    }
    _poll?.cancel();
    onStatus('poll', 'Twelve Data');
    _poll = Timer.periodic(Duration(seconds: s.pollSec.clamp(3, 120).toInt()), (_) async {
      if (gen != _gen) return;
      final key = pool.next();
      if (key == null) return;
      try {
        final r = await _http
            .get(Uri.https('api.twelvedata.com', '/price',
                {'symbol': sym.code, 'apikey': key}))
            .timeout(const Duration(seconds: 10));
        final j = jsonDecode(r.body);
        final p = double.tryParse('${j['price']}');
        if (p != null) {
          _gotTick(gen, Tick(sym.code, p, DateTime.now().toUtc()), 'Polling');
        } else {
          pool.penalize(key);
        }
      } catch (_) {
        pool.penalize(key, const Duration(seconds: 20));
      }
    });
  }

  void _scheduleRetry(int gen) {
    if (gen != _gen) return;
    _hb?.cancel();
    _sub?.cancel();
    try {
      _ch?.sink.close();
    } catch (_) {}
    _attempt++;
    final s = _s!;
    if (_attempt >= 3 && s.hasTwelve && _poll == null) _startPolling(gen);
    final secs = math.min(30, 2 << math.min(_attempt, 4));
    _retry?.cancel();
    _retry = Timer(Duration(seconds: secs), () {
      if (gen == _gen) _connect(gen);
    });
  }
}
