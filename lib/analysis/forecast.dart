import 'dart:math' as math;
import '../models.dart';
import 'indicators.dart';
import 'patterns.dart';
import 'smc.dart';

/// اسم مختصر للنموذج يُكتب فوق/تحت الشمعة على الشارت.
String shortPattern(PatternHit p) {
  const m = {
    'Hammer': 'مطرقة',
    'Inverted Hammer': 'مطرقة مقلوبة',
    'Hanging Man': 'مشنوق',
    'Shooting Star': 'نجم هاوٍ',
    'Bullish Engulfing': 'ابتلاع',
    'Bearish Engulfing': 'ابتلاع',
    'Piercing Line': 'اختراق',
    'Dark Cloud Cover': 'غطاء أسود',
    'Bullish Harami': 'هارامي',
    'Bearish Harami': 'هارامي',
    'Bullish Harami Cross': 'هارامي+',
    'Bearish Harami Cross': 'هارامي+',
    'Tweezer Bottom': 'ملقط',
    'Tweezer Top': 'ملقط',
    'Morning Star': 'نجمة الصباح',
    'Evening Star': 'نجمة المساء',
    'Three White Soldiers': '3 جنود',
    'Three Black Crows': '3 غربان',
    'Three Inside Up': 'داخل 3',
    'Three Inside Down': 'داخل 3',
    'Three Outside Up': 'خارج 3',
    'Three Outside Down': 'خارج 3',
    'Bullish Marubozu': 'ماروبوزو',
    'Bearish Marubozu': 'ماروبوزو',
    'Dragonfly Doji': 'يعسوب',
    'Gravestone Doji': 'شاهد قبر',
    'Bullish Outside Bar': 'خارجية',
    'Bearish Outside Bar': 'خارجية',
    'Rising Three Methods': '3 طرق',
    'Falling Three Methods': '3 طرق',
  };
  return m[p.en] ?? p.ar;
}

/// نموذج شمعة مكتشف على شمعة تاريخية.
class PatMark {
  final int i;
  final int bias;
  final String label;
  const PatMark(this.i, this.bias, this.label);
}

/// توصية ظهرت على الشارت في الماضي ونتيجتها الفعلية بعدها.
/// تُحسب على الشموع المغلقة فقط (بدون نظر للمستقبل) فلا تتغير بعد ظهورها.
class PastSignal {
  final int i; // شمعة الإشارة (مغلقة)
  final int dir; // +1 شراء / -1 بيع
  final double entry, sl, tp1, tp2;
  final int result; // 2 = TP2 ، 1 = TP1 ، -1 = وقف ، 0 = ما زالت مفتوحة
  final int exitI; // شمعة الخروج (-1 لو مفتوحة)
  final String why;
  final bool strong; // تأكيدان أو أكثر
  const PastSignal(this.i, this.dir, this.entry, this.sl, this.tp1, this.tp2,
      this.result, this.exitI, this.why, this.strong);
}

/// إشارة مرتقبة: مستوى إذا وصل له السعر تتأكد التوصية (قبل حدوثها).
class PendingSetup {
  final int dir;
  final double trigger, sl, tp1, tp2;
  final String cond;
  const PendingSetup(this.dir, this.trigger, this.sl, this.tp1, this.tp2, this.cond);
}

/// توقع الشمعة القادمة.
class NextBar {
  final double pUp; // احتمال إغلاق الشمعة القادمة أعلى من الحالية
  final int sample; // عدد الحالات المشابهة في التاريخ
  final double open, high, low, close; // الشمعة الشبحية المتوقعة
  final String why;
  const NextBar(this.pUp, this.sample, this.open, this.high, this.low,
      this.close, this.why);
}

class Forecast {
  final List<PatMark> patterns;
  final List<PastSignal> signals;
  final List<int> predHits; // لكل شمعة: 1 صح ، -1 خطأ ، 0 بدون توقع
  final int predN, predOk;
  final NextBar? next;
  final List<PendingSetup> pending;
  final List<double> ema20, ema50, ema200;
  final String liveSignal; // إشارة تتكوّن في الشمعة الحالية (غير مغلقة)
  const Forecast({
    this.patterns = const [],
    this.signals = const [],
    this.predHits = const [],
    this.predN = 0,
    this.predOk = 0,
    this.next,
    this.pending = const [],
    this.ema20 = const [],
    this.ema50 = const [],
    this.ema200 = const [],
    this.liveSignal = '',
  });

