import 'dart:math' as math;
import '../models.dart';
import 'indicators.dart';

/// UT Bot Alerts (وقف متحرك مبني على ATR).
/// يرجع (الاتجاه: 1 شراء / -1 بيع / 0 غير محدد ، عدد الشموع منذ آخر انقلاب).
(int, int) utBot(List<Candle> c, {double key = 1.0, int period = 10}) {
  final n = c.length;
  if (n < period + 5) return (0, -1);
  final at = atr(c, period);
  var stop = 0.0, pos = 0, flipAt = -1;
  for (var i = 1; i < n; i++) {
    if (at[i].isNaN) continue;
    final src = c[i].close, prev = c[i - 1].close;
    final loss = key * at[i];
    final ps = stop;
    if (src > ps && prev > ps) {
      stop = math.max(ps, src - loss);
    } else if (src < ps && prev < ps) {
      stop = math.min(ps, src + loss);
    } else if (src > ps) {
      stop = src - loss;
    } else {
      stop = src + loss;
    }
    var np = pos;
    if (prev < ps && src > ps) {
      np = 1;
    } else if (prev > ps && src < ps) {
      np = -1;
    }
    if (np != pos) {
      pos = np;
      flipAt = i;
    }
  }
  return (pos, flipAt < 0 ? -1 : n - 1 - flipAt);
}
