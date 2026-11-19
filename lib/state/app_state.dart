import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../analysis/aab_algo.dart';
import '../analysis/alka.dart';
import '../analysis/zero_one.dart';
import '../analysis/sm_indicator.dart';
import '../analysis/all_indicator.dart';
import '../analysis/forecast.dart';
import '../analysis/indicators.dart';
import '../analysis/health.dart';
import '../analysis/st_indicator.dart';
import '../analysis/star_indicator.dart';
import '../analysis/lt_indicator.dart';
import '../analysis/pq_indicator.dart';
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
  bool settingsLoaded = false; // صار true بعد قراءة الإعدادات والمفاتيح المحفوظة
  MarketSymbol symbol = allSymbols.first;
  String tf = '5m';
  int tab = 0;
  /// عدد الشموع المحمّلة لكل فريم
  static int candleCount(String tf) => tf == '1m' || tf == '5m' ? 600 : 300;

  bool chartFull = false; // شاشة كاملة للشارت: يخفي شريط التنقل أيضاً

  List<Candle> candles = [];
  List<Candle>? htf;
  DateTime? _htfAt;
  TradeSignal? signal;
  Forecast? forecast; // توصيات الشارت + توقع الشمعة القادمة
  AlgoResult? algo; // مؤشر AAB Algo (تلوين الشموع + خط الاتجاه + مناطق الانعكاس)
  AlkaResult? alka; // مؤشر Alka (شموع الانعكاس عند الدعم/المقاومة و Volume Profile)
  AllResult? allR; // مؤشر ALL (دمج AAB و Alka + فلتر الشمعة الصغيرة)
  ZeroResult? zero; // مؤشر 0.1 (مصيدة سيولة + شمعة رفض)
  AllResult? mpR; // مؤشر Mp (دمج مؤشراتنا الأربعة: ALL + 0.1)
  AllResult? smR; // مؤشر SM (إشارات Mp التي يوافقها شريط المتوسطات)
  AllResult? kmR; // مؤشر KM (إشارات SM في السوق الهادئ)
  AllResult? pqR; // مؤشر PQ (النجوم + SM + Alka في مؤشر واحد)
  AllResult? ltR; // مؤشر LT بعيد المدى (من الشموع اليومية)
  StarResult? starR; // مؤشر النجوم (كل إشارات Mp مع درجة الثقة)
  int starMin = 0; // أقل عدد نجوم يظهر
  StResult? stR; // مؤشر ST (إشارات Mp عالية الثقة حسب النموذج المتعلّم)
  AllResult? dmR; // مؤشر DM (خاص بالذهب: Mp مع الترند اليومي في السوق الهادئ)
  List<Candle>? daily; // شموع يومية (للوحة الاتجاهات و DM)
  Forecast? _fAll; // إشارات AAB بهدف Alka (لـ DM المستقل)
  Map<String, int> board = {}; // لوحة الاتجاهات (مثل DTC): 1h / 4h / 1d → +1 صاعد ، -1 هابط
  DateTime? _boardAt;
  IndHealth? aabHealth, alkaHealth, allHealth, zeroHealth, mpHealth, smHealth, kmHealth, dmHealth, stHealth; // أداء المؤشرات على هذا السوق والفريم (آخر 5000 شمعة)
  bool healthLoading = false;
  final _healthCache = <String, (List<IndHealth>, DateTime)>{};
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

  /// يزيد مع كل سعر لحظي — الشارت يعيد الرسم فوراً بدون انتظار التحليل.
  final liveTick = ValueNotifier<int>(0);
  bool _analyzing = false, _again = false;

  AppState() {
    _feed = LiveFeed(onTick: _onTick, onStatus: _onLiveStatus, onCandle: _onCandle);
  }

  Future<void> init() async {
    settings = await AppSettings.load();
    settingsLoaded = true;
    final p = await SharedPreferences.getInstance();
    favorites = (p.getStringList('favs') ?? []).toSet();
    symbol = symbolByCode(p.getString('symbol') ?? allSymbols.first.code);
    tf = p.getString('tf') ?? '5m';
    notifyListeners();
    if (settings.hasTwelve || settings.hasTiingo) {
      await refresh();
      _feed.start(symbol, settings, tf: tf);
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
        _analyzeAsync();
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
      if (candles.length > candleCount(tf) + 150) candles.removeAt(0);
    } else {
      candles[candles.length - 1] = Candle(last.time, last.open,
          math.max(last.high, p), math.min(last.low, p), p, last.volume, last.buyVol);
    }
    liveTick.value++;
    _dirty = true;
  }

  /// شمعة كاملة لحظية من Binance (العملات الرقمية).
  void _onCandle(Candle k) {
    if (candles.isEmpty) return;
    lastTickAt = DateTime.now();
    final last = candles.last;
    if (k.ts == last.ts) {
      candles[candles.length - 1] = k;
    } else if (k.ts > last.ts) {
      candles.add(k);
      if (candles.length > candleCount(tf) + 150) candles.removeAt(0);
    } else {
      return;
    }
    liveTick.value++;
    _dirty = true;
  }

  /// يدمج بيانات الخادم مع الشموع اللحظية: الخادم قد يتأخر، فلا نعود بالشمعة للخلف.
  List<Candle> _mergeLive(List<Candle> rest) {
    if (rest.isEmpty || candles.isEmpty || lastTickAt == null) return rest;
    if (DateTime.now().difference(lastTickAt!).inMinutes >= 3) return rest;
    final lastRest = rest.last.ts;
    final live = candles.where((k) => k.ts >= lastRest).toList();
    if (live.isEmpty) return rest;
    final out = rest.where((k) => k.ts < live.first.ts).toList();
    for (final k in live) {
      final same = rest.lastIndexWhere((r) => r.ts == k.ts);
      if (same >= 0) {
        final r = rest[same];
        // نفس الشمعة: الأعلى/الأدنى من الاثنين، والإغلاق من السعر اللحظي الأحدث
        out.add(Candle(k.time, r.open, math.max(r.high, k.high), math.min(r.low, k.low),
            k.close, math.max(r.volume, k.volume), k.buyVol >= 0 ? k.buyVol : r.buyVol));
      } else {
        out.add(k);
      }
    }
    final cap = candleCount(tf) + 150;
    return out.length > cap ? out.sublist(out.length - cap) : out;
  }

  void setChartFull(bool v) {
    chartFull = v;
    notifyListeners();
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
    _feed.start(symbol, settings, tf: tf);
    await refresh();
  }

  Future<void> setTf(String t) async {
    tf = t;
    _resetData();
    final p = await SharedPreferences.getInstance();
    await p.setString('tf', t);
    notifyListeners();
    await refresh();
    _feed.start(symbol, settings, tf: tf); // بث شموع الإطار الجديد (العملات الرقمية)
  }

  void _resetData() {
    _gen++;
    candles = [];
    htf = null;
    _htfAt = null;
    signal = null;
    forecast = null;
    algo = null;
    alka = null;
    allR = null;
    zero = null;
    mpR = null;
    smR = null;
    kmR = null;
    stR = null;
    starR = null;
    ltR = null;
    pqR = null;
    dmR = null;
    daily = null;
    board = {};
    _boardAt = null;
    _setHealth(_healthCache['${symbol.code}|$tf']?.$1);
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
    _feed.start(symbol, settings, tf: tf);
    await refresh();
    loadNews();
  }

  /// التحليل الكامل في خيط منفصل (Isolate) حتى لا يتجمّد الشارت أثناءه.
  Future<void> _analyzeAsync() async {
    if (candles.isEmpty) return;
    if (_analyzing) {
      _again = true;
      return;
    }
    _analyzing = true;
    final gen = _gen;
    final snap = List<Candle>.of(candles);
    final h = htf == null ? null : List<Candle>.of(htf!);
    final s = settings, sym = symbol, cfg = EngineConfig.current;
    final rr1 = settings.rr1For(symbol.category), rr2 = settings.rr2;
    final alkaTp1 = settings.alkaTp1;
    (TradeSignal, Forecast, AlgoResult, AlkaResult, AllResult, ZeroResult, AllResult, Forecast) res;
    try {
      res = await Isolate.run(() => _computeAll(snap, h, s, sym, cfg, rr1, rr2, alkaTp1));
    } catch (_) {
      res = _computeAll(snap, h, s, sym, cfg, rr1, rr2, alkaTp1); // احتياط
    }
    _analyzing = false;
    if (gen != _gen) return;
    _apply(res);
    notifyListeners();
    if (_again) {
      _again = false;
      _analyzeAsync();
    }
  }

  @visibleForTesting
  void analyzeNow() => _analyze();

  void _analyze() {
    if (candles.isEmpty) return;
    _apply(_computeAll(candles, htf, settings, symbol, EngineConfig.current,
        settings.rr1For(symbol.category), settings.rr2, settings.alkaTp1));
  }

  void _apply((TradeSignal, Forecast, AlgoResult, AlkaResult, AllResult, ZeroResult, AllResult, Forecast) r) {
    final prev = signal;
    final (base, fc, al, ak, all, z, mp, fAll) = r;
    _fAll = fAll;
    alka = ak;
    zero = z;
    mpR = mp;
    _rebuildStar();
    smR = buildSm(candles, mp, stars: starR);
    pqR = starR == null ? null : buildPq(mp, starR!, smR!);
    kmR = buildKm(candles, smR!);
    stR = buildSt(candles, mp);
    dmR = buildDm(candles, symbol, aab: fAll, alka: ak, zero: z, daily: daily);
    _rebuildLt();
    allR = all;
    forecast = fc;
    signal = _unify(base, fc);
    algo = al;
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

  /// تاريخ أطول للسوق الحالي (للمقارنة): 3000 شمعة بدل 300 حتى تكون النتائج موثوقة.
  /// لوحة الاتجاهات: اتجاه الساعة و4 ساعات واليومي لنفس السوق (تُحدّث كل 15 دقيقة).
  Future<void> _loadBoard() async {
    if (_boardAt != null && DateTime.now().difference(_boardAt!).inMinutes < 15) return;
    _boardAt = DateTime.now();
    final gen = _gen, sym = symbol;
    final out = <String, int>{};
    for (final t in const ['1h', '4h', '1d']) {
      try {
        final c = await _market.fetch(sym, t, settings, count: t == '1d' ? 400 : 120);
        if (gen != _gen) return;
        out[t] = trendOf(c);
        if (t == '1d') {
          daily = c;
          _rebuildLt();
          if (_fAll != null && alka != null && zero != null) {
            dmR = buildDm(candles, symbol, aab: _fAll!, alka: alka!, zero: zero!, daily: c);
            _rebuildStar();
          }
          _healthCache.remove('${symbol.code}|$tf'); // نعيد حساب صحة DM باليومي الصحيح
          _loadHealth(force: true);
        }
      } catch (_) {}
    }
    if (gen != _gen) return;
    board = out;
    notifyListeners();
  }

  Future<List<Candle>> fetchLong({int count = 3000}) =>
      _market.fetch(symbol, tf, settings, count: count);

  /// LT يعمل على الشموع اليومية: على فريم 1D من شموع الشارت، وفي غيره من الشموع اليومية المحمّلة.
  void _rebuildLt() {
    final d = tf == '1d' ? candles : daily;
    ltR = d == null || d.length < 230 ? null : buildLt(d);
  }

  void _rebuildStar() {
    final mp = mpR;
    starR = mp == null ? null : buildStar(candles, mp, minStars: starMin);
  }

  /// أقل عدد نجوم يظهر في مؤشر النجوم (0 = كل إشارات Mp).
  void setStarMin(int v) {
    starMin = v;
    _rebuildStar();
    notifyListeners();
  }

  /// خيار المحرك (مطفأ افتراضياً): إشارات إضافية في نفس الاتجاه.
  Future<void> setEngineOptions({bool? extraSameDir}) async {
    if (extraSameDir != null) settings.extraSameDir = extraSameDir;
    await settings.save();
    notifyListeners();
    _analyzeAsync();
  }

  void _setHealth(List<IndHealth>? h) {
    IndHealth? at(int i) => h != null && i < h.length ? h[i] : null;
    aabHealth = at(0);
    alkaHealth = at(1);
    allHealth = at(2);
    zeroHealth = at(3);
    mpHealth = at(4);
    smHealth = at(5);
    kmHealth = at(6);
    dmHealth = at(7);
    stHealth = at(8);
  }

  /// صحة AAB و Alka على هذا السوق (تُحسب في الخلفية وتُحفظ ساعتين).
  Future<void> _loadHealth({bool force = false}) async {
    final key = '${symbol.code}|$tf';
    final hit = _healthCache[key];
    if (!force && hit != null && DateTime.now().difference(hit.$2).inHours < 2) {
      _setHealth(hit.$1);
      return;
    }
    if (healthLoading) return;
    healthLoading = true;
    final gen = _gen;
    try {
      var c = candles;
      try {
        final h = await fetchLong(count: 5000);
        if (h.length > c.length) c = h;
      } catch (_) {}
      if (gen != _gen || c.length < 300) return;
      final data = List<Candle>.of(c), sym = symbol;
      List<IndHealth> r;
      try {
        final dd = daily == null ? null : List<Candle>.of(daily!);
        r = await Isolate.run(() => computeHealth(data, sym, daily: dd));
      } catch (_) {
        r = computeHealth(data, sym, daily: daily);
      }
      if (gen != _gen) return;
      _healthCache[key] = (r, DateTime.now());
      _setHealth(r);
    } finally {
      healthLoading = false;
      if (gen == _gen) notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_busy) return;
    if (!settings.hasTwelve && !settings.hasTiingo) return;
    _busy = true;
    final gen = _gen;
    loading = candles.isEmpty;
    notifyListeners();
    try {
      // الفريمات الصغيرة: 600 شمعة بدل 300 حتى تظهر إشارات أكثر (300 دقيقة = 5 ساعات فقط)
      final data = await _market.fetch(symbol, tf, settings, count: candleCount(tf));
      if (gen != _gen) return;
      candles = _mergeLive(data);
      liveTick.value++;
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
      _loadHealth();
      _loadBoard();
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
    liveTick.dispose();
    super.dispose();
  }
}

/// كل الحسابات الثقيلة (تعمل داخل Isolate): المحرك القديم للطبقات، محرك التوصيات، و AAB Algo.
(TradeSignal, Forecast, AlgoResult, AlkaResult, AllResult, ZeroResult, AllResult, Forecast) _computeAll(List<Candle> c, List<Candle>? htf,
    AppSettings s, MarketSymbol sym, EngineConfig cfg, double rr1, double rr2, double alkaTp1) {
  final base = SignalEngine.analyze(c, htf: htf, s: s, sym: sym, cfg: cfg);
  final hist = c.length; // الإشارات على كل الشموع المحمّلة (300 أو 600)
  final fc = buildForecast(c, rr1: rr1, rr2: rr2, history: hist);
  final al = aabAlgo(c, sens: 2.0, withPanel: false);
  final ak = buildAlka(c, rr1: alkaTp1, rr2: rr2, sym: sym, history: hist);
  // ALL: AAB بنفس هدف Alka، ثم الدمج مع فلتر الشمعة الصغيرة
  final fAll = alkaTp1 == rr1 ? fc : buildForecast(c, rr1: alkaTp1, rr2: rr2, history: hist);
  final all = combineAll(c, fAll.signals, fAll.pending, ak.signals, ak.pending);
  final z = buildZeroOne(c, rr1: alkaTp1, rr2: rr2, sym: sym, history: hist);
  // Mp: ALL + 0.1 (إشارات 0.1 بدون فلتر الشمعة الصغيرة ولها الأولوية)
  var mp = combineAll(c, fAll.signals, fAll.pending, ak.signals, ak.pending, zero: z.signals, zeroPending: z.pending, tag: 'Mp');
  if (s.extraSameDir) mp = _withExtras(c, mp, sym, alkaTp1, rr2, hist);
  return (base, fc, al, ak, all, z, mp, fAll);
}

/// إشارات إضافية في نفس اتجاه الصفقة المفتوحة، بعد أن تحقق TP1 (فتصبح الأولى بلا خطر).
/// صفقة إضافية واحدة في كل مرة. مقاس على الذهب: صفقات أكثر ~17% بنفس الدقة تقريباً، وربح أكثر ~13-18%.
AllResult _withExtras(List<Candle> c, AllResult mp, MarketSymbol sym, double rr1, double rr2, int hist) {
  final n = c.length;
  final fo = buildForecast(c, rr1: rr1, rr2: rr2, history: hist, overlap: true);
  final ko = buildAlka(c, rr1: rr1, rr2: rr2, sym: sym, history: hist, overlap: true);
  final zo = buildZeroOne(c, rr1: rr1, rr2: rr2, sym: sym, history: hist, overlap: true);
  final at = atr(c, 14);
  bool small(int i) {
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    return a > 0 && (c[i].high - c[i].low) / a <= 0.94;
  }
  final cands = <(PastSignal, String)>[
    for (final x in zo.signals) (x, '0.1'),
    for (final x in fo.signals) if (small(x.i)) (x, 'AAB'),
    for (final x in ko.signals) if (small(x.i)) (x, 'Alka'),
  ]..sort((a, b) => a.$1.i.compareTo(b.$1.i));
  final mainI = {for (final x in mp.signals) x.i};
  final extras = <(PastSignal, String)>[];
  var busy = -1;
  for (final s0 in mp.signals) {
    final end = s0.exitI < 0 ? n - 1 : s0.exitI;
    var tp1 = -1;
    for (var q = s0.i + 1; q <= end; q++) {
      if (s0.dir > 0 ? c[q].high >= s0.tp1 : c[q].low <= s0.tp1) {
        tp1 = q;
        break;
      }
    }
    if (tp1 < 0) continue;
    for (final (x, src) in cands) {
      if (x.i < tp1 || x.i > end || x.dir != s0.dir || x.i <= busy || mainI.contains(x.i)) continue;
      extras.add((x, src));
      busy = x.exitI < 0 ? n : x.exitI;
    }
  }
  if (extras.isEmpty) return mp;
  final all = <(PastSignal, String)>[
    for (final (q, x) in mp.signals.indexed) (x, mp.sources[q]),
    ...extras,
  ]..sort((a, b) => a.$1.i.compareTo(b.$1.i));
  return AllResult([for (final x in all) x.$1], [for (final x in all) x.$2], mp.pending, mp.pendingSrc, mp.tag,
      {for (final e in extras) e.$1.i});
}
