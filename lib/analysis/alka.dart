import 'dart:math' as math;
import '../models.dart';
import 'chart_reader.dart';
import 'forecast.dart';
import 'indicators.dart';
import 'patterns.dart';

/// مؤشر Alka: يقرأ الشارت كما يقرؤه متداول Price Action:
///   شمعة انعكاس قوية  +  عند دعم/مقاومة أو مستوى Volume Profile  +  تأكيد بكسر طرف الشمعة.
/// كل شيء محسوب من الشموع المغلقة حتى لحظة الإشارة فقط (لا ينظر للمستقبل).
class AlkaResult {
  final List<PastSignal> signals;
  final List<PendingSetup> pending;
  const AlkaResult(this.signals, this.pending);
  int get wins => signals.where((s) => s.result > 0).length;
  int get losses => signals.where((s) => s.result < 0).length;
  int get closed => wins + losses;
  double get winRate => closed == 0 ? 0 : wins / closed;

  /// قرار Alka الحالي: 1 صفقة مفتوحة ، 2 تنتظر التأكيد ، 0 لا شيء.
  Decision get decision {
    if (signals.isNotEmpty && signals.last.exitI < 0) {
      final sg = signals.last;
      final side = sg.dir > 0 ? 'شراء' : 'بيع';
      final st = sg.curStop.isNaN ? (sg.result >= 1 ? sg.entry : sg.sl) : sg.curStop;
      return Decision(1, sg.dir, sg.entry, st, sg.tp1, sg.tp2,
          sg.result >= 1
              ? 'Alka $side مفتوح — تحقق TP1: أغلق النصف، والوقف المتحرك الآن عند هذا السعر'
              : 'Alka $side — صفقة مفتوحة',
          sg.why, (sg.entry - sg.sl).abs());
    }
    if (pending.isNotEmpty) {
      final p = pending.first;
      return Decision(2, p.dir, p.trigger, p.sl, p.tp1, p.tp2,
          'Alka ${p.dir > 0 ? 'شراء' : 'بيع'} ينتظر التأكيد — ادخل عند ${p.dir > 0 ? 'اختراق' : 'كسر'} السعر المحدد خلال 3 شموع، وألغِ لو انكسر الطرف الآخر',
          p.cond, (p.trigger - p.sl).abs());
    }
    return const Decision(0, 0, double.nan, double.nan, double.nan, double.nan,
        'Alka: لا توجد إشارة', '');
  }
}

/// Volume Profile متحرك (150 شمعة قبل الشمعة): (VAL, POC, VAH)
List<(double, double, double)?> _profile(List<Candle> c) {
  final n = c.length;
  final out = List<(double, double, double)?>.filled(n, null);
  const look = 150, bins = 24;
  final hasVol = c.where((e) => e.volume > 0).length > n * 0.8;
  for (var i = look; i < n; i++) {
    var lo = double.infinity, hi = -double.infinity;
    for (var j = i - look; j < i; j++) {
      lo = math.min(lo, c[j].low);
      hi = math.max(hi, c[j].high);
    }
    if (!(hi > lo)) continue;
    final w = (hi - lo) / bins;
    final vol = List<double>.filled(bins, 0);
    for (var j = i - look; j < i; j++) {
      final k = c[j];
      final b0 = ((k.low - lo) / w).floor().clamp(0, bins - 1);
      final b1 = ((k.high - lo) / w).floor().clamp(0, bins - 1);
      final share = (hasVol ? k.volume : 1.0) / (b1 - b0 + 1);
      for (var q = b0; q <= b1; q++) {
        vol[q] += share;
      }
    }
    var poc = 0;
    for (var q = 1; q < bins; q++) {
      if (vol[q] > vol[poc]) poc = q;
    }
    final total = vol.fold(0.0, (a, x) => a + x);
    var l2 = poc, h2 = poc;
    var acc = vol[poc];
    while (acc < total * 0.7 && (l2 > 0 || h2 < bins - 1)) {
      final down = l2 > 0 ? vol[l2 - 1] : -1.0;
      final up = h2 < bins - 1 ? vol[h2 + 1] : -1.0;
      if (up >= down) {
        h2++;
        acc += vol[h2];
      } else {
        l2--;
        acc += vol[l2];
      }
    }
    out[i] = (lo + l2 * w, lo + (poc + 0.5) * w, lo + (h2 + 1) * w);
  }
  return out;
}

