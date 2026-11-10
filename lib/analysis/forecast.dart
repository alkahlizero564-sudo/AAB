import 'dart:math' as math;
import '../models.dart';
import 'indicator_panel.dart';
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
  final int result; // 2 = TP2 ، 1 = TP1 ، -1 = وقف ، -2 = انتهت المهلة ، 0 = مفتوحة
  final int exitI; // شمعة الخروج (-1 لو مفتوحة)
  final String why;
  final bool strong; // تأكيدان أو أكثر
  final int agree, total; // عدد المؤشرات المتوافقة من لوحة المؤشرات
  const PastSignal(this.i, this.dir, this.entry, this.sl, this.tp1, this.tp2,
      this.result, this.exitI, this.why, this.strong,
      [this.agree = 0, this.total = 0]);
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
  final bool clear; // هل توجد ميزة احتمالية حقيقية؟ (وإلا "غير واضح")
  const NextBar(this.pUp, this.sample, this.open, this.high, this.low,
      this.close, this.why, this.clear);
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
  final List<IndNow> indicators; // حالة كل مؤشر الآن + طريقة عمله
  final int liveDir; // اتجاه الإشارة التي تتكوّن في الشمعة الحالية
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
    this.indicators = const [],
    this.liveDir = 0,
  });

  /// القرار الوحيد المعروض للمستخدم (من هذا المحرك فقط).
  Decision get decision {
    if (signals.isNotEmpty && signals.last.exitI < 0) {
      final sg = signals.last;
      final side = sg.dir > 0 ? 'شراء' : 'بيع';
      return Decision(1, sg.dir, sg.entry, sg.result == 1 ? sg.entry : sg.sl, sg.tp1, sg.tp2,
          sg.result == 1 ? '$side مفتوح — تحقق TP1 والوقف الآن عند الدخول' : '$side — صفقة مفتوحة',
          sg.why);
    }
    if (pending.isNotEmpty) {
      final p = pending.first;
      return Decision(2, p.dir, p.trigger, p.sl, p.tp1, p.tp2,
          '${p.dir > 0 ? 'شراء' : 'بيع'} ينتظر التأكيد — ادخل عند ${p.dir > 0 ? 'اختراق' : 'كسر'} السعر المحدد',
          p.cond);
    }
    if (liveDir != 0) {
      return Decision(3, liveDir, double.nan, double.nan, double.nan, double.nan,
          '${liveDir > 0 ? 'شراء' : 'بيع'} يتكوّن الآن — انتظر إغلاق الشمعة', liveSignal);
    }
    return const Decision(0, 0, double.nan, double.nan, double.nan, double.nan,
        'انتظار — لا توجد إشارة مكتملة الشروط', 'الشروط: اتجاه مع EMA200 + سبب دخول + توافق 60–90% من المؤشرات + كسر شمعة الإشارة');
  }

  /// توقع الشمعة القادمة يُعرض فقط إذا كان واضحاً ويتفق مع القرار الحالي.
  bool get showNext {
    final nb = next;
    final d = decision.dir;
    if (nb == null || !nb.clear || d == 0) return false;
    return (nb.pUp >= 0.5 ? 1 : -1) == d;
  }

  int get wins => signals.where((s) => s.result > 0).length;
  int get losses => signals.where((s) => s.result < 0).length;
  int get closed => wins + losses;
  double get winRate => closed == 0 ? 0 : wins / closed;
  double get predAcc => predN == 0 ? 0 : predOk / predN;
}

