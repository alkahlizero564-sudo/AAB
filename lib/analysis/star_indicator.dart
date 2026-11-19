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
  final Set<(int, int)> rev; // إشارات عكسية (ظهرت وصفقة عكسها مفتوحة)
  final Set<(int, int)> hot; // ضغط 🔥: نجمتان أو 3 في سوق مضغوط (ATR5/ATR50 < 0.6)
  const StarResult(this.res, this.stars, [this.rev = const {}, this.hot = const {}]);
  static const empty = StarResult(AllResult([], [], [], [], 'نجوم'), {});
  int of(int i, int dir) => stars[(i, dir)] ?? 0;
  bool isRev(int i, int dir) => rev.contains((i, dir));
  bool isHot(int i, int dir) => hot.contains((i, dir));
}

/// الإشارات العكسية: إشارات محرّكَي الشراء والبيع المستقلين [two] التي ظهرت وصفقة Mp عكسها ما زالت مفتوحة.
/// مختبرة (ذهب وبيتكوين 15m/1h/4h): دقتها بهدف 1R 56.0% (2016-2020) و55.9% (2021-2026) مثل باقي الإشارات،
/// لكن نجوم الثقة لا تميّزها (2-3★ منها ~55-57%) فتُعطى نجمة واحدة كحد أقصى.
AllResult reverseSignals(AllResult mp, AllResult two) {
  final have = {for (final s in mp.signals) (s.i, s.dir)};
  bool oppOpenAt(int i, int d) => mp.signals.any((b) => b.dir == -d && b.i < i && (b.exitI < 0 || b.exitI > i));
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in two.signals.indexed) {
    if (have.contains((s.i, s.dir)) || !oppOpenAt(s.i, s.dir)) continue;
    sigs.add(s);
    src.add(two.sources[q]);
  }
  final pDirs = {for (final p in mp.pending) p.dir};
  final openDirs = {for (final b in mp.signals) if (b.exitI < 0) b.dir};
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in two.pending.indexed) {
    if (pDirs.contains(p.dir) || !openDirs.contains(-p.dir)) continue;
    pend.add(p);
    pSrc.add(two.pendingSrc[q]);
  }
  return AllResult(sigs, src, pend, pSrc, 'Mp↺');
}


/// حد أعلى 10% من درجات ثقة ST (من بيانات التدريب نفسها)
const stTop10 = 0.5823269046477569;

StarResult buildStar(List<Candle> c, AllResult mp, {int minStars = 0, AllResult? rev}) {
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
  final revKeys = <(int, int)>{};
  if (rev != null) {
    for (final (q, s) in rev.signals.indexed) {
      final g = starsOf(s.i, s.dir, rev.sources[q]).clamp(0, 1);
      stars[(s.i, s.dir)] = g;
      revKeys.add((s.i, s.dir));
      if (g >= minStars) {
        sigs.add(s);
        src.add(rev.sources[q]);
      }
    }
    for (final (q, p) in rev.pending.indexed) {
      final g = p.i < 0 ? 0 : starsOf(p.i, p.dir, rev.pendingSrc[q]).clamp(0, 1);
      stars[(p.i, p.dir)] = g;
      revKeys.add((p.i, p.dir));
      if (g >= minStars) {
        pend.add(p);
        pSrc.add(rev.pendingSrc[q]);
      }
    }
    final order = [for (var q = 0; q < sigs.length; q++) q]..sort((a, b) => sigs[a].i.compareTo(sigs[b].i));
    final s2 = [for (final q in order) sigs[q]], r2 = [for (final q in order) src[q]];
    sigs..clear()..addAll(s2);
    src..clear()..addAll(r2);
  }
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final keep = [for (var q = 0; q < pend.length; q++) if (!openDirs.contains(pend[q].dir)) q];
  return StarResult(AllResult(sigs, src, [for (final q in keep) pend[q]], [for (final q in keep) pSrc[q]], 'نجوم'), stars, revKeys, hot);
}
