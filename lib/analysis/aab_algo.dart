import 'dart:math' as math;
import '../models.dart';
import 'indicator_panel.dart';
import 'indicators.dart';

/// إشارة من مؤشر AAB Algo مع نتيجتها الحقيقية بعدها.
class AlgoSignal {
  final int i; // شمعة الإشارة (مغلقة)
  final int dir; // +1 شراء / -1 بيع
  final bool strong; // إشارة قوية (+): مع EMA200 وتوافق المؤشرات
  final double entry, sl, tp1, tp2, tp3;
  final int result; // 3/2/1 = أعلى هدف تحقق ، -1 وقف ، 0 مفتوحة
  final int exitI;
  final double sens; // الحساسية المستخدمة
  const AlgoSignal(this.i, this.dir, this.strong, this.entry, this.sl, this.tp1,
      this.tp2, this.tp3, this.result, this.exitI, this.sens);
}

class AlgoResult {
  final List<int> trend; // اتجاه كل شمعة +1/-1/0
  final List<int> power; // قوة الاتجاه 0 ضعيف ، 1 متوسط ، 2 قوي (لتلوين الشموع)
  final List<double> line; // خط الاتجاه (Trend Tracer) — NaN قبل البداية
  final List<double> zoneHi, zoneLo; // مناطق الانعكاس (تشبع)
  final List<AlgoSignal> signals;
  final double sens; // الحساسية الحالية المختارة تلقائياً
  const AlgoResult(this.trend, this.power, this.line, this.zoneHi, this.zoneLo,
      this.signals, this.sens);

  int get wins => signals.where((s) => s.result > 0).length;
  int get losses => signals.where((s) => s.result < 0).length;
  int get closed => wins + losses;
  double get winRate => closed == 0 ? 0 : wins / closed;
}

class _Run {
  final List<int> dir;
  final List<double> line;
  final List<AlgoSignal> sigs;
  _Run(this.dir, this.line, this.sigs);
}

/// قلب المؤشر لحساسية واحدة: خط اتجاه متكيّف (ATR مُنعّم على سعر مُنعّم)
/// يتحول الاتجاه فقط عند إغلاق خلف الخط — فلا يعيد الرسم.
_Run _core(List<Candle> c, double sens, List<double> at, List<double> e200,
    List<Ind> panel, double rr1, double rr2, double rr3) {
  final n = c.length;
  final src = ema(c.map((e) => (e.high + e.low + e.close) / 3).toList(), 3);
  final dir = List<int>.filled(n, 0);
  final line = List<double>.filled(n, double.nan);
  final sigs = <AlgoSignal>[];
  var d = 0;
  var up = double.nan, dn = double.nan;
  var busy = -1;
  for (var i = 1; i < n; i++) {
    if (at[i].isNaN || src[i].isNaN) continue;
    final band = sens * at[i];
    var nu = src[i] - band, nd = src[i] + band;
    if (!up.isNaN && c[i - 1].close > up) nu = math.max(nu, up);
    if (!dn.isNaN && c[i - 1].close < dn) nd = math.min(nd, dn);
    var flip = 0;
    if (d <= 0 && !dn.isNaN && c[i].close > dn) {
      d = 1;
      flip = 1;
    } else if (d >= 0 && !up.isNaN && c[i].close < up) {
      d = -1;
      flip = -1;
    } else if (d == 0) {
      d = c[i].close >= src[i] ? 1 : -1;
    }
    up = nu;
    dn = nd;
    dir[i] = d;
    line[i] = d > 0 ? up : dn;

    if (flip != 0 && i < n - 1 && i > busy) {
      // قوة الإشارة: مع EMA200 + توافق 60–90% من لوحة المؤشرات
      var ag = 0, tot = 0;
      for (final p in panel) {
        if (p.bias[i] == 0) continue;
        tot++;
        if (p.bias[i] == flip) ag++;
      }
      final ratio = tot == 0 ? 0.0 : ag / tot;
      final withTrend = !e200[i].isNaN && (flip > 0 ? c[i].close > e200[i] : c[i].close < e200[i]);
      final strong = withTrend && ratio >= 0.6 && ratio < 0.9;
      // الدخول: افتتاح الشمعة التالية • الوقف: خلف الخط المعاكس
      final entry = c[i + 1].open;
      var risk = (entry - (flip > 0 ? up : dn)).abs() + 0.1 * at[i];
      risk = risk.clamp(0.8 * at[i], 3.0 * at[i]).toDouble();
      final sl = entry - flip * risk;
      final t1 = entry + flip * risk * rr1;
      final t2 = entry + flip * risk * rr2;
      final t3 = entry + flip * risk * rr3;
      var res = 0, exitI = -1, best = 0;
      var stop = sl;
      for (var j = i + 1; j < n && j <= i + 100; j++) {
        final k = c[j];
        if (flip > 0 ? k.low <= stop : k.high >= stop) {
          res = best > 0 ? best : -1;
          exitI = j;
          break;
        }
        if (best < 1 && (flip > 0 ? k.high >= t1 : k.low <= t1)) {
          best = 1;
          stop = entry; // بعد الهدف الأول: الوقف عند الدخول
        }
        if (best >= 1 && best < 2 && (flip > 0 ? k.high >= t2 : k.low <= t2)) {
          best = 2;
          stop = t1; // بعد الهدف الثاني: الوقف عند الهدف الأول
        }
        if (best >= 2 && (flip > 0 ? k.high >= t3 : k.low <= t3)) {
          res = 3;
          exitI = j;
          break;
        }
        if (j == i + 100) {
          res = best > 0 ? best : -1;
          exitI = j;
        }
      }
      if (exitI < 0 && best > 0) res = best;
      sigs.add(AlgoSignal(i, flip, strong, entry, sl, t1, t2, t3, res, exitI, sens));
      busy = exitI < 0 ? n : exitI;
    }
  }
  return _Run(dir, line, sigs);
}