/// إعدادات فلاتر التوصيات (القيم الافتراضية مختارة بالقياس على بيانات حقيقية).
class ForecastCfg {
  final double adxMin; // أقل قوة اتجاه ADX (0 = بدون)
  final double maxExt; // أقصى ابتعاد عن EMA20 بوحدات ATR (0 = بدون)
  final bool e200; // التداول مع اتجاه EMA200 فقط
  final int confirm; // الدخول فقط بعد كسر طرف شمعة الإشارة خلال N شموع (0 = افتتاح التالية)
  final int stopLook; // عدد الشموع لحساب الوقف خلف القاع/القمة
  final double minRisk; // أقل وقف بوحدات ATR
  final bool counter; // السماح بصفقات الانعكاس عكس الاتجاه
  final int minWhy; // أقل عدد أسباب للدخول
  final bool adaptive; // إيقاف أي سبب دخول دقته ضعيفة على نفس الشارت
  final Set<String> extraTrig; // مؤشرات إضافية تُستخدم كسبب دخول
  final double confRatio; // أقل نسبة مؤشرات متوافقة مع الاتجاه (0 = بدون)
  final double confMax; // أعلى نسبة (توافق كامل غالباً = حركة منتهية ودخول متأخر)
  final double predEdge; // أقل ميزة احتمالية لإظهار توقع الشمعة
  final int predH; // أفق التوقع بالشموع
  const ForecastCfg({
    this.extraTrig = const {'cci', 'ha', 'mfi'},
    this.confRatio = 0.6,
    this.confMax = 0.9,
    this.predEdge = 0.15,
    this.predH = 1,
    this.adxMin = 0,
    this.maxExt = 0,
    this.e200 = true,
    this.confirm = 3,
    this.stopLook = 3,
    this.minRisk = 0.7,
    this.counter = true,
    this.minWhy = 1,
    this.adaptive = true,
  });
}

/// حالة مؤشر عند آخر شمعة (للعرض والشرح).
class IndNow {
  final String name, how;
  final int bias; // +1 صاعد ، -1 هابط ، 0 محايد
  final bool fired; // أعطى إشارة دخول في آخر 3 شموع
  const IndNow(this.name, this.how, this.bias, this.fired);
}

