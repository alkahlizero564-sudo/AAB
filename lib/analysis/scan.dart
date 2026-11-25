import '../models.dart';
import 'alka.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'king_indicator.dart';
import 'sm_indicator.dart';
import 'star_indicator.dart';
import 'zero_one.dart';

/// إشارة وجدها الماسح: من أي مؤشر، اتجاهها، وكم شمعة مرّت عليها.
class ScanHit {
  final String ind; // AK / King / النجوم
  final int dir, barsAgo, i;
  final double entry, sl, tp1, tp2;
  final DateTime time;
  final bool open; // الصفقة ما زالت مفتوحة
  const ScanHit(this.ind, this.dir, this.barsAgo, this.i, this.entry, this.sl, this.tp1, this.tp2, this.time, this.open);
  String get key => '$ind|${time.millisecondsSinceEpoch}|$dir';
}

/// ترتيب المؤشرات من الأقوى (دقة اختبار لم يره بهدف 1R).
const scanAcc = {'AK': 66.0, 'King': 62.4, 'النجوم': 61.3};

/// يفحص الشموع ويرجع آخر إشارة مفتوحة لكل مؤشر قوي (AK، King قوي، النجوم بفهم التوقيت)
/// ظهرت خلال آخر [maxAge] شمعة مغلقة.
List<ScanHit> scanCandles(List<Candle> c, MarketSymbol sym,
    {List<Candle>? daily, double rr1 = 1, double rr2 = 2, double alkaTp1 = 0.35, int maxAge = 6}) {
  final n = c.length;
  if (n < 260) return const [];
  final hist = n;
  final fc = buildForecast(c, rr1: rr1, rr2: rr2, history: hist);
  final fAll = buildForecast(c, rr1: alkaTp1, rr2: rr2, history: hist);
  final ak = buildAlka(c, rr1: alkaTp1, rr2: rr2, sym: sym, history: hist);
  final z = buildZeroOne(c, rr1: alkaTp1, rr2: rr2, sym: sym, history: hist);
  final mp = combineAll(c, fAll.signals, fAll.pending, ak.signals, ak.pending, zero: z.signals, zeroPending: z.pending, tag: 'Mp');
  final st = buildStar(c, mp);
  final sm = buildSm(c, mp, stars: st);
  final king = buildKing(c, mp, top: 15, stars: st, sm: sm, daily: daily);
  final e = king.eval;
  final out = <ScanHit>[];
  void take(String name, List<PastSignal> sigs) {
    PastSignal? best;
    for (final s in sigs) {
      if (s.exitI >= 0 || s.i < n - 1 - maxAge || s.i >= n - 1) continue;
      if (best == null || s.i > best.i) best = s;
    }
    final b = best;
    if (b == null) return;
    out.add(ScanHit(name, b.dir, n - 2 - b.i, b.i, b.entry, b.sl, b.tp1, b.tp2, c[b.i].time, true));
  }

  if (e != null) {
    final akR = kingFilter(AllResult(fc.signals, List.filled(fc.signals.length, 'AAB'), fc.pending, List.filled(fc.pending.length, 'AAB'), 'AK'), e, 15);
    take('AK', akR.signals);
    take('King', king.res.signals);
    final sv = kingFilter(st.res, e, 15, wideTop: 30, wide: (i, d) => st.of(i, d) >= 2);
    take('النجوم', sv.signals);
  }
  out.sort((a, b) => (scanAcc[b.ind] ?? 0).compareTo(scanAcc[a.ind] ?? 0));
  return out;
}
