import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../analysis/forecast.dart';
import '../analysis/signal_engine.dart';
import '../data/symbols.dart';
import '../models.dart';
import '../services/gemini_service.dart';
import '../services/live_feed_service.dart';
import '../services/market_data_service.dart';
import '../services/news_service.dart';
import '../services/settings_service.dart';

class AppState extends ChangeNotifier {
  final _market = MarketDataService();
  final _gemini = GeminiService();
  final _newsSvc = NewsService();
  late final LiveFeed _feed;

  AppSettings settings = AppSettings();
  MarketSymbol symbol = allSymbols.first;
  String tf = '5m';
  int tab = 0;

  List<Candle> candles = [];
  List<Candle>? htf;
  DateTime? _htfAt;
  TradeSignal? signal;
  Forecast? forecast; // توصيات الشارت + توقع الشمعة القادمة
  bool loading = false;
  String? error;
  DateTime? lastUpdate;
  int tick = 0; // increments whenever candles/signal changed

  // live feed state
  String liveStatus = 'off'; // off | connecting | live | poll | error
  String liveSource = '';
  DateTime? lastTickAt;
  bool _dirty = false;

  bool aiLoading = false;
  String? aiError;
  Direction? _aiDir;
  DateTime? _aiAt;

  List<NewsItem> news = [];
  bool newsLoading = false;
  String? newsError;

  Set<String> favorites = {};

  Timer? _timer, _newsTimer, _uiTimer;
  bool _busy = false;
  int _gen = 0; // guards against stale responses after symbol/tf change

  static const timeframes = ['1m', '5m', '15m', '30m', '1h', '4h', '1d'];

  AppState() {
    _feed = LiveFeed(onTick: _onTick, onStatus: _onLiveStatus);
  }

  Future<void> init() async {
    settings = await AppSettings.load();
    final p = await SharedPreferences.getInstance();
    favorites = (p.getStringList('favs') ?? []).toSet();
    symbol = symbolByCode(p.getString('symbol') ?? allSymbols.first.code);
    tf = p.getString('tf') ?? '5m';
    notifyListeners();
    if (settings.hasTwelve || settings.hasTiingo) {
      await refresh();
      _feed.start(symbol, settings);
    } else {
      tab = 4; // go to settings so the user can add keys
      notifyListeners();
    }
    _startTimers();
    loadNews();
  }

