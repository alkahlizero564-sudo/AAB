import 'all_indicator.dart';
import 'forecast.dart';
import 'star_indicator.dart';

/// مؤشر PQ: النجوم + SM + Alka في مؤشر واحد بإشارات واحدة.
/// يأخذ كل إشارات Mp (وفيها Alka وAAB و0.1) التي لها نجمة أو أكثر، أو التي يوافقها شريط SM،
/// ويحذف الأضعف: بلا نجوم وخارج SM، وإضافات Alka خارج Mp (دقتها ~51-53%).
/// الذهب (15m/1h/4h) بهدف 1R: 57.3% / 57.3% على 15m، و60.6% / 56.6% على 1h، و57.9% / 60.7% على 4h
/// (2016-2020 / 2021-2026)، مقابل النجوم كلها ~55-56%، وبإدارة التطبيق ~79-86%.
AllResult buildPq(AllResult mp, StarResult st, AllResult sm) {
  final inSm = {for (final s in sm.signals) (s.i, s.dir)};
  final pSm = {for (final p in sm.pending) (p.i, p.dir)};
  bool keep(int i, int d) => st.of(i, d) >= 1 || inSm.contains((i, d));
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    if (keep(s.i, s.dir)) {
      sigs.add(s);
      src.add(mp.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    if (p.i >= 0 && (st.of(p.i, p.dir) >= 1 || pSm.contains((p.i, p.dir)))) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
    }
  }
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final keepP = [for (var q = 0; q < pend.length; q++) if (!openDirs.contains(pend[q].dir)) q];
  return AllResult(sigs, src, [for (final q in keepP) pend[q]], [for (final q in keepP) pSrc[q]], 'PQ');
}
