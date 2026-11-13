import 'dart:math' as math;
import '../models.dart';
import 'forecast.dart';
import 'indicator_panel.dart';
import 'indicators.dart';
import 'patterns.dart';
import 'tv_indicators.dart';

/// مؤشر 0.1: مصيدة سيولة + شمعة رفض.
///  1) السعر يكسر قاعاً/قمة متأرجحة (لم تُكسر من قبل) ليضرب أوامر الوقف، ثم يغلق راجعاً داخلها.
///  2) شمعة رفض على المصيدة أو خلال شمعتين بعدها: المطرقة، النجمة الهاوية، دوجي اليعسوب،
///     دوجي شاهد القبر، الرجل المشنوق، نجمة الصباح/المساء، الملقط.
///  3) الدخول عند كسر طرف شمعة الرفض خلال 3 شموع، والوقف خلف المصيدة.
///  ⭐ قوية: 40% أو أكثر من الـ23 مؤشراً (لوحة المؤشرات + مؤشرات TradingView) توافق الاتجاه.
/// كل شيء من الشموع المغلقة حتى لحظة الإشارة فقط (لا ينظر للمستقبل).
class ZeroResult {
  final List<PastSignal> signals;
  final List<PendingSetup> pending;
  const ZeroResult(this.signals, this.pending);
  int get wins => signals.where((s) => s.result > 0).length;
  int get losses => signals.where((s) => s.result < 0).length;
  int get closed => wins + losses;
  double get winRate => closed == 0 ? 0 : wins / closed;

  /// قرار 0.1 الحالي: 1 صفقة مفتوحة ، 2 تنتظر التأكيد ، 0 لا شيء.
  Decision get decision {
    if (signals.isNotEmpty && signals.last.exitI < 0) {
      final sg = signals.last;
      final side = sg.dir > 0 ? 'شراء' : 'بيع';
      final st = sg.curStop.isNaN ? (sg.result >= 1 ? sg.entry : sg.sl) : sg.curStop;
      return Decision(1, sg.dir, sg.entry, st, sg.tp1, sg.tp2,
          sg.result >= 1
              ? '0.1 $side مفتوح — تحقق TP1: أغلق النصف، والوقف المتحرك الآن عند هذا السعر'
              : '0.1 $side${sg.strong ? ' ⭐' : ''} — صفقة مفتوحة',
          sg.why, (sg.entry - sg.sl).abs());
    }
    if (pending.isNotEmpty) {
      final p = pending.first;
      return Decision(2, p.dir, p.trigger, p.sl, p.tp1, p.tp2,
          '0.1 ${p.dir > 0 ? 'شراء' : 'بيع'} ينتظر التأكيد — ادخل عند ${p.dir > 0 ? 'اختراق' : 'كسر'} السعر المحدد خلال 3 شموع، وألغِ لو انكسرت المصيدة',
          p.cond, (p.trigger - p.sl).abs());
    }
    return const Decision(0, 0, double.nan, double.nan, double.nan, double.nan,
        '0.1: لا توجد إشارة', '');
  }
}

const _rejection = {
  'Hammer', 'Shooting Star', 'Dragonfly Doji', 'Gravestone Doji', 'Hanging Man',
  'Morning Star', 'Evening Star', 'Tweezer Top', 'Tweezer Bottom',
};

