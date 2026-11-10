import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models.dart';
import 'settings_service.dart';

class MarketDataService {
  final http.Client _c = http.Client();
  KeyPool? _twelvePool;
  String _twelveSig = '';

  static const Map<String, String> tdInterval = {
    '1m': '1min', '5m': '5min', '15m': '15min', '30m': '30min',
    '1h': '1h', '4h': '4h', '1d': '1day',
  };
  static const Map<String, String> tiingoFreq = {
    '1m': '1min', '5m': '5min', '15m': '15min', '30m': '30min',
    '1h': '1hour', '4h': '4hour', '1d': '1day',
  };
  static const Map<String, int> tfMinutes = {
    '1m': 1, '5m': 5, '15m': 15, '30m': 30, '1h': 60, '4h': 240, '1d': 1440,
  };
  static const Map<String, String> higherTf = {
    '1m': '15m', '5m': '1h', '15m': '1h', '30m': '4h',
    '1h': '4h', '4h': '1d', '1d': '1d',
  };

  static const _binanceHosts = ['data-api.binance.vision', 'api.binance.com'];

  KeyPool _pool(AppSettings s) {
    final sig = s.twelveKeys.join('|');
    if (_twelvePool == null || sig != _twelveSig) {
      _twelvePool = KeyPool(s.twelveKeys);
      _twelveSig = sig;
    }
    return _twelvePool!;
  }

