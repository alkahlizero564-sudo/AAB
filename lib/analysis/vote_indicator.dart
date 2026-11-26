import 'all_indicator.dart';
import 'forecast.dart';
import 'king_indicator.dart';
import 'king_model.dart';
import 'st_indicator.dart';
import 'star_indicator.dart';

/// مؤشر الإجماع: كل إشارة Mp يُعدّ لها كم مؤشراً من 7 يوافقها:
/// مصدرها (Alka أو AAB أو 0.1) • النجوم • SM • KM • ST • King (أعلى 30%) • AK (AAB في أعلى 15%).
/// تظهر الإشارة إذا وافقها مؤشران أو أكثر (60% من إشارات Mp — إشارات كثيرة).
/// اختبار (ذهب 2019+ وبيتكوين 2021+، دقة الهدف 1R):
/// 2 فأكثر 56.2% • 5 فأكثر 59.6% • 6 فأكثر 63.1% • الكل (7) 68.9% (مقابل 55.2% لكل إشارات Mp).
/// النجوم: بلا نجوم = 2-4 مؤشرات • ⭐ = 5 • ⭐⭐ = 6 • ⭐⭐⭐ = 7.
const voteMin = 2;
const voteTotal = 7;

AllResult buildVote(AllResult? mp, {StarResult? stars, AllResult? sm, AllResult? km, StResult? st, KingResult? king}) {
  final sigs = <PastSignal>[], src = <String>[];
  if (mp == null) return AllResult(sigs, src, const [], const [], 'VOTE');
  final smS = {for (final s in sm?.signals ?? const <PastSignal>[]) (s.i, s.dir), for (final p in sm?.pending ?? const <PendingSetup>[]) (p.i, p.dir)};
  final kmS = {for (final s in km?.signals ?? const <PastSignal>[]) (s.i, s.dir), for (final p in km?.pending ?? const <PendingSetup>[]) (p.i, p.dir)};
  for (final (q, s) in mp.signals.indexed) {
    final k = (s.i, s.dir);
    final p = king?.conf[k] ?? 0;
    final stc = st?.conf[s.i] ?? 0;
    final v = 1 + // مصدر الإشارة نفسه (Alka أو AAB أو 0.1)
        ((stars?.of(s.i, s.dir) ?? 0) >= 1 ? 1 : 0) +
        (smS.contains(k) ? 1 : 0) +
        (kmS.contains(k) ? 1 : 0) +
        (stc >= stThreshold ? 1 : 0) +
        (p >= kingQ70 ? 1 : 0) +
        (mp.sources[q] == 'AAB' && p >= kingQ85 ? 1 : 0);
    if (v < voteMin) continue;
    sigs.add(s);
    src.add('K${v >= 7 ? 3 : v >= 5 ? v - 4 : 0}|$v');
  }
  return AllResult(sigs, src, const [], const [], 'VOTE');
}

/// النجوم من sources بالشكل «K2|6».
int voteStarsOf(AllResult r, int q) => q < r.sources.length ? (int.tryParse(r.sources[q].substring(1).split('|').first) ?? 1) : 1;
int voteCountOf(AllResult r, int q) => q < r.sources.length ? (int.tryParse(r.sources[q].split('|').last) ?? voteMin) : voteMin;