/// [rr1] الهدف الأول بوحدات R (مع الوقف المتحرك بعده، مثل Alka).
ZeroResult buildZeroOne(List<Candle> c,
    {double rr1 = 0.35, double rr2 = 2.0, int history = 300, MarketSymbol? sym, bool trail = true}) {
  final n = c.length;
  if (n < 220) return const ZeroResult([], []);
  final at = atr(c, 14);
  final start = math.max(210, n - history);
  final inds = [...buildPanel(c, at), ...tvIndicators(c)];
  const L = 3, look = 30;

  /// المصيدة عند الشمعة i في الاتجاه d: سعر المستوى المكسور أو null
  double? sweepAt(int i, int d) {
    final k = c[i];
    double? lvl;
    for (var j = i - L - 1; j >= math.max(L, i - look); j--) {
      var piv = true;
      for (var q = j - L; q <= j + L; q++) {
        if (q != j && (d > 0 ? c[q].low <= c[j].low : c[q].high >= c[j].high)) {
          piv = false;
          break;
        }
      }
      if (!piv) continue;
      final p = d > 0 ? c[j].low : c[j].high;
      var swept = false;
      for (var q = j + 1; q < i; q++) {
        if (d > 0 ? c[q].low < p : c[q].high > p) {
          swept = true;
          break;
        }
      }
      if (swept) continue;
      if (!(d > 0 ? (k.low < p && k.close > p) : (k.high > p && k.close < p))) continue;
      if (lvl == null || (d > 0 ? p < lvl : p > lvl)) lvl = p;
    }
    return lvl;
  }

  bool strongAt(int s, int d) {
    var ag = 0, tot = 0;
    for (final p in inds) {
      final b = p.bias[s];
      if (b == 0) continue;
      tot++;
      if (b == d) ag++;
    }
    return tot > 0 && ag / tot >= 0.4;
  }

  final signals = <PastSignal>[];
  final pending = <PendingSetup>[];
  var busy = -1;
  for (var i = start; i < n - 1; i++) {
    if (i <= busy) continue;
    for (final d in const [1, -1]) {
      final lvl = sweepAt(i, d);
      if (lvl == null) continue;
      final k = c[i];
      // شمعة الرفض: على المصيدة أو خلال شمعتين بعدها (شموع مغلقة فقط)
      var s = -1;
      PatternHit? hit;
      for (var s0 = i; s0 <= math.min(n - 2, i + 2); s0++) {
        if (s0 > i && (d > 0 ? c[s0].low < k.low : c[s0].high > k.high)) break; // المصيدة فشلت
        // أقوى نموذج في اتجاه الصفقة: إن كان شمعة رفض نقبله، وإن كان غيره (ابتلاع، هارامي...) نرفض المصيدة
        for (final h in detectPatterns(c.sublist(s0 - 14, s0 + 1))) {
          if (h.bias == d && h.weight >= 0.3 && (hit == null || h.weight > hit.weight)) hit = h;
        }
        if (hit != null) {
          s = s0;
          break;
        }
      }
      if (s < 0 || !_rejection.contains(hit!.en)) continue;
      final a = at[s].isNaN ? (c[s].high - c[s].low) : at[s];
      final strong = strongAt(s, d);
      final why = '${hit.ar} بعد مصيدة سيولة ${d > 0 ? 'تحت قاع' : 'فوق قمة'} ${sym?.fmt(lvl) ?? lvl.toStringAsFixed(2)}'
          '${strong ? ' • ⭐ المؤشرات توافق' : ''}';
      var ext = d > 0 ? k.low : k.high;
      for (var q = i; q <= s; q++) {
        ext = d > 0 ? math.min(ext, c[q].low) : math.max(ext, c[q].high);
      }
      (double, double, double) levels(double entry) {
        final risk = ((d > 0 ? entry - ext : ext - entry) + 0.1 * a).clamp(0.7 * a, 2.5 * a).toDouble();
        return (entry - d * risk, entry + d * risk * rr1, entry + d * risk * rr2);
      }

      // التأكيد: كسر طرف شمعة الرفض خلال 3 شموع، والإلغاء لو كُسرت المصيدة
      final trig = d > 0 ? c[s].high : c[s].low;
      var ei = -1, cancelled = false;
      var entry = 0.0;
      var j = s + 1;
      for (; j < n && j <= s + 3; j++) {
        if (d > 0 ? c[j].low < k.low : c[j].high > k.high) {
          cancelled = true;
          break;
        }
        if (d > 0 ? c[j].high > trig : c[j].low < trig) {
          ei = j;
          entry = d > 0 ? math.max(trig, c[j].open) : math.min(trig, c[j].open);
          break;
        }
      }
      if (ei < 0) {
        if (!cancelled && j >= n) {
          final (sl, t1, t2) = levels(trig);
          pending
            ..clear()
            ..add(PendingSetup(d, trig, sl, t1, t2, why, s));
        }
        continue;
      }
      pending.clear();
      final (sl, t1, t2) = levels(entry);
      var stop = sl, got = false, res = 0, exitI = -1;
      var exitPrice = double.nan;
      for (var q = ei; q < n; q++) {
        final b = c[q];
        if (d > 0 ? b.low <= stop : b.high >= stop) {
          res = got ? ((stop - t2) * d >= 0 ? 2 : 1) : -1;
          exitPrice = stop;
          exitI = q;
          break;
        }
        if (!got && (d > 0 ? b.high >= t1 : b.low <= t1)) {
          got = true;
          stop = entry;
        } else if (got && trail) {
          var hh = d > 0 ? -double.infinity : double.infinity;
          for (var r = math.max(0, q - 21); r <= q; r++) {
            hh = d > 0 ? math.max(hh, c[r].high) : math.min(hh, c[r].low);
          }
          final aq = at[q].isNaN ? (b.high - b.low) : at[q];
          final cand = hh - d * 3 * aq;
          stop = d > 0 ? math.max(stop, cand) : math.min(stop, cand);
        }
        if (!trail && got && (d > 0 ? b.high >= t2 : b.low <= t2)) {
          res = 2;
          exitPrice = t2;
          exitI = q;
          break;
        }
        if (!got && q >= s + 80) {
          res = -2;
          exitPrice = b.close;
          exitI = q;
          break;
        }
        if (got && q >= s + (trail ? 300 : 80)) {
          res = (b.close - t2) * d >= 0 ? 2 : 1;
          exitPrice = b.close;
          exitI = q;
          break;
        }
      }
      if (exitI < 0 && got) res = (c[n - 1].close - t2) * d >= 0 ? 2 : 1;
      signals.add(PastSignal(s, d, entry, sl, t1, t2, res, exitI, why, strong, 0, 0, exitPrice,
          exitI < 0 ? stop : double.nan));
      busy = exitI < 0 ? n : exitI;
      break;
    }
  }
  return ZeroResult(signals, busy >= n ? const [] : pending);
}