  int get wins => signals.where((s) => s.result > 0).length;
  int get losses => signals.where((s) => s.result < 0).length;
  int get closed => wins + losses;
  double get winRate => closed == 0 ? 0 : wins / closed;
  double get predAcc => predN == 0 ? 0 : predOk / predN;
}

class _Bar {
  final int trend; // اتجاه EMA + Supertrend
  final int pat; // انحياز أقوى نموذج شمعة
  final PatternHit? hit;
  final int div; // انحراف RSI مؤكد عند هذه الشمعة
  final int ema; // ارتداد من EMA20 مع الاتجاه
  final int macdX; // تقاطع MACD
  final int rz; // منطقة RSI 0..3
  final int mom; // هيستوجرام MACD يتسارع +1 / يتباطأ -1
  const _Bar(this.trend, this.pat, this.hit, this.div, this.ema, this.macdX,
      this.rz, this.mom);
}

/// محرك التوقع: يقرأ الشارت كما يقرأه المتداول المحترف
/// (الاتجاه بـ EMA 20/50/200 + Supertrend، الزخم بـ RSI و MACD،
/// الانحرافات Divergence، أنماط الشموع اليابانية) ويُخرج:
///  • التوصيات التاريخية على الشارت مع نتيجتها الحقيقية ← دقة مرئية بدون باكتست.
///  • توقع الشمعة القادمة من تكرار الحالات المشابهة في نفس الشارت.
///  • مستويات الإشارة المرتقبة قبل حدوثها.
Forecast buildForecast(List<Candle> c, {double rr1 = 1.0, double rr2 = 2.0}) {
  final n = c.length;
  if (n < 70) return const Forecast();
  final cl = c.map((e) => e.close).toList();
  final e20 = ema(cl, 20), e50 = ema(cl, 50), e200 = ema(cl, 200);
  final r = rsi(cl, 14);
  final m = macd(cl);
  final at = atr(c, 14);
  final st = supertrend(c);

  final start = math.max(55, n - 300);

  // ── قيعان/قمم محورية (يسار 3 ، يمين 2) للانحرافات — تتأكد بعد شمعتين
  bool isPivLow(int p) {
    if (p < 3 || p + 2 >= n) return false;
    for (var j = p - 3; j <= p + 2; j++) {
      if (j != p && c[j].low <= c[p].low) return false;
    }
    return true;
  }

  bool isPivHigh(int p) {
    if (p < 3 || p + 2 >= n) return false;
    for (var j = p - 3; j <= p + 2; j++) {
      if (j != p && c[j].high >= c[p].high) return false;
    }
    return true;
  }

  int divergenceAt(int i) {
    final p = i - 2;
    if (p < 10 || r[p].isNaN) return 0;
    if (isPivLow(p)) {
      for (var q = p - 5; q >= math.max(3, p - 40); q--) {
        if (!isPivLow(q) || r[q].isNaN) continue;
        // قاع سعري أدنى + قاع RSI أعلى = انحراف إيجابي
        if (c[p].low < c[q].low && r[p] > r[q] + 2 && r[q] < 45) return 1;
        break;
      }
    }
    if (isPivHigh(p)) {
      for (var q = p - 5; q >= math.max(3, p - 40); q--) {
        if (!isPivHigh(q) || r[q].isNaN) continue;
        if (c[p].high > c[q].high && r[p] < r[q] - 2 && r[q] > 55) return -1;
        break;
      }
    }
    return 0;
  }

  _Bar barAt(int i) {
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    var trend = 0;
    if (!e20[i].isNaN && !e50[i].isNaN) {
      if (cl[i] > e50[i] && e20[i] > e50[i] && st.dir[i] == 1) trend = 1;
      if (cl[i] < e50[i] && e20[i] < e50[i] && st.dir[i] == -1) trend = -1;
    }
    final hits = detectPatterns(c.sublist(math.max(0, i - 14), i + 1));
    PatternHit? best;
    for (final h in hits) {
      if (h.bias == 0 || h.weight < 0.7) continue;
      if (best == null || h.weight > best.weight) best = h;
    }
    var emaB = 0;
    if (!e20[i].isNaN) {
      final k = c[i];
      if (trend == 1 && k.low <= e20[i] + 0.15 * a && k.close > e20[i] && k.close > k.open) {
        emaB = 1;
      }
      if (trend == -1 && k.high >= e20[i] - 0.15 * a && k.close < e20[i] && k.close < k.open) {
        emaB = -1;
      }
    }
    var mx = 0, mom = 0;
    final h = m.hist[i], hp = m.hist[i - 1];
    if (!h.isNaN && !hp.isNaN) {
      if (h > 0 && hp <= 0) mx = 1;
      if (h < 0 && hp >= 0) mx = -1;
      mom = h > hp ? 1 : -1;
    }
    final rv = r[i];
    final rz = rv.isNaN ? 1 : (rv < 30 ? 0 : rv < 50 ? 1 : rv < 70 ? 2 : 3);
    return _Bar(trend, best?.bias ?? 0, best, divergenceAt(i), emaB, mx, rz, mom);
  }

  final bars = <int, _Bar>{};
  for (var i = start; i < n; i++) {
    bars[i] = barAt(i);
  }

  // ── منطق التوصية لشمعة i: يُرجع (الاتجاه، السبب، قوي؟)
  (int, String, bool) decide(int i) {
    final b = bars[i]!;
    for (final d in const [1, -1]) {
      final why = <String>[];
      if (b.pat == d) why.add('شمعة ${b.hit!.ar}');
      if (b.div == d) why.add('انحراف RSI ${d > 0 ? 'إيجابي' : 'سلبي'}');
      if (b.ema == d) why.add('ارتداد من EMA20');
      if (b.macdX == d) why.add('تقاطع MACD');
      final rv = r[i];
      final rsiOk = rv.isNaN || (d > 0 ? rv < 72 : rv > 28);
      if (!rsiOk || why.isEmpty) continue;
      // مع الاتجاه: يكفي تأكيد واحد. عكس الاتجاه (انعكاس): انحراف + شمعة انعكاسية.
      if (b.trend == d) return (d, why.join(' + '), why.length >= 2);
      if (b.trend == 0 && why.length >= 2) return (d, why.join(' + '), true);
      if (b.trend == -d && b.div == d && b.pat == d) {
        return (d, 'انعكاس: ${why.join(' + ')}', true);
      }
    }
    return (0, '', false);
  }

  (double, double, double, double) levels(int i, int d, double entry) {
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    var ext = d > 0 ? c[i].low : c[i].high;
    for (var j = math.max(0, i - 2); j <= i; j++) {
      ext = d > 0 ? math.min(ext, c[j].low) : math.max(ext, c[j].high);
    }
    var risk = (d > 0 ? entry - ext : ext - entry) + 0.1 * a;
    risk = risk.clamp(0.7 * a, 2.5 * a).toDouble();
    return (
      entry - d * risk,
      entry + d * risk * rr1,
      entry + d * risk * rr2,
      risk,
    );
  }

  // ── التوصيات التاريخية + نتيجتها (صفقة واحدة في كل مرة كالتداول الحقيقي)
  final signals = <PastSignal>[];
  var busyUntil = -1;
  for (var i = start; i < n - 1; i++) {
    if (i <= busyUntil) continue;
    final (d, why, strong) = decide(i);
    if (d == 0) continue;
    final entry = c[i + 1].open;
    final (sl, t1, t2, _) = levels(i, d, entry);
    var res = 0, exitI = -1;
    var stop = sl;
    var gotT1 = false;
    for (var j = i + 1; j < n && j <= i + 80; j++) {
      final k = c[j];
      final hitSl = d > 0 ? k.low <= stop : k.high >= stop;
      if (hitSl) {
        res = gotT1 ? 1 : -1; // بعد الهدف الأول ينتقل الوقف للدخول
        exitI = j;
        break;
      }
      if (!gotT1 && (d > 0 ? k.high >= t1 : k.low <= t1)) {
        gotT1 = true;
        stop = entry;
      }
      if (gotT1 && (d > 0 ? k.high >= t2 : k.low <= t2)) {
        res = 2;
        exitI = j;
        break;
      }
    }
    if (exitI < 0 && gotT1) res = 1; // تحقق الهدف الأول وما زالت مفتوحة
    signals.add(PastSignal(i, d, entry, sl, t1, t2, res, exitI, why, strong));
    busyUntil = exitI < 0 ? n : exitI;
  }

  // ── توقع الشمعة القادمة: تكرار الحالات المشابهة (Walk-forward بلا نظر للمستقبل)
  String k3(_Bar b) => '${b.trend}|${b.rz}|${b.pat}|${b.mom}';
  String k2(_Bar b) => '${b.trend}|${b.pat}|${b.mom}';
  String k1(_Bar b) => '${b.trend}|${b.mom}';
  final up = <String, int>{}, tot = <String, int>{};
  void learn(int j) {
    final b = bars[j]!;
    final u = cl[j + 1] > cl[j] ? 1 : 0;
    for (final k in ['3${k3(b)}', '2${k2(b)}', '1${k1(b)}', '0']) {
      up[k] = (up[k] ?? 0) + u;
      tot[k] = (tot[k] ?? 0) + 1;
    }
  }

  (double, int) predict(_Bar b) {
    for (final k in ['3${k3(b)}', '2${k2(b)}', '1${k1(b)}', '0']) {
      final t = tot[k] ?? 0;
      if (t >= 12 || k == '0') {
        return (((up[k] ?? 0) + 1) / (t + 2), t); // تنعيم لابلاس
      }
    }
    return (0.5, 0);
  }

  final predHits = List<int>.filled(n, 0);
  var predN = 0, predOk = 0;
  for (var i = start; i < n - 1; i++) {
    if (i - 1 >= start) learn(i - 1);
    final (p, t) = predict(bars[i]!);
    if (t < 12 || (p - 0.5).abs() < 0.06) continue; // لا توقع عند عدم الوضوح
    final ok = (p > 0.5) == (cl[i + 1] > cl[i]);
    predHits[i + 1] = ok ? 1 : -1;
    predN++;
    if (ok) predOk++;
  }
  learn(n - 2);

  final last = n - 1;
  final lb = bars[last]!;
  final (pUp, sample) = predict(lb);
  final a = at[last].isNaN ? (c[last].high - c[last].low) : at[last];
  final o = cl[last];
  final cNext = o + (pUp - 0.5) * 2 * 0.6 * a;
  final whyNext = <String>[
    lb.trend == 1 ? 'اتجاه صاعد' : lb.trend == -1 ? 'اتجاه هابط' : 'بدون اتجاه',
    if (lb.hit != null) 'شمعة ${lb.hit!.ar}',
    lb.mom > 0 ? 'زخم MACD يتسارع' : 'زخم MACD يتباطأ',
    'RSI ${r[last].isNaN ? '-' : r[last].toStringAsFixed(0)}',
  ];
  final next = NextBar(pUp, sample, o, math.max(o, cNext) + 0.25 * a,
      math.min(o, cNext) - 0.25 * a, cNext, whyNext.join(' • '));

  // ── الإشارة المرتقبة قبل حدوثها
  final pending = <PendingSetup>[];
  final (dLive, whyLive, _) = decide(last);
  var live = '';
  if (dLive != 0) {
    live = '${dLive > 0 ? 'شراء' : 'بيع'} يتكوّن الآن ($whyLive) — يتأكد بإغلاق الشمعة';
  }
  void addBreak(int d, double trig, String cond) {
    final (sl, t1, t2, _) = levels(last, d, trig);
    pending.add(PendingSetup(d, trig, sl, t1, t2, cond));
  }

  final hh = math.max(c[last].high, c[last - 1].high);
  final ll = math.min(c[last].low, c[last - 1].low);
  if (lb.trend == 1) {
    addBreak(1, hh, 'الاتجاه صاعد: شراء عند اختراق قمة آخر شمعتين');
  } else if (lb.trend == -1) {
    addBreak(-1, ll, 'الاتجاه هابط: بيع عند كسر قاع آخر شمعتين');
  } else {
    var rh = c[last].high, rl = c[last].low;
    for (var j = math.max(0, last - 20); j < last; j++) {
      rh = math.max(rh, c[j].high);
      rl = math.min(rl, c[j].low);
    }
    addBreak(1, rh, 'تذبذب: شراء عند اختراق قمة النطاق');
    addBreak(-1, rl, 'تذبذب: بيع عند كسر قاع النطاق');
  }

  final pats = <PatMark>[];
  for (var i = start; i < n; i++) {
    final b = bars[i]!;
    if (b.hit != null) pats.add(PatMark(i, b.pat, shortPattern(b.hit!)));
  }

  return Forecast(
    patterns: pats,
    signals: signals,
    predHits: predHits,
    predN: predN,
    predOk: predOk,
    next: next,
    pending: pending,
    ema20: e20,
    ema50: e50,
    ema200: e200,
    liveSignal: live,
  );
}
