import '../models.dart';

/// تحليل الحجم الحقيقي (متوفر للعملات الرقمية من Binance فقط).
/// النسب من -1 (بيع كامل) إلى +1 (شراء كامل).
class Flow {
  final double lastDelta; // الشمعة الأخيرة
  final double delta10; // آخر 10 شموع
  final double delta30; // آخر 30 شمعة
  final double volRatio; // حجم آخر شمعة ÷ متوسط آخر 20
  const Flow(this.lastDelta, this.delta10, this.delta30, this.volRatio);
}

Flow? flowOf(List<Candle> c) {
  final n = c.length;
  if (n < 30 || !c.last.hasFlow) return null;

  double ratio(int k) {
    var buy = 0.0, tot = 0.0;
    for (var i = n - k; i < n; i++) {
      if (!c[i].hasFlow) continue;
      buy += c[i].buyVol;
      tot += c[i].volume;
    }
    return tot <= 0 ? 0 : (2 * buy - tot) / tot;
  }

  var avg = 0.0;
  for (var i = n - 21; i < n - 1; i++) {
    avg += c[i].volume;
  }
  avg /= 20;
  final last = c.last;
  final lastDelta = last.volume <= 0 ? 0.0 : (2 * last.buyVol - last.volume) / last.volume;
  return Flow(lastDelta, ratio(10), ratio(30), avg <= 0 ? 0.0 : last.volume / avg);
}