/// القرار الحالي: 0 انتظار ، 1 صفقة مفتوحة ، 2 تنتظر التأكيد ، 3 تتكوّن الآن.
class Decision {
  final int state, dir;
  final double entry, sl, tp1, tp2; // NaN عند عدم التوفر
  final String title, why;
  const Decision(this.state, this.dir, this.entry, this.sl, this.tp1, this.tp2,
      this.title, this.why);
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
Forecast buildForecast(List<Candle> c,
    {double rr1 = 1.0,
    double rr2 = 2.0,
    int history = 300,
    ForecastCfg cfg = const ForecastCfg()}) {
  final n = c.length;
  if (n < 70) return const Forecast();
  final cl = c.map((e) => e.close).toList();
  final e20 = ema(cl, 20), e50 = ema(cl, 50), e200 = ema(cl, 200);
  final r = rsi(cl, 14);
  final m = macd(cl);
  final at = atr(c, 14);
  final st = supertrend(c);
  final adx = adxCalc(c).adx;
  final panel = buildPanel(c, at);
  // توافق المؤشرات مع الاتجاه d عند الشمعة i
  (int, int) conf(int i, int d) {
    var ag = 0, tot = 0;
    for (final p in panel) {
      if (p.bias[i] == 0) continue;
      tot++;
      if (p.bias[i] == d) ag++;
    }
    final mh = m.hist[i];
    if (!mh.isNaN) {
      tot++;
      if ((mh > 0 ? 1 : -1) == d) ag++;
    }
    if (st.dir[i] != 0) {
      tot++;
      if (st.dir[i] == d) ag++;
    }
    return (ag, tot);
  }

  final start = math.max(55, n - history);

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

  // إحصائيات كل سبب دخول على نفس الشارت (تتحدث بعد إغلاق كل صفقة فقط)
  final trigW = <String, int>{}, trigN = <String, int>{};
  bool trigOk(String k) {
    if (!cfg.adaptive) return true;
    final t = trigN[k] ?? 0;
    if (t < 6) return true;
    return (trigW[k] ?? 0) / t >= 0.45;
  }

  // ── منطق التوصية لشمعة i: يُرجع (الاتجاه، السبب، قوي؟، مفاتيح الأسباب)
  (int, String, bool, List<String>) decide(int i) {
    final b = bars[i]!;
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    for (final d in const [1, -1]) {
      final why = <String>[];
      final keys = <String>[];
      void add(String k, String t) {
        if (!trigOk(k)) return;
        keys.add(k);
        why.add(t);
      }

      if (b.pat == d) add('p:${b.hit!.en}', 'شمعة ${b.hit!.ar}');
      if (b.div == d) add('div', 'انحراف RSI ${d > 0 ? 'إيجابي' : 'سلبي'}');
      if (b.ema == d) add('ema', 'ارتداد من EMA20');
      if (b.macdX == d) add('macd', 'تقاطع MACD');
      for (final p in panel) {
        if (cfg.extraTrig.contains(p.key) && p.trig[i] == d) add('i:${p.key}', p.name);
      }
      final rv = r[i];
      final rsiOk = rv.isNaN || (d > 0 ? rv < 72 : rv > 28);
      if (!rsiOk || why.isEmpty || why.length < cfg.minWhy) continue;
      if (cfg.confRatio > 0) {
        final (ag, tot) = conf(i, d);
        if (tot == 0 || ag / tot < cfg.confRatio || ag / tot >= cfg.confMax) continue;
      }
      if (b.trend == d) {
        if (cfg.adxMin > 0 && !adx[i].isNaN && adx[i] < cfg.adxMin) continue;
        if (cfg.maxExt > 0 && !e20[i].isNaN && (cl[i] - e20[i]).abs() > cfg.maxExt * a) {
          continue;
        }
        if (cfg.e200 && !e200[i].isNaN && (d > 0 ? cl[i] < e200[i] : cl[i] > e200[i])) {
          continue;
        }
        return (d, why.join(' + '), why.length >= 2, keys);
      }
      if (!cfg.counter) continue;
      if (b.trend == 0 && why.length >= 2) return (d, why.join(' + '), true, keys);
      if (b.trend == -d && b.div == d && b.pat == d) {
        return (d, 'انعكاس: ${why.join(' + ')}', true, keys);
      }
    }
    return (0, '', false, const []);
  }

  (double, double, double, double) levels(int i, int d, double entry) {
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    var ext = d > 0 ? c[i].low : c[i].high;
    for (var j = math.max(0, i - cfg.stopLook + 1); j <= i; j++) {
      ext = d > 0 ? math.min(ext, c[j].low) : math.max(ext, c[j].high);
    }
    var risk = (d > 0 ? entry - ext : ext - entry) + 0.1 * a;
    risk = risk.clamp(cfg.minRisk * a, math.max(2.5, cfg.minRisk + 0.5) * a).toDouble();
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
  (int, int, String)? waiting; // آخر إشارة لم تتأكد بعد (الشمعة، الاتجاه، السبب)
  for (var i = start; i < n - 1; i++) {
    if (i <= busyUntil) continue;
    final (d, why, strong, keys) = decide(i);
    if (d == 0) continue;
    // الدخول: افتتاح الشمعة التالية ، أو (مع التأكيد) عند كسر طرف شمعة الإشارة
    var entryI = i + 1;
    var entry = c[i + 1].open;
    if (cfg.confirm > 0) {
      final trig = d > 0 ? c[i].high : c[i].low;
      entryI = -1;
      var cancelled = false;
      var j = i + 1;
      for (; j < n && j <= i + cfg.confirm; j++) {
        final k = c[j];
        // إلغاء لو ضرب السعر قاع/قمة شمعة الإشارة قبل التأكيد
        if (d > 0 ? k.low < c[i].low : k.high > c[i].high) {
          cancelled = true;
          break;
        }
        if (d > 0 ? k.high > trig : k.low < trig) {
          entryI = j;
          entry = d > 0 ? math.max(trig, k.open) : math.min(trig, k.open);
          break;
        }
      }
      if (entryI < 0) {
        // وصلنا لنهاية البيانات والمهلة لم تنتهِ ← إشارة مرتقبة
        if (!cancelled && j >= n) waiting = (i, d, why);
        continue; // لم تتأكد ← لا صفقة
      }
    }
    waiting = null;
    final (sl, t1, t2, _) = levels(i, d, entry);
    var res = 0, exitI = -1;
    var stop = sl;
    var gotT1 = false;
    for (var j = entryI; j < n; j++) {
      final k = c[j];
      // في شمعة الدخول نفسها مع التأكيد: لا نعرف الترتيب ← نفحص الوقف فقط
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
      if (j >= i + 80) {
        // انتهت المهلة: تُغلق بسعر الإغلاق
        res = gotT1 ? 1 : -2;
        exitI = j;
        break;
      }
    }
    if (exitI < 0 && gotT1) res = 1; // تحقق الهدف الأول وما زالت مفتوحة
    final (ag, tot) = conf(i, d);
    signals.add(PastSignal(i, d, entry, sl, t1, t2, res, exitI, why, strong, ag, tot));
    busyUntil = exitI < 0 ? n : exitI;
    if (exitI >= 0 || res != 0) {
      for (final k in keys) {
        trigN[k] = (trigN[k] ?? 0) + 1;
        if (res > 0) trigW[k] = (trigW[k] ?? 0) + 1;
      }
    }
  }

  // ── توقع الشمعة القادمة: تكرار الحالات المشابهة (Walk-forward بلا نظر للمستقبل)
  String k3(_Bar b) => '${b.trend}|${b.rz}|${b.pat}|${b.mom}';
  String k2(_Bar b) => '${b.trend}|${b.pat}|${b.mom}';
  String k1(_Bar b) => '${b.trend}|${b.mom}';
  final up = <String, int>{}, tot = <String, int>{};
  void learn(int j) {
    final b = bars[j]!;
    final u = cl[j + cfg.predH] > cl[j] ? 1 : 0;
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
  final hz = cfg.predH;
  for (var i = start; i < n - hz; i++) {
    // نتعلم فقط من الشموع التي عُرفت نتيجتها عند الشمعة i
    if (i - hz >= start) learn(i - hz);
    final (p, t) = predict(bars[i]!);
    if (t < 12 || (p - 0.5).abs() < cfg.predEdge) continue; // لا توقع عند عدم الوضوح
    final ok = (p > 0.5) == (cl[i + hz] > cl[i]);
    predHits[i + hz] = ok ? 1 : -1;
    predN++;
    if (ok) predOk++;
  }
  for (var j = math.max(start, n - 2 * hz); j <= n - 1 - hz; j++) {
    if (j >= start) learn(j);
  }

  final last = n - 1;
  final lb = bars[last]!;
  final (pUp, sample) = predict(lb);
  final a = at[last].isNaN ? (c[last].high - c[last].low) : at[last];
  final o = cl[last];
  final clear = sample >= 12 && (pUp - 0.5).abs() >= cfg.predEdge;
  final cNext = clear ? o + (pUp - 0.5) * 2 * 0.6 * a : o;
  final whyNext = <String>[
    lb.trend == 1 ? 'اتجاه صاعد' : lb.trend == -1 ? 'اتجاه هابط' : 'بدون اتجاه',
    if (lb.hit != null) 'شمعة ${lb.hit!.ar}',
    lb.mom > 0 ? 'زخم MACD يتسارع' : 'زخم MACD يتباطأ',
    'RSI ${r[last].isNaN ? '-' : r[last].toStringAsFixed(0)}',
  ];
  final next = NextBar(pUp, sample, o, math.max(o, cNext) + 0.25 * a,
      math.min(o, cNext) - 0.25 * a, cNext, whyNext.join(' • '), clear);

  // ── الإشارة المرتقبة قبل حدوثها: إشارة ظهرت وتنتظر كسر طرف شمعتها للدخول
  final pending = <PendingSetup>[];
  final w = waiting;
  if (w != null && busyUntil < n) {
    final (wi, wd, wwhy) = w;
    final trig = wd > 0 ? c[wi].high : c[wi].low;
    final (sl, t1, t2, _) = levels(wi, wd, trig);
    pending.add(PendingSetup(wd, trig, sl, t1, t2,
        '${wd > 0 ? 'شراء' : 'بيع'} ينتظر التأكيد ($wwhy) — ادخل عند ${wd > 0 ? 'اختراق' : 'كسر'}'));
  }
  var live = '';
  var liveDir = 0;
  if (busyUntil < n && pending.isEmpty) {
    final (dLive, whyLive, _, _) = decide(last);
    liveDir = dLive;
    if (dLive != 0) {
      live = '${dLive > 0 ? 'شراء' : 'بيع'} يتكوّن الآن ($whyLive) — بعد إغلاق الشمعة '
          'يكون الدخول عند ${dLive > 0 ? 'اختراق قمتها' : 'كسر قاعها'}';
    }
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
    liveDir: liveDir,
    indicators: [
      for (final p in panel)
        IndNow(p.name, p.how, p.bias[last],
            p.trig.sublist(math.max(0, last - 2)).any((v) => v != 0)),
    ],
  );
}
