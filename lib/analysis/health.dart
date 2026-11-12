import '../models.dart';
import 'alka.dart';
import 'forecast.dart';

/// صحة مؤشر على سوق معيّن: أداؤه على آخر 3000 شمعة بنفس الإدارة العادلة (1R ثم 2R).
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

double _r(PastSignal s) => s.result == 2 ? 1.5 : s.result == 1 ? 0.5 : -1;

/// يحسب صحة AAB و Alka (يعمل داخل Isolate).
(IndHealth, IndHealth) computeHealth(List<Candle> c, MarketSymbol sym) {
  final days = c.isEmpty ? 0 : c.last.time.difference(c.first.time).inDays;
  final f = buildForecast(c, history: c.length, rr1: 1, rr2: 2, cfg: const ForecastCfg(trail: false));
  final k = buildAlka(c, history: c.length, rr1: 1, rr2: 2, trail: false, sym: sym);
  IndHealth h(List<PastSignal> l, int w, int n) =>
      IndHealth(w, n, l.where((s) => s.result != 0).fold(0.0, (a, s) => a + _r(s)), c.length, days);
  return (h(f.signals, f.wins, f.closed), h(k.signals, k.wins, k.closed));
}
