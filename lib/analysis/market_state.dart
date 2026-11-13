import 'dart:math' as math;
import '../models.dart';
import 'indicators.dart';

/// حالة السوق الآن كما يفهمها Mp.
/// مقاسة على 32 مجموعة بيانات (12222 صفقة Mp بالهدف 1R):
///   هادئ (تذبذب < 0.8 من المعتاد): 59.0% — أفضل الظروف
///   عادي (0.8–1.3): 56.0% • نشِط (1.3–1.8): 56.1%
///   عاصف (≥ 1.8): 51.5% بلا ربح — Mp يتجاهل إشاراته فيه
class MarketState {
  final double volRatio; // تذبذب الآن ÷ متوسط تذبذب آخر 100 شمعة
  final int trend; // +1 صاعد ، -1 هابط ، 0 عرضي
  const MarketState(this.volRatio, this.trend);

  String get volLabel => volRatio < 0.8
      ? 'هادئ'
      : volRatio < 1.3
          ? 'عادي'
          : volRatio < 1.8
              ? 'نشِط'
              : 'عاصف';

  bool get stormy => volRatio >= 1.8;
  bool get quiet => volRatio < 0.8;

  String get trendLabel => trend > 0 ? 'اتجاه صاعد' : (trend < 0 ? 'اتجاه هابط' : 'سوق عرضي');

  /// نصيحة Mp بناءً على الاختبار
  String get advice => stormy
      ? 'السوق عاصف الآن (تذبذب ${volRatio.toStringAsFixed(1)}× المعتاد) — Mp يتوقف عن الإشارات حتى يهدأ، فدقته هنا 51% فقط'
      : quiet
          ? 'السوق هادئ — أفضل ظروف لـ Mp (دقة 59% في الاختبار)'
          : 'ظروف ${volLabel == 'عادي' ? 'عادية' : 'نشطة'} — دقة Mp المعتادة (56%)';
}

/// تذبذب كل شمعة ÷ متوسطه على آخر 100 شمعة (NaN قبل توفر البيانات).
List<double> volRatios(List<Candle> c) {
  final at = atr(c, 14);
  final m = sma(at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
  return [
    for (var i = 0; i < c.length; i++) (at[i].isNaN || m[i].isNaN || m[i] <= 0) ? double.nan : at[i] / m[i]
  ];
}

MarketState? marketState(List<Candle> c) {
  final n = c.length;
  if (n < 120) return null;
  final i = n - 2; // آخر شمعة مغلقة
  final vr = volRatios(c)[i];
  final cl = c.map((e) => e.close).toList();
  final e50 = ema(cl, 50);
  final at = atr(c, 14);
  var t = 0;
  if (!e50[i].isNaN && !e50[i - 10].isNaN && !at[i].isNaN && at[i] > 0) {
    final slope = (e50[i] - e50[i - 10]) / at[i];
    t = slope > 0.5 ? 1 : (slope < -0.5 ? -1 : 0);
  }
  return MarketState(vr.isNaN ? 1 : math.max(0, vr), t);
}
