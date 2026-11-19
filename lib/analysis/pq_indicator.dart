import 'all_indicator.dart';
import 'forecast.dart';
import 'star_indicator.dart';

/// مؤشر PQ: النجوم + SM + Alka في مؤشر واحد — نفس إشارات الثلاثة مجتمعة
/// (إشارات Mp كلها — وفيها Alka وAAB و0.1 — وإشارات Alka الإضافية خارج Mp).
/// الذهب بهدف 1R (2016-2020 / 2021-2026): 54.5% / 53.2% (15m)، 54.0% / 54.7% (1h)، 52.8% / 58.1% (4h).
/// الإشارات بلا نجوم وخارج SM وإضافات Alka محفوظة في [AllResult.extra] (للاختبار).
AllResult buildPq(AllResult mp, StarResult st, AllResult sm, {List<PastSignal> alka = const []}) {
  final inSm = {for (final s in sm.signals) (s.i, s.dir)};
  final pSm = {for (final p in sm.pending) (p.i, p.dir)};
  final inMp = {for (final s in mp.signals) (s.i, s.dir)};
  final all = <(PastSignal, String, bool)>[]; // (الإشارة، المصدر، ضعيفة؟)
  for (final (q, s) in mp.signals.indexed) {
    final strong = st.of(s.i, s.dir) >= 1 || inSm.contains((s.i, s.dir));
    all.add((s, mp.sources[q], !strong));
  }
  for (final s in alka) {
    if (!inMp.contains((s.i, s.dir))) all.add((s, 'Alka', true));
  }
  all.sort((a, b) => a.$1.i.compareTo(b.$1.i));
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    pend.add(p);
    pSrc.add(p.i >= 0 && (st.of(p.i, p.dir) >= 1 || pSm.contains((p.i, p.dir))) ? mp.pendingSrc[q] : 'ضعيفة');
  }
  final openDirs = {for (final x in all) if (x.$1.exitI < 0) x.$1.dir};
  final keepP = [for (var q = 0; q < pend.length; q++) if (!openDirs.contains(pend[q].dir)) q];
  return AllResult([for (final x in all) x.$1], [for (final x in all) x.$2], [for (final q in keepP) pend[q]],
      [for (final q in keepP) pSrc[q]], 'PQ', {for (final x in all) if (x.$3) x.$1.i});
}

/// دقة إشارات PQ القوية فقط (الضعيفة لا تُحسب).
(int, int) pqStrongStats(AllResult pq) {
  var w = 0, n = 0;
  for (final s in pq.signals) {
    if (pq.extra.contains(s.i) || s.result == 0) continue;
    n++;
    if (s.result > 0) w++;
  }
  return (w, n);
}