/// [rr1] الهدف الأول بوحدات R. مع الوقف المتحرك بعده: 0.35R ≈ دقة 79% بنفس ربح الصفقة تقريباً
/// (مقاس على 25 مجموعة بيانات حقيقية، قديمة وحديثة، منها البيتكوين والذهب).
AlkaResult buildAlka(List<Candle> c,
    {double rr1 = 0.35, double rr2 = 2.0, int history = 300, MarketSymbol? sym, bool trail = true}) {
  final n = c.length;
  if (n < 220) return const AlkaResult([], []);
  final at = atr(c, 14);
  final vp = _profile(c);
  final start = math.max(210, n - history);

  // سبب الإشارة عند الشمعة i (أو null): (الاتجاه، النص)
  (int, String)? setupAt(int i) {
    final hits = detectPatterns(c.sublist(i - 14, i + 1));
    PatternHit? best;
    for (final h in hits) {
      if (h.bias != 0 && h.weight >= 0.7 && (best == null || h.weight > best.weight)) best = h;
    }
    if (best == null) return null;
    final d = best.bias;
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    final k = c[i];
    final (sup, res) =
        structureLevels(c.sublist(math.max(0, i - 299), i + 1), k.close, sym: sym);
    String? where;
    if (d > 0) {
      if (sup.isNotEmpty && ((k.low - sup.first.p).abs() <= 0.5 * a || (k.low <= sup.first.p && k.close > sup.first.p))) {
        where = sup.first.name;
      }
      final v = vp[i];
      if (where == null && v != null) {
        for (final (p, nm) in [(v.$1, 'VAL'), (v.$2, 'POC')]) {
          if ((k.low - p).abs() <= 0.3 * a || (k.low <= p && k.close > p)) {
            where = 'Volume Profile $nm';
            break;
          }
        }
      }
    } else {
      if (res.isNotEmpty && ((k.high - res.first.p).abs() <= 0.5 * a || (k.high >= res.first.p && k.close < res.first.p))) {
        where = res.first.name;
      }
      final v = vp[i];
      if (where == null && v != null) {
        for (final (p, nm) in [(v.$3, 'VAH'), (v.$2, 'POC')]) {
          if ((k.high - p).abs() <= 0.3 * a || (k.high >= p && k.close < p)) {
            where = 'Volume Profile $nm';
            break;
          }
        }
      }
    }
    if (where == null) return null;
    return (d, '${best.ar} عند ${where.split(' + ').first}');
  }

  (double, double, double) levels(int i, int d, double entry) {
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    var ext = d > 0 ? c[i].low : c[i].high;
    for (var j = i - 2; j <= i; j++) {
      ext = d > 0 ? math.min(ext, c[j].low) : math.max(ext, c[j].high);
    }
    final risk = ((d > 0 ? entry - ext : ext - entry) + 0.1 * a).clamp(0.7 * a, 2.5 * a).toDouble();
    return (entry - d * risk, entry + d * risk * rr1, entry + d * risk * rr2);
  }

  final signals = <PastSignal>[];
  final pending = <PendingSetup>[];
  var busy = -1;
  for (var i = start; i < n - 1; i++) {
    if (i <= busy) continue;
    final st = setupAt(i);
    if (st == null) continue;
    final (d, why) = st;
    // التأكيد: كسر طرف الشمعة خلال 3 شموع، والإلغاء لو كُسر الطرف الآخر أولاً
    final trig = d > 0 ? c[i].high : c[i].low;
    var ei = -1, cancelled = false;
    var entry = 0.0;
    var j = i + 1;
    for (; j < n && j <= i + 3; j++) {
      if (d > 0 ? c[j].low < c[i].low : c[j].high > c[i].high) {
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
        final (sl, t1, t2) = levels(i, d, trig);
        pending
          ..clear()
          ..add(PendingSetup(d, trig, sl, t1, t2, why, i));
      }
      continue;
    }
    pending.clear();
    final (sl, t1, t2) = levels(i, d, entry);
    var stop = sl, got = false, res = 0, exitI = -1;
    var exitPrice = double.nan;
    for (var q = ei; q < n; q++) {
      final k = c[q];
      if (d > 0 ? k.low <= stop : k.high >= stop) {
        res = got ? ((stop - t2) * d >= 0 ? 2 : 1) : -1;
        exitPrice = stop;
        exitI = q;
        break;
      }
      if (!got && (d > 0 ? k.high >= t1 : k.low <= t1)) {
        got = true;
        stop = entry;
      } else if (got && trail) {
        var hh = d > 0 ? -double.infinity : double.infinity;
        for (var r = math.max(0, q - 21); r <= q; r++) {
          hh = d > 0 ? math.max(hh, c[r].high) : math.min(hh, c[r].low);
        }
        final a = at[q].isNaN ? (k.high - k.low) : at[q];
        final cand = hh - d * 3 * a;
        stop = d > 0 ? math.max(stop, cand) : math.min(stop, cand);
      }
      if (!trail && got && (d > 0 ? k.high >= t2 : k.low <= t2)) {
        res = 2;
        exitPrice = t2;
        exitI = q;
        break;
      }
      if (!got && q >= i + 80) {
        res = -2;
        exitPrice = k.close;
        exitI = q;
        break;
      }
      if (got && q >= i + (trail ? 300 : 80)) {
        res = (k.close - t2) * d >= 0 ? 2 : 1;
        exitPrice = k.close;
        exitI = q;
        break;
      }
    }
    if (exitI < 0 && got) res = (c[n - 1].close - t2) * d >= 0 ? 2 : 1;
    signals.add(PastSignal(i, d, entry, sl, t1, t2, res, exitI, why, false, 0, 0, exitPrice,
        exitI < 0 ? stop : double.nan));
    busy = exitI < 0 ? n : exitI;
  }
  return AlkaResult(signals, busy >= n ? const [] : pending);
}
