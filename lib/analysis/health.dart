import '../models.dart';
import 'alka.dart';
import 'zero_one.dart';
import 'all_indicator.dart';
import 'forecast.dart';

/// صحة مؤشر على سوق معيّن: أداؤه على آخر 3000 شمعة بنفس الإدارة العادلة (1R ثم 2R).
class IndHealth {
  final int wins, trades;
  final double totalR;
  final int candles, days;
  /// أداء كل مصدر داخل المؤشر (لـ Mp: '0.1' و 'AAB' و 'Alka') → (ربح، صفقات)
  final Map<String, (int, int)> bySource;
  const IndHealth(this.wins, this.trades, this.totalR, this.candles, this.days, [this.bySource = const {}]);

  /// نص نجاح مصدر معيّن على هذا السوق، مثل: "AAB هنا 58% من 40 صفقة"
  String? sourceLine(String src) {
    final v = bySource[src];
    if (v == null || v.$2 == 0) return null;
    return '$src على هذا السوق: ${(100 * v.$1 / v.$2).toStringAsFixed(0)}% من ${v.$2} صفقة';
  }

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

double _r(PastSignal s) => s.result == 2 ? 1.5 : s.result == 1 ? 0.5 : -1;

/// يحسب صحة AAB و Alka و ALL و 0.1 و Mp (يعمل داخل Isolate).
(IndHealth, IndHealth, IndHealth, IndHealth, IndHealth) computeHealth(List<Candle> c, MarketSymbol sym) {
  final days = c.isEmpty ? 0 : c.last.time.difference(c.first.time).inDays;
  final f = buildForecast(c, history: c.length, rr1: 1, rr2: 2, cfg: const ForecastCfg(trail: false));
  final k = buildAlka(c, history: c.length, rr1: 1, rr2: 2, trail: false, sym: sym);
  IndHealth h(List<PastSignal> l, int w, int n) =>
      IndHealth(w, n, l.where((s) => s.result != 0).fold(0.0, (a, s) => a + _r(s)), c.length, days);
  final all = combineAll(c, f.signals, const [], k.signals, const []);
  final z = buildZeroOne(c, history: c.length, rr1: 1, rr2: 2, trail: false, sym: sym);
  final mp = combineAll(c, f.signals, const [], k.signals, const [], zero: z.signals, tag: 'Mp', maxVol: 1.8);
  return (h(f.signals, f.wins, f.closed), h(k.signals, k.wins, k.closed), h(all.signals, all.wins, all.closed),
      h(z.signals, z.wins, z.closed), _mpHealth(c, mp, days));
}

IndHealth _mpHealth(List<Candle> c, AllResult mp, int days) {
  final by = <String, (int, int)>{};
  var r = 0.0;
  for (final (q, s) in mp.signals.indexed) {
    if (s.result == 0) continue;
    r += _r(s);
    final src = mp.sources[q];
    final o = by[src] ?? (0, 0);
    by[src] = (o.$1 + (s.result > 0 ? 1 : 0), o.$2 + 1);
  }
  return IndHealth(mp.wins, mp.closed, r, c.length, days, by);
}

/// صحة Mp وحده (لفحص الفريمات).
IndHealth computeMpHealth(List<Candle> c, MarketSymbol sym) {
  final days = c.isEmpty ? 0 : c.last.time.difference(c.first.time).inDays;
  final f = buildForecast(c, history: c.length, rr1: 1, rr2: 2, cfg: const ForecastCfg(trail: false));
  final k = buildAlka(c, history: c.length, rr1: 1, rr2: 2, trail: false, sym: sym);
  final z = buildZeroOne(c, history: c.length, rr1: 1, rr2: 2, trail: false, sym: sym);
  final mp = combineAll(c, f.signals, const [], k.signals, const [], zero: z.signals, tag: 'Mp', maxVol: 1.8);
  return _mpHealth(c, mp, days);
}