/// مؤشر AAB Algo.
///  • [sens] حساسية ثابتة، أو null = اختيار تلقائي: عند كل شمعة تُستخدم الحساسية
///    التي حققت أفضل نتيجة على صفقات أُغلقت قبلها فقط (بدون نظر للمستقبل).
///  • [strongOnly] إظهار الإشارات القوية فقط.
AlgoResult aabAlgo(List<Candle> c,
    {double? sens,
    bool strongOnly = false,
    double rr1 = 1,
    double rr2 = 2,
    double rr3 = 3,
    bool withPanel = true, // false = للرسم فقط (أسرع، بدون تصنيف الإشارات القوية)
    List<double> choices = const [1.5, 2.0, 2.5, 3.0, 4.0]}) {
  final n = c.length;
  if (n < 60) {
    return const AlgoResult([], [], [], [], [], [], 2.5);
  }
  final at = atr(c, 10);
  final cl = c.map((e) => e.close).toList();
  final e200 = ema(cl, 200);
  final panel = withPanel ? buildPanel(c, atr(c, 14)) : <Ind>[];
  final opts = sens != null ? [sens] : choices;
  final runs = {for (final s in opts) s: _core(c, s, at, e200, panel, rr1, rr2, rr3)};

  // نتيجة صفقة بوحدات R (نفس إدارة الصفقة: نصف عند كل هدف)
  double rOf(AlgoSignal s) => s.result == 3
      ? (rr1 + rr2 + rr3) / 3
      : s.result == 2
          ? (rr1 + rr2 + rr1) / 3
          : s.result == 1
              ? rr1 / 3
              : -1;

  // الحساسية النشطة عند كل شمعة (اختيار تلقائي متدرّج)
  final active = List<double>.filled(n, opts.first);
  if (opts.length > 1) {
    final events = <(int, double, double)>[]; // (شمعة الإغلاق، الحساسية، R)
    for (final e in runs.entries) {
      for (final s in e.value.sigs) {
        if (s.exitI >= 0) events.add((s.exitI, e.key, rOf(s)));
      }
    }
    events.sort((a, b) => a.$1.compareTo(b.$1));
    final score = {for (final s in opts) s: 0.0};
    final count = {for (final s in opts) s: 0};
    var ev = 0;
    var cur = opts[opts.length ~/ 2];
    for (var i = 0; i < n; i++) {
      while (ev < events.length && events[ev].$1 < i) {
        final (_, s, r) = events[ev];
        score[s] = score[s]! * 0.97 + r; // أحدث الصفقات أهم
        count[s] = count[s]! + 1;
        ev++;
      }
      var best = cur, bestV = -1e9;
      for (final s in opts) {
        if (count[s]! < 4) continue;
        if (score[s]! > bestV) {
          bestV = score[s]!;
          best = s;
        }
      }
      cur = best;
      active[i] = cur;
    }
  }

  // دمج: كل شمعة تأخذ خط واتجاه الحساسية النشطة، والإشارات من الحساسية النشطة وقتها
  final trend = List<int>.filled(n, 0);
  final line = List<double>.filled(n, double.nan);
  for (var i = 0; i < n; i++) {
    final r = runs[active[i]]!;
    trend[i] = r.dir[i];
    line[i] = r.line[i];
  }
  final sigs = <AlgoSignal>[];
  var busy = -1;
  final all = [for (final r in runs.values) ...r.sigs]..sort((a, b) => a.i.compareTo(b.i));
  for (final s in all) {
    if (s.sens != active[s.i] || s.i <= busy) continue;
    if (strongOnly && !s.strong) continue;
    sigs.add(s);
    busy = s.exitI < 0 ? n : s.exitI;
  }

  // قوة الاتجاه لتلوين الشموع: ميل خط الاتجاه + بُعد السعر عنه
  final power = List<int>.filled(n, 0);
  for (var i = 5; i < n; i++) {
    if (line[i].isNaN || line[i - 5].isNaN || at[i].isNaN || trend[i] == 0) continue;
    final slope = (line[i] - line[i - 5]) * trend[i] / at[i];
    power[i] = slope > 1.0 ? 2 : (slope > 0.2 ? 1 : 0);
  }
  // مناطق الانعكاس: متوسط 50 ± 2.5 ATR (السعر خارجها = حركة ممتدة)
  final mid = ema(cl, 50);
  final at14 = atr(c, 14);
  final zh = List<double>.filled(n, double.nan), zl = List<double>.filled(n, double.nan);
  for (var i = 0; i < n; i++) {
    if (mid[i].isNaN || at14[i].isNaN) continue;
    zh[i] = mid[i] + 2.5 * at14[i];
    zl[i] = mid[i] - 2.5 * at14[i];
  }
  return AlgoResult(trend, power, line, zh, zl, sigs, active[n - 1]);
}
