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
  const StarResult(this.res, this.stars, [this.hot = const {}]);
  static const empty = StarResult(AllResult([], [], [], [], 'نجوم'), {});
  int of(int i, int dir) => stars[(i, dir)] ?? 0;
  bool isHot(int i, int dir) => hot.contains((i, dir));
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
  final hot = <(int, int)>{
    for (final e in stars.entries)
      if (e.value >= 2 && squeezed(e.key.$1)) e.key
  };
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final keep = [for (var q = 0; q < pend.length; q++) if (!openDirs.contains(pend[q].dir)) q];
  return StarResult(AllResult(sigs, src, [for (final q in keep) pend[q]], [for (final q in keep) pSrc[q]], 'نجوم'), stars, hot);
}
