import 'dart:math' as math;
import '../models.dart';
import 'indicators.dart';

/// مستوى دعم أو مقاومة: قمم وقيعان مؤكدة متقاربة تُجمع في مستوى واحد.
class SrLevel {
  final double price; // متوسط الملامسات
  final double lo, hi; // حدود المنطقة
  final int touches; // عدد القمم/القيعان التي كوّنته
  final int lastI; // آخر شمعة لمسته
  final bool resistance; // فوق السعر الحالي = مقاومة، تحته = دعم
  const SrLevel(this.price, this.lo, this.hi, this.touches, this.lastI, this.resistance);
}

/// أقرب [each] مقاومات فوق السعر و[each] دعوم تحته، من القمم والقيعان المؤكدة
/// (3 شموع يميناً ويساراً) في كل الشموع المحمّلة. القمم والقيعان القريبة من بعضها
/// (أقل من نصف ATR) تُدمج في مستوى واحد، والمستوى الأقوى = ملامسات أكثر وأحدث.
List<SrLevel> srLevels(List<Candle> c, {int each = 3, int side = 3}) {
  final n = c.length;
  if (n < 40) return const [];
  final at = atr(c, 14);
  final a = at[n - 1].isNaN ? (c[n - 1].high - c[n - 1].low) : at[n - 1];
  if (!(a > 0)) return const [];
  final pts = <(double, int)>[];
  for (var j = side; j < n - side; j++) {
    var isH = true, isL = true;
    for (var q = j - side; q <= j + side; q++) {
      if (q == j) continue;
      if (c[q].high >= c[j].high) isH = false;
      if (c[q].low <= c[j].low) isL = false;
    }
    if (isH) pts.add((c[j].high, j));
    if (isL) pts.add((c[j].low, j));
  }
  pts.sort((x, y) => x.$1.compareTo(y.$1));
  // تجميع النقاط المتقاربة
  final groups = <List<(double, int)>>[];
  for (final p in pts) {
    if (groups.isNotEmpty && p.$1 - groups.last.first.$1 <= 0.5 * a) {
      groups.last.add(p);
    } else {
      groups.add([p]);
    }
  }
  final px = c[n - 1].close;
  final lv = <SrLevel>[];
  for (final g in groups) {
    final avg = g.fold(0.0, (s, p) => s + p.$1) / g.length;
    final lo = g.map((p) => p.$1).reduce(math.min), hi = g.map((p) => p.$1).reduce(math.max);
    final last = g.map((p) => p.$2).reduce(math.max);
    lv.add(SrLevel(avg, lo, hi, g.length, last, avg > px));
  }
  // الأقوى أولاً بين المستويات القريبة: نختار الأقرب للسعر مع تفضيل الملامسات الأكثر
  double score(SrLevel l) => (l.price - px).abs() / a - 0.8 * (l.touches - 1);
  final res = lv.where((l) => l.resistance).toList()..sort((x, y) => score(x).compareTo(score(y)));
  final sup = lv.where((l) => !l.resistance).toList()..sort((x, y) => score(x).compareTo(score(y)));
  return [...res.take(each), ...sup.take(each)];
}
