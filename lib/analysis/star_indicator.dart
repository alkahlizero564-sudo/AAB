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
  const StarResult(this.res, this.stars);
  static const empty = StarResult(AllResult([], [], [], [], 'نجوم'), {});
  int of(int i, int dir) => stars[(i, dir)] ?? 0;
}


/// حد أعلى 10% من درجات ثقة ST (من بيانات التدريب نفسها)
const stTop10 = 0.5823269046477569;

StarResult buildStar(List<Candle> c, AllResult mp, {int minStars = 0}) {
  if (c.length < 120) return StarResult.empty;
  final sc = StScorer(c);
  final at = atr(c, 14);
  final am = sma(at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
  bool calm(int i) => i >= 0 && i < c.length && !at[i].isNaN && !am[i].isNaN && am[i] > 0 && at[i] / am[i] < 0.9;
  int starsOf(int i, int d, String src) {
    final p = sc.score(i, d, src);
    final g = (p >= stTop10 ? 2 : p >= stThreshold ? 1 : 0) + (calm(i) ? 1 : 0);
    return g > 3 ? 3 : g;
  }

  final stars = <(int, int), int>{};
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    final g = starsOf(s.i, s.dir, mp.sources[q]);
    stars[(s.i, s.dir)] = g;
    if (g >= minStars) {
      sigs.add(s);
      src.add(mp.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    final g = p.i < 0 ? 0 : starsOf(p.i, p.dir, mp.pendingSrc[q]);
    stars[(p.i, p.dir)] = g;
    if (g >= minStars) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
    }
  }
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  return StarResult(AllResult(sigs, src, [for (final p in pend) if (!openDirs.contains(p.dir)) p], [for (final (q, p) in pend.indexed) if (!openDirs.contains(p.dir)) pSrc[q]], 'نجوم'), stars);
}
