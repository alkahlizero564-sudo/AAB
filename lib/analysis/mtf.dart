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

/// الفريمات الأعلى التي تُبنى من شموع الفريم الحالي نفسه (بدون طلبات بيانات إضافية).
const mtfHigher = {
  '1m': ['5m', '15m'],
  '5m': ['15m', '1h'],
  '15m': ['1h'],
  '30m': ['4h'],
  '1h': ['4h'],
};

/// كم شمعة نطلب من الفريم الحالي (طلب واحد) حتى يكفي أعلى فريم مبني منها (~300 شمعة).
int mtfCount(String tf, int base) {
  final hi = mtfHigher[tf];
  if (hi == null) return base;
  final r = (mtfMinutes[hi.last]! / mtfMinutes[tf]!).round();
  return (300 * r + 50).clamp(base, 5000).toInt();
}

/// تجميع شموع الفريم الحالي إلى فريم أعلى — الشموع المكتملة فقط.
List<Candle> aggregate(List<Candle> c, String tf, {DateTime? nowBarStart}) {
  final ms = (mtfMinutes[tf] ?? 60) * 60000;
  final out = <Candle>[];
  int? key;
  for (final k in c) {
    final kk = k.time.millisecondsSinceEpoch ~/ ms;
    if (key != kk) {
      out.add(Candle(DateTime.fromMillisecondsSinceEpoch(kk * ms, isUtc: true), k.open, k.high, k.low, k.close, k.volume));
      key = kk;
    } else {
      final o = out.removeLast();
      out.add(Candle(o.time, o.open, k.high > o.high ? k.high : o.high, k.low < o.low ? k.low : o.low, k.close, o.volume + k.volume));
    }
  }
  // آخر شمعة أعلى لم تكتمل بعد (الشمعة الجارية داخلها) — تُحذف
  final cut = nowBarStart ?? c.last.time;
  while (out.isNotEmpty && out.last.time.millisecondsSinceEpoch + ms > cut.millisecondsSinceEpoch) {
    out.removeLast();
  }
  return out;
}

/// إشارات King على شموع فريم واحد (نفس طريقة التطبيق: Mp ← النجوم/SM/KM ← King).
/// كل إشارة مع نجومها (1 = أعلى 30%، 2 = أعلى 15%، 3 = أعلى 7%).
List<(PastSignal, int)> kingSignalsFor(List<Candle> c, MarketSymbol sym, String tf,
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
  final k = buildKing(c, mp, top: 30, stars: st, sm: sm, km: km, daily: daily);
  return [for (final x in k.res.signals) (x, k.stars(x.i, x.dir) < 1 ? 1 : k.stars(x.i, x.dir))];
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
List<(PastSignal, int)> mapSignals(List<(PastSignal, int)> sigs, List<Candle> from, String fromTf, List<Candle> to) {
  if (to.length < 2 || from.isEmpty) return const [];
  final dur = (mtfMinutes[fromTf] ?? 15) * 60000;
  final out = <(PastSignal, int)>[];
  for (final (s, stars) in sigs) {
    if (s.i < 0 || s.i >= from.length) continue;
    final closeMs = from[s.i].time.millisecondsSinceEpoch + dur - 1;
    final i = _barAt(to, closeMs);
    if (i < 0 || i >= to.length - 1) continue; // لا نضعها على الشمعة الجارية
    var ex = -1;
    if (s.exitI >= 0 && s.exitI < from.length) {
      ex = _barAt(to, from[s.exitI].time.millisecondsSinceEpoch + dur - 1);
      if (ex < i) ex = i;
    }
    out.add((PastSignal(i, s.dir, s.entry, s.sl, s.tp1, s.tp2, s.result, ex, s.why, s.strong, s.agree, s.total, s.exitPrice, s.curStop), stars));
  }
  return out;
}

/// دمج الفريمات: إشارة واحدة لكل (شمعة، اتجاه) بأعلى نجوم.
List<(PastSignal, int)> mergeSignals(List<List<(PastSignal, int)>> lists) {
  final best = <(int, int), (PastSignal, int)>{};
  for (final l in lists) {
    for (final x in l) {
      final k = (x.$1.i, x.$1.dir);
      final o = best[k];
      if (o == null || x.$2 > o.$2) best[k] = x;
    }
  }
  return best.values.toList()..sort((a, b) => a.$1.i.compareTo(b.$1.i));
}

/// النجوم تُحمل في sources بالشكل «K2».
AllResult mtfResult(List<(PastSignal, int)> s) =>
    AllResult([for (final x in s) x.$1], [for (final x in s) 'K${x.$2}'], const [], const [], 'MTF');
int mtfStarsOf(AllResult r, int q) => q < r.sources.length ? (int.tryParse(r.sources[q].substring(1)) ?? 1) : 1;
