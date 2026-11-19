import 'dart:math' as math;
import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';
import 'st_indicator.dart';

/// مؤشر النجوم: كل إشارات Mp في مؤشر واحد، ولكل إشارة نجوم الثقة (حتى 3):
///  - نجمتان إن كانت درجة ثقة ST في أعلى 10% ، أو نجمة إن كانت في أعلى 30%
///  - + نجمة إن كان السوق هادئاً (ATR14 أقل من 0.9 من متوسطه على 100 شمعة)
/// الحدود من ذهب وبيتكوين 2016-2020 فقط. بهدف 1R على 2021-2026: 0★ 54.5% ، 1★ 56.2% ، 2★ 59.6% ، 3★ 64.4%،
/// وعلى أسواق لم يرها: 55.3% ، 57.2% ، 58.2% ، 61.4% (كل نجمة أعلى من التي قبلها).
class StarResult {
  final AllResult res; // الإشارات التي نجومها ≥ الحد الأدنى
  final Map<(int, int), int> stars; // (شمعة الإشارة، الاتجاه) → عدد النجوم
  final Set<(int, int)> hot; // ضغط 🔥: نجمتان أو 3 في سوق مضغوط (ATR5/ATR50 < 0.6)
  final Set<(int, int)> held; // قاع أعلى فوق الدعم (للشراء) / قمة أدنى تحت المقاومة (للبيع) دون لمسه
  final Set<(int, int)> near; // دخول ممتاز: سعر الدخول قريب من قاع/قمة آخر 5 شموع (< 0.75 ATR)
  const StarResult(this.res, this.stars, [this.hot = const {}, this.held = const {}, this.near = const {}]);
  static const empty = StarResult(AllResult([], [], [], [], 'نجوم'), {});
  int of(int i, int dir) => stars[(i, dir)] ?? 0;
  bool isHot(int i, int dir) => hot.contains((i, dir));
  bool isHeld(int i, int dir) => held.contains((i, dir));
  bool isNear(int i, int dir) => near.contains((i, dir));
}

/// حد أعلى 10% من درجات ثقة ST (من بيانات التدريب نفسها)
const stTop10 = 0.5823269046477569;