  void _startTimers() {
    _timer?.cancel();
    _newsTimer?.cancel();
    _uiTimer?.cancel();
    _timer = Timer.periodic(
        Duration(seconds: settings.refreshSec.clamp(15, 600).toInt()),
        (_) => refresh());
    _newsTimer = Timer.periodic(const Duration(seconds: 90), (_) => loadNews());
    // re-analyse at most once per second while live ticks arrive
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_dirty) {
        _dirty = false;
        _analyze();
        notifyListeners();
      }
    });
  }

  // ───────────── live ticks ─────────────
  void _onLiveStatus(String status, String source) {
    if (status == liveStatus && source == liveSource) return;
    liveStatus = status;
    liveSource = source;
    notifyListeners();
  }

  void _onTick(Tick t) {
    if (t.symbol != symbol.code || candles.isEmpty) return;
    lastTickAt = DateTime.now();
    final secs = MarketDataService.tfMinutes[tf]! * 60;
    final nowTs = t.time.millisecondsSinceEpoch ~/ 1000;
    final bucket = (nowTs ~/ secs) * secs;
    final last = candles.last;
    final p = t.price;
    if (bucket >= last.ts + secs) {
      candles.add(Candle(
          DateTime.fromMillisecondsSinceEpoch(bucket * 1000, isUtc: true),
          p, p, p, p));
      if (candles.length > 450) candles.removeAt(0);
    } else {
      candles[candles.length - 1] = Candle(last.time, last.open,
          math.max(last.high, p), math.min(last.low, p), p, last.volume);
    }
    _dirty = true;
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  Future<void> setSymbol(MarketSymbol s) async {
    symbol = s;
    _resetData();
    final p = await SharedPreferences.getInstance();
    await p.setString('symbol', s.code);
    notifyListeners();
    _feed.start(symbol, settings);
    await refresh();
  }

  Future<void> setTf(String t) async {
    tf = t;
    _resetData();
    final p = await SharedPreferences.getInstance();
    await p.setString('tf', t);
    notifyListeners();
    await refresh();
  }

  void _resetData() {
    _gen++;
    candles = [];
    htf = null;
    _htfAt = null;
    signal = null;
    forecast = null;
    error = null;
    _aiDir = null;
    _aiAt = null;
    aiError = null;
    _dirty = false;
  }

  Future<void> toggleFavorite(String code) async {
    favorites.contains(code) ? favorites.remove(code) : favorites.add(code);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('favs', favorites.toList());
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings s) async {
    settings = s;
    await s.save();
    _startTimers();
    notifyListeners();
    _feed.start(symbol, settings);
    await refresh();
    loadNews();
  }

  void _analyze() {
    if (candles.isEmpty) return;
    final prev = signal;
    final base = SignalEngine.analyze(candles, htf: htf, s: settings, sym: symbol);
    forecast = buildForecast(candles, rr1: settings.rr1, rr2: settings.rr2);
    signal = _unify(base, forecast!);
    if (prev != null && prev.direction == signal!.direction) {
      signal!.aiVerdict = prev.aiVerdict;
      signal!.aiComment = prev.aiComment;
    }
    lastUpdate = DateTime.now();
    tick++;
    _maybeAi();
  }

  /// قرار واحد في كل التطبيق: الاتجاه والمستويات والأسباب من محرك التوصيات المقاس
  /// (forecast)، مع الإبقاء على طبقات الرسم (مناطق، فيبوناتشي، VWAP...) من المحرك القديم.
  TradeSignal _unify(TradeSignal b, Forecast f) {
    if (f.indicators.isEmpty) return b; // بيانات غير كافية
    final d = f.decision;
    final open = d.state == 1;
    final dir = !open
        ? Direction.neutral
        : d.dir > 0
            ? Direction.buy
            : Direction.sell;
    final ratio = d.total == 0 ? 0.0 : d.agree / d.total;
    final reasons = <String>[
      d.title,
      if (d.why.isNotEmpty) d.why,
      if (d.state == 2)
        'الدخول عند ${symbol.fmt(d.entry)} • الوقف ${symbol.fmt(d.sl)} • '
            'الهدف 1 ${symbol.fmt(d.tp1)} • الهدف 2 ${symbol.fmt(d.tp2)}',
      if (f.closed > 0)
        'دقة التوصيات على هذا الشارت: ${(f.winRate * 100).toStringAsFixed(0)}% '
            '(${f.wins} ربح / ${f.losses} خسارة)',
    ];
    final tp3 = open && !d.risk.isNaN ? d.entry + d.dir * d.risk * settings.rr3 : 0.0;
    return TradeSignal(
      direction: dir,
      score: open ? d.dir * ratio * 100 : 0,
      price: b.price,
      entry: open ? d.entry : b.price,
      stopLoss: open ? d.sl : 0,
      tp1: open ? d.tp1 : 0,
      tp2: open ? d.tp2 : 0,
      tp3: tp3,
      atr: b.atr,
      votes: [
        for (final e in f.indicators)
          IndicatorVote(e.name,
              '${e.bias > 0 ? 'صاعد' : e.bias < 0 ? 'هابط' : 'محايد'}${e.fired ? ' • إشارة جديدة' : ''}',
              e.bias),
      ],
      patterns: b.patterns,
      reasons: reasons,
      htfTrend: b.htfTrend,
      time: b.time,
      grade: !open ? 'C' : (ratio >= 0.7 ? 'A' : 'B'),
      aligned: d.agree,
      killzone: b.killzone,
      zones: b.zones,
      marks: b.marks,
      ceLong: b.ceLong,
      ceShort: b.ceShort,
      equilibrium: b.equilibrium,
      poc: b.poc,
      vah: b.vah,
      val: b.val,
      fibs: b.fibs,
      fibUp: b.fibUp,
      vpBins: b.vpBins,
      vwap: b.vwap,
      keyLevels: b.keyLevels,
    );
  }

  Future<void> refresh() async {
    if (_busy) return;
    if (!settings.hasTwelve && !settings.hasTiingo) return;
    _busy = true;
    final gen = _gen;
    loading = candles.isEmpty;
    notifyListeners();
    try {
      final data = await _market.fetch(symbol, tf, settings);
      if (gen != _gen) return;
      candles = data;
      final stale = _htfAt == null ||
          DateTime.now().difference(_htfAt!).inMinutes >= 5;
      if (stale) {
        try {
          final h = await _market.fetch(
              symbol, MarketDataService.higherTf[tf]!, settings,
              count: 120);
          if (gen != _gen) return;
          htf = h;
          _htfAt = DateTime.now();
        } catch (_) {
          // higher timeframe is optional
        }
      }
      _analyze();
      error = null;
    } catch (e) {
      if (gen == _gen) error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _busy = false;
      loading = false;
      notifyListeners();
    }
  }

  void _maybeAi() {
    final s = signal;
    if (s == null || !settings.useAi || !settings.hasGemini) return;
    if (s.direction == Direction.neutral || aiLoading) return;
    final fresh = _aiAt != null &&
        DateTime.now().difference(_aiAt!).inMinutes < 3 &&
        _aiDir == s.direction;
    if (fresh) return;
    aiLoading = true;
    aiError = null;
    final gen = _gen;
    _gemini.review(symbol, tf, s, settings).then((r) {
      if (gen != _gen) return;
      s.aiVerdict = r.verdict;
      s.aiComment = r.comment;
      _aiDir = s.direction;
      _aiAt = DateTime.now();
    }).catchError((e) {
      aiError = e.toString().replaceFirst('Exception: ', '');
    }).whenComplete(() {
      aiLoading = false;
      notifyListeners();
    });
  }

  Future<void> loadNews() async {
    if (newsLoading) return;
    newsLoading = true;
    notifyListeners();
    try {
      final n = await _newsSvc.fetch(tiingoKey: settings.tiingoKey);
      if (n.isNotEmpty) news = n;
      newsError = n.isEmpty && news.isEmpty ? 'تعذر تحميل الأخبار' : null;
    } catch (e) {
      newsError = e.toString();
    } finally {
      newsLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _feed.stop();
    _timer?.cancel();
    _newsTimer?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }
}