  Future<List<Candle>> fetch(MarketSymbol sym, String tf, AppSettings s,
      {int count = 300}) async {
    final errors = <String>[];
    final tiingoOk = s.hasTiingo && sym.tiingo;
    final twelveOk = s.hasTwelve;

    // العملات الرقمية: Binance أولاً (حجم حقيقي شراء/بيع) — مجاني وبدون مفتاح
    if (sym.isCrypto) {
      try {
        final data = await _binance(sym, tf, count);
        if (data.length >= 20) return data;
        errors.add('binance: بيانات قليلة');
      } catch (e) {
        errors.add('binance: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }

    final order = <String>[];
    if (s.source == 'tiingo') {
      if (tiingoOk) order.add('tiingo');
      if (twelveOk) order.add('twelve');
    } else if (s.source == 'twelve') {
      if (twelveOk) order.add('twelve');
      if (tiingoOk) order.add('tiingo');
    } else {
      if (twelveOk) order.add('twelve');
      if (tiingoOk) order.add('tiingo');
    }
    if (order.isEmpty) {
      throw Exception(errors.isEmpty
          ? 'أضف مفتاح Twelve Data أو Tiingo من الإعدادات'
          : errors.join(' | '));
    }
    for (final src in order) {
      try {
        final data = src == 'twelve'
            ? await _twelve(sym, tf, _pool(s), count)
            : await _tiingo(sym, tf, s.tiingoKey.trim(), count);
        if (data.length >= 20) return data;
        errors.add('$src: بيانات قليلة');
      } catch (e) {
        errors.add('$src: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    throw Exception(errors.join(' | '));
  }

  Future<List<dynamic>> _binanceGet(Map<String, String> q) async {
    var last = 'فشل الاتصال';
    for (final h in _binanceHosts) {
      try {
        final r = await _c
            .get(Uri.https(h, '/api/v3/klines', q))
            .timeout(const Duration(seconds: 15));
        final j = jsonDecode(r.body);
        if (j is List) return j;
        last = (j is Map && j['msg'] != null)
            ? '${j['msg']}'
            : 'رد غير متوقع (${r.statusCode})';
      } catch (e) {
        last = e.toString();
      }
    }
    throw Exception(last);
  }

  Future<List<Candle>> _binance(MarketSymbol sym, String tf, int count) async {
    final out = <Candle>[];
    int? endTime;
    for (var page = 0; page < 12 && out.length < count; page++) {
      final need = math.min(1000, count - out.length);
      final q = <String, String>{
        'symbol': sym.binanceTicker,
        'interval': tf,
        'limit': '$need',
      };
      if (endTime != null) q['endTime'] = '$endTime';
      List<dynamic> rows;
      try {
        rows = await _binanceGet(q);
      } catch (e) {
        if (out.isEmpty) rethrow;
        break;
      }
      if (rows.isEmpty) break;
      final part = rows.map<Candle>((v) {
        final m = v as List;
        return Candle(
          DateTime.fromMillisecondsSinceEpoch(m[0] as int, isUtc: true),
          double.parse('${m[1]}'),
          double.parse('${m[2]}'),
          double.parse('${m[3]}'),
          double.parse('${m[4]}'),
          double.parse('${m[5]}'), // الحجم الكلي
          double.parse('${m[9]}'), // حجم شراء الـ Taker
        );
      }).toList();
      out.insertAll(0, part);
      endTime = part.first.time.millisecondsSinceEpoch - 1;
      if (rows.length < need) break;
    }
    return out;
  }

  DateTime _parseTd(String dt) {
    var t = dt.trim();
    if (t.length == 10) t = '${t}T00:00:00';
    t = t.replaceFirst(' ', 'T');
    return DateTime.parse('${t}Z');
  }

  Future<List<Candle>> _twelve(
      MarketSymbol sym, String tf, KeyPool pool, int count) async {
    if (pool.isEmpty) throw Exception('لا توجد مفاتيح Twelve Data');
    String last = 'فشل الطلب';
    for (var a = 0; a < pool.keys.length; a++) {
      final key = pool.next();
      if (key == null) break;
      try {
        final uri = Uri.https('api.twelvedata.com', '/time_series', {
          'symbol': sym.code,
          'interval': tdInterval[tf]!,
          'outputsize': '$count',
          'order': 'ASC',
          'timezone': 'UTC',
          'apikey': key,
        });
        final r = await _c.get(uri).timeout(const Duration(seconds: 20));
        final j = jsonDecode(r.body);
        if (j is Map && j['status'] == 'error') {
          last = '${j['message']}';
          pool.penalize(key);
          continue;
        }
        final vals = (j['values'] as List);
        return vals.map<Candle>((v) {
          return Candle(
            _parseTd(v['datetime'] as String),
            double.parse('${v['open']}'),
            double.parse('${v['high']}'),
            double.parse('${v['low']}'),
            double.parse('${v['close']}'),
            double.tryParse('${v['volume'] ?? ''}') ?? 0,
          );
        }).toList();
      } catch (e) {
        last = e.toString();
        pool.penalize(key, const Duration(seconds: 20));
      }
    }
    throw Exception(last);
  }

  Future<List<Candle>> _tiingo(
      MarketSymbol sym, String tf, String key, int count) async {
    final mins = tfMinutes[tf]!;
    final days = ((mins * count * 1.7) / 1440).ceil() + 3;
    final start = DateTime.now().toUtc().subtract(Duration(days: days));
    final uri = Uri.https(
      'api.tiingo.com',
      '/tiingo/fx/${sym.tiingoTicker}/prices',
      {
        'startDate': DateFormat('yyyy-MM-dd').format(start),
        'resampleFreq': tiingoFreq[tf]!,
        'token': key,
      },
    );
    final r = await _c.get(uri).timeout(const Duration(seconds: 20));
    final j = jsonDecode(r.body);
    if (j is Map) {
      throw Exception('${j['detail'] ?? j['message'] ?? 'خطأ من Tiingo'}');
    }
    final list = (j as List).map<Candle>((v) {
      return Candle(
        DateTime.parse(v['date'] as String).toUtc(),
        (v['open'] as num).toDouble(),
        (v['high'] as num).toDouble(),
        (v['low'] as num).toDouble(),
        (v['close'] as num).toDouble(),
      );
    }).toList();
    return list.length > count ? list.sublist(list.length - count) : list;
  }
}