StarResult buildStar(List<Candle> c, AllResult mp, {int minStars = 0}) {
  if (c.length < 120) return StarResult.empty;
  final sc = StScorer(c);
  final at = atr(c, 14);
  final am = sma(at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
  // ضغط 🔥 (فكرة Squeeze في TradingView): التذبذب في آخر 5 شموع أقل من 60% من آخر 50.
  // مع نجمتين أو 3 (ذهب وبيتكوين 15m/1h/4h، بهدف 1R): 70.3% (2016-2020) و67.7% (2021-2026)
  // مقابل 60.4% و58.4% بدونه. لا يفيد مع 0-1 نجمة.
  final a5 = atr(c, 5), a50 = atr(c, 50);
  bool squeezed(int i) => i >= 0 && i < c.length && !a5[i].isNaN && !a50[i].isNaN && a50[i] > 0 && a5[i] / a50[i] < 0.6;
  bool calm(int i) => i >= 0 && i < c.length && !at[i].isNaN && !am[i].isNaN && am[i] > 0 && at[i] / am[i] < 0.9;
  int starsOf(int i, int d, String src) {
    final p = sc.score(i, d, src);
    final g = (p >= stTop10 ? 2 : p >= stThreshold ? 1 : 0) + (calm(i) ? 1 : 0);
    return g > 3 ? 3 : g;
  }

  // مكان الدخول: بُعد سعر الدخول عن قاع (للشراء) / قمة (للبيع) آخر 5 شموع بوحدات ATR.
  // ذهب وبيتكوين 15m/1h (2016-2020 / 2021-2026) بهدف 1R: القريب (< 0.75) 58-64%، والمتأخر (≥ 1.25) 47-56%.
  // على الفريمات الأقل من 4h نحذف الدخول المتأخر، ونعلّم القريب «دخول ممتاز». على 4h وما فوق لا فرق ثابت.
  double dist(int i, int d, double entry) {
    if (i < 4 || i >= c.length || at[i].isNaN || !(at[i] > 0)) return 1;
    var ext = d > 0 ? double.infinity : -double.infinity;
    for (var q = i - 4; q <= i; q++) {
      ext = d > 0 ? math.min(ext, c[q].low) : math.max(ext, c[q].high);
    }
    return (entry - ext) * d / at[i];
  }

  final gaps = [for (var q = math.max(1, c.length - 200); q < c.length; q++) c[q].time.difference(c[q - 1].time).inMinutes.abs()]..sort();
  final intraday = gaps.isNotEmpty && gaps[gaps.length ~/ 2] < 240;
  final near = <(int, int)>{};
  final stars = <(int, int), int>{};
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    final g = starsOf(s.i, s.dir, mp.sources[q]);
    stars[(s.i, s.dir)] = g;
    final dd = dist(s.i, s.dir, s.entry);
    if (intraday && dd < 0.75) near.add((s.i, s.dir));
    if (g >= minStars && !(intraday && dd >= 1.25)) {
      sigs.add(s);
      src.add(mp.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    final g = p.i < 0 ? 0 : starsOf(p.i, p.dir, mp.pendingSrc[q]);
    stars[(p.i, p.dir)] = g;
    final dd = p.i < 0 ? 1.0 : dist(p.i, p.dir, p.trigger);
    if (intraday && dd < 0.75) near.add((p.i, p.dir));
    if (g >= minStars && !(intraday && dd >= 1.25)) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
    }
  }
  final hot = <(int, int)>{
    for (final e in stars.entries)
      if (e.value >= 2 && squeezed(e.key.$1)) e.key
  };
  final held = <(int, int)>{
    for (final key in stars.keys)
      if (heldAboveLevel(c, at, key.$1, key.$2)) key
  };
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final keep = [for (var q = 0; q < pend.length; q++) if (!openDirs.contains(pend[q].dir)) q];
  return StarResult(AllResult(sigs, src, [for (final q in keep) pend[q]], [for (final q in keep) pSrc[q]], 'نجوم'), stars, hot, held, near);
}

/// «قاع أعلى» (للشراء): أدنى سعر في آخر 3 شموع فوق أقرب دعم تحته بمسافة 0.3-1 ATR، أي أن السعر
/// ارتد قبل أن يلمس الدعم. «قمة أدنى» للبيع بالعكس تحت المقاومة. الدعم/المقاومة من قمم وقيعان
/// مؤكدة (3 شموع يميناً ويساراً) في آخر 300 شمعة قبل الإشارة، مجمّعة بنصف ATR.
/// ذهب وبيتكوين 15m/1h/4h بهدف 1R: 58.8% (2016-2020) و59.8% (2021-2026) مقابل 55.0% و55.7% للكل؛
/// ومع 2-3 نجوم 64.0% و65.0%.
bool heldAboveLevel(List<Candle> c, List<double> at, int i, int d) {
  if (i < 20 || i >= c.length || at[i].isNaN || !(at[i] > 0)) return false;
  final a = at[i], px = c[i].close;
  final pts = <double>[];
  for (var j = math.max(3, i - 300); j <= i - 3; j++) {
    var isH = true, isL = true;
    for (var q = j - 3; q <= j + 3; q++) {
      if (q == j) continue;
      if (c[q].high >= c[j].high) isH = false;
      if (c[q].low <= c[j].low) isL = false;
    }
    if (isH) pts.add(c[j].high);
    if (isL) pts.add(c[j].low);
  }
  if (pts.isEmpty) return false;
  pts.sort();
  var ext = d > 0 ? c[i].low : c[i].high;
  for (var q = i - 2; q <= i; q++) {
    ext = d > 0 ? math.min(ext, c[q].low) : math.max(ext, c[q].high);
  }
  var best = double.infinity;
  var g0 = 0;
  while (g0 < pts.length) {
    var g1 = g0;
    while (g1 + 1 < pts.length && pts[g1 + 1] - pts[g0] <= 0.5 * a) {
      g1++;
    }
    final lo = pts[g0], hi = pts[g1];
    if (d > 0 && hi <= px) best = math.min(best, math.max(0, (ext - hi) / a));
    if (d < 0 && lo >= px) best = math.min(best, math.max(0, (lo - ext) / a));
    g0 = g1 + 1;
  }
  return best > 0.3 && best <= 1;
}
