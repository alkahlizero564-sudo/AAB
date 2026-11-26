import '../models.dart';

/// منطقة الاتجاه بهيكل السوق (لكل شمعة):
///  +1 أخضر: آخر قمة أعلى من التي قبلها وآخر قاع أعلى من الذي قبله (قمم وقيعان صاعدة)
///  -1 أحمر: آخر قمة أدنى وآخر قاع أدنى (قمم وقيعان هابطة)
///   0 رمادي: غير ذلك (السوق متذبذب / بلا اتجاه واضح)
/// القمة/القاع تُعتمد بعد [k] شموع من تكوّنها (بلا نظر للمستقبل): لون الشموع المغلقة لا يتغير.
/// اختبار (ذهب وبيتكوين 15m/1h): وصفية لا تتنبأ (صحة بعد 20 شمعة 47-50%) — للعرض فقط، لا تُستخدم فلتراً لـ King.
List<int>? _cz;
String _ck = '';

/// نسخة مخزّنة: لا تُعاد الحسبة مع كل سعر لحظي (فقط عند شمعة جديدة أو تغيّر البيانات).
List<int> trendZoneCached(List<Candle> c, {int k = 10}) {
  if (c.isEmpty) return const [];
  final key = '${c.length}|${c.first.time.millisecondsSinceEpoch}|${c.last.time.millisecondsSinceEpoch}|${c.length > 1 ? c[c.length - 2].close : 0}|$k';
  if (key != _ck || _cz == null) {
    _cz = trendZone(c, k: k);
    _ck = key;
  }
  return _cz!;
}

List<int> trendZone(List<Candle> c, {int k = 10}) {
  final n = c.length;
  final z = List<int>.filled(n, 0);
  double? h1, h2, l1, l2; // آخر قمتين وآخر قاعين
  for (var i = 2 * k; i < n; i++) {
    final j = i - k;
    var isH = true, isL = true;
    for (var q = j - k; q <= j + k; q++) {
      if (c[q].high > c[j].high) isH = false;
      if (c[q].low < c[j].low) isL = false;
    }
    if (isH) {
      h2 = h1;
      h1 = c[j].high;
    }
    if (isL) {
      l2 = l1;
      l1 = c[j].low;
    }
    if (h1 != null && h2 != null && l1 != null && l2 != null) {
      if (h1 > h2 && l1 > l2) {
        z[i] = 1;
      } else if (h1 < h2 && l1 < l2) {
        z[i] = -1;
      }
    }
  }
  return z;
}
