import '../models.dart';
import 'alka.dart';
import 'zero_one.dart';
import 'sm_indicator.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'st_indicator.dart';
import 'star_indicator.dart';
import 'king_indicator.dart';
import 'indicators.dart';

/// صحة مؤشر على سوق معيّن: أداؤه على آخر 5000 شمعة بنفس الإدارة العادلة (1R ثم 2R).
class IndHealth {
  final int wins, trades;
  final double totalR;
  final int candles, days;
  const IndHealth(this.wins, this.trades, this.totalR, this.candles, this.days);

  double get winRate => trades == 0 ? 0 : wins / trades;
  double get avgR => trades == 0 ? 0 : totalR / trades;

  /// 'green' قوي الآن ، 'yellow' متوسط ، 'red' ضعيف الآن ، 'grey' عينة صغيرة
  String get light {
    if (trades < 20) return 'grey';
    if (trades >= 30 && (winRate < 0.48 || avgR < -0.05)) return 'red';
    if (winRate >= 0.53 && avgR > 0) return 'green';
    return 'yellow';
  }

  String get dot => switch (light) { 'green' => '🟢', 'red' => '🔴', 'yellow' => '🟡', _ => '⚪' };

  String get label => switch (light) {
        'green' => 'قوي الآن',
        'red' => 'ضعيف الآن',
        'yellow' => 'متوسط',
        _ => 'عينة صغيرة',
      };

  String get summary =>
      '${(winRate * 100).toStringAsFixed(0)}% من $trades صفقة • ${avgR >= 0 ? '+' : ''}${avgR.toStringAsFixed(2)}R لكل صفقة (آخر $days يوم)';
}

/// الدقة على المدى الطويل لكل مؤشر (رقم ثابت لا يتأثر بالحظ): من اختبار ذهب وبيتكوين 2021-2026
/// (سنوات لم يُضبط عليها أي مؤشر) — (بهدف 1R ، بإدارة التطبيق ، عدد الصفقات بهدف 1R).
/// DM خاص بالذهب فرقمه من ذهب 2021-2026 وحده.
const longTermAcc = <String, (double, double, int)>{
  'DM': (59.2, 82.0, 868),
  'Mp': (55.7, 80.8, 12662),
  '0.1': (51.2, 76.7, 2884),
};

double _r(PastSignal s) => s.result == 2 ? 1.5 : s.result == 1 ? 0.5 : -1;

/// يحسب صحة AAB و Alka و ALL و 0.1 و Mp و SM و KM و DM و ST بهذا الترتيب (يعمل داخل Isolate).
List<IndHealth> computeHealth(List<Candle> c,
    MarketSymbol sym, {List<Candle>? daily}) {
  final days = c.isEmpty ? 0 : c.last.time.difference(c.first.time).inDays;
  final f = buildForecast(c, history: c.length, rr1: 1, rr2: 2, cfg: const ForecastCfg(trail: false));
  final k = buildAlka(c, history: c.length, rr1: 1, rr2: 2, trail: false, sym: sym);
  IndHealth h(List<PastSignal> l, int w, int n) =>
      IndHealth(w, n, l.where((s) => s.result != 0).fold(0.0, (a, s) => a + _r(s)), c.length, days);
  final all = combineAll(c, f.signals, const [], k.signals, const []);
  final z = buildZeroOne(c, history: c.length, rr1: 1, rr2: 2, trail: false, sym: sym);
  final mp = combineAll(c, f.signals, const [], k.signals, const [], zero: z.signals, tag: 'Mp');
  final sm = buildSm(c, mp);
  final km = buildKm(c, sm);
  final dm = buildDm(c, sym, aab: f, alka: k, zero: z, daily: daily);
  final st = buildSt(c, mp).res;
  // King: كل خيارات العرض (15/30/50/70) × (دخول قريب فقط: لا/نعم) من تقييم واحد
  final stars = buildStar(c, mp);
  final kg = buildKing(c, mp, top: 70, stars: stars, sm: sm, km: km, daily: daily);
  final at = atr(c, 14);
  final kingH = <IndHealth>[];
  for (final top in const [15, 30, 50, 70]) {
    for (final nearOnly in const [false, true]) {
      final thr = kingThreshold(top);
      final l = [
        for (final s in mp.signals)
          if (kg.of(s.i, s.dir) >= thr && (!nearOnly || kingEntryDist(c, at, s.i, s.dir, s.entry) < 0.75)) s
      ];
      final closed = l.where((s) => s.result != 0).toList();
      kingH.add(h(l, closed.where((s) => s.result > 0).length, closed.length));
    }
  }
  // فلتر الذكاء على SM و AAB: [SM 30%، SM 15%، AAB 30%، AAB 15%]
  final ev = kg.eval;
  IndHealth hk(List<PastSignal> l, List<String> src, int top) {
    final thr = kingThreshold(top);
    final kept = [for (final (q, s) in l.indexed) if (ev != null && ev.score(s.i, s.dir, s.entry, s.sl, src[q]) >= thr) s];
    final closed = kept.where((s) => s.result != 0).toList();
    return h(kept, closed.where((s) => s.result > 0).length, closed.length);
  }
  final aabSrc = List.filled(f.signals.length, 'AAB');
  final aiH = [hk(sm.signals, sm.sources, 30), hk(sm.signals, sm.sources, 15), hk(f.signals, aabSrc, 30), hk(f.signals, aabSrc, 15),
    // فهم التوقيت: Alka، ALL، KM، ST (أعلى 30% حسب King)
    hk(k.signals, List.filled(k.signals.length, 'Alka'), 30), hk(all.signals, all.sources, 30), hk(km.signals, km.sources, 30), hk(st.signals, st.sources, 30)];
  return [h(f.signals, f.wins, f.closed), h(k.signals, k.wins, k.closed), h(all.signals, all.wins, all.closed),
      h(z.signals, z.wins, z.closed), h(mp.signals, mp.wins, mp.closed), h(sm.signals, sm.wins, sm.closed), h(km.signals, km.wins, km.closed), h(dm.signals, dm.wins, dm.closed),
      h(st.signals, st.wins, st.closed), ...kingH, ...aiH];
}
