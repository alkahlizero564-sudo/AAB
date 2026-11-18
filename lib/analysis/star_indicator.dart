import 'all_indicator.dart';
import 'forecast.dart';

/// مؤشر النجوم: كل إشارات Mp في مؤشر واحد، ولكل إشارة نجوم بعدد المؤشرات الموافقة عليها
/// من SM و KM و ST و DM (حتى 3 نجوم).
/// مقاس على ذهب وبيتكوين 2021-2026 (بهدف 1R): 0 نجوم 54% ، نجمة 56% ، نجمتان 55% ، 3 نجوم 62%.
class StarResult {
  final AllResult res; // الإشارات التي نجومها ≥ الحد الأدنى
  final Map<(int, int), int> stars; // (شمعة الإشارة، الاتجاه) → عدد النجوم
  const StarResult(this.res, this.stars);
  static const empty = StarResult(AllResult([], [], [], [], 'نجوم'), {});
  int of(int i, int dir) => stars[(i, dir)] ?? 0;
}

StarResult buildStar(AllResult mp, List<AllResult?> filters, {int minStars = 0}) {
  final keys = [
    for (final f in filters)
      if (f != null) {for (final s in f.signals) (s.i, s.dir), for (final p in f.pending) (p.i, p.dir)}
  ];
  int count(int i, int d) {
    var g = 0;
    for (final k in keys) {
      if (k.contains((i, d))) g++;
    }
    return g > 3 ? 3 : g;
  }

  final stars = <(int, int), int>{};
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    final g = count(s.i, s.dir);
    stars[(s.i, s.dir)] = g;
    if (g >= minStars) {
      sigs.add(s);
      src.add(mp.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    final g = count(p.i, p.dir);
    stars[(p.i, p.dir)] = g;
    if (g >= minStars) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
    }
  }
  final open = sigs.isNotEmpty && sigs.last.exitI < 0;
  return StarResult(AllResult(sigs, src, open ? const [] : pend, open ? const [] : pSrc, 'نجوم'), stars);
}
