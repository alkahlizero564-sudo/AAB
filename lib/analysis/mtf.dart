import '../models.dart';
import 'alka.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'king_indicator.dart';
import 'low_tf.dart';
import 'sm_indicator.dart';
import 'star_indicator.dart';
import 'zero_one.dart';

/// فريمات King المتعدد: إشارات King (أعلى 30%) من 5m و15m و1h على شارت واحد.
/// اختبار ذهب 2021-2026: 5m 57.1% (بعد السبريد) • 15m 58.4% • 1h 58.3% — معاً 57.5% و1.13 إشارة/يوم
/// (ضعف إشارات 15m وحده بنفس الجودة تقريباً).
const mtfFrames = ['5m', '15m', '1h'];
const mtfMinutes = {'1m': 1, '5m': 5, '15m': 15, '30m': 30, '1h': 60, '4h': 240, '1d': 1440};

/// إشارات King على شموع فريم واحد (نفس طريقة التطبيق: Mp ← النجوم/SM/KM ← King).
List<PastSignal> kingSignalsFor(List<Candle> c, MarketSymbol sym, String tf,
    {List<Candle>? daily, double alkaTp1 = 0.35, double rr2 = 2}) {
  final n = c.length;
  if (n < 260) return const [];
  final ms = minStopFor(tf, c.last.close);
  final fAll = wideForecast(buildForecast(c, rr1: alkaTp1, rr2: rr2, history: n), ms);
  final ak = wideAlka(buildAlka(c, rr1: alkaTp1, rr2: rr2, sym: sym, history: n), ms);
  final z = wideZero(buildZeroOne(c, rr1: alkaTp1, rr2: rr2, sym: sym, history: n), ms);
  final mp = combineAll(c, fAll.signals, fAll.pending, ak.signals, ak.pending, zero: z.signals, zeroPending: z.pending, tag: 'Mp');
  final st = buildStar(c, mp);
  final sm = buildSm(c, mp, stars: st);
  final km = buildKm(c, sm);
  return buildKing(c, mp, top: 30, stars: st, sm: sm, km: km, daily: daily).res.signals;
}

int _barAt(List<Candle> cc, int ms) {
  // آخر شمعة يبدأ وقتها قبل أو عند ms
  var lo = 0, hi = cc.length - 1, ans = -1;
  while (lo <= hi) {
    final m = (lo + hi) >> 1;
    if (cc[m].time.millisecondsSinceEpoch <= ms) {
      ans = m;
      lo = m + 1;
    } else {
      hi = m - 1;
    }
  }
  return ans;
}

/// ينقل إشارات فريم آخر إلى شموع الشارت الحالي: الإشارة تظهر على الشمعة التي أُغلقت فيها شمعة الإشارة.
List<PastSignal> mapSignals(List<PastSignal> sigs, List<Candle> from, String fromTf, List<Candle> to) {
  if (to.length < 2 || from.isEmpty) return const [];
  final dur = (mtfMinutes[fromTf] ?? 15) * 60000;
  final out = <PastSignal>[];
  for (final s in sigs) {
    if (s.i < 0 || s.i >= from.length) continue;
    final closeMs = from[s.i].time.millisecondsSinceEpoch + dur - 1;
    final i = _barAt(to, closeMs);
    if (i < 0 || i >= to.length - 1) continue; // لا نضعها على الشمعة الجارية
    var ex = -1;
    if (s.exitI >= 0 && s.exitI < from.length) {
      ex = _barAt(to, from[s.exitI].time.millisecondsSinceEpoch + dur - 1);
      if (ex < i) ex = i;
    }
    out.add(PastSignal(i, s.dir, s.entry, s.sl, s.tp1, s.tp2, s.result, ex, s.why, s.strong, s.agree, s.total, s.exitPrice, s.curStop));
  }
  return out;
}

/// دمج الفريمات: إشارة واحدة لكل (شمعة، اتجاه).
List<PastSignal> mergeSignals(List<List<PastSignal>> lists) {
  final seen = <(int, int)>{};
  final all = [for (final l in lists) ...l]..sort((a, b) => a.i.compareTo(b.i));
  return [for (final s in all) if (seen.add((s.i, s.dir))) s];
}

AllResult mtfResult(List<PastSignal> s) => AllResult(s, List.filled(s.length, 'King'), const [], const [], 'MTF');
