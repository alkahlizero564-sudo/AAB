import 'dart:math' as math;
import '../models.dart';
import 'q_model.dart';

/// مؤشر Q 🗺️ — خريطة الاحتمالات.
/// يقرأ حالة السوق (التذبذب، الضغط، الزخم، البعد عن المتوسطات، الساعة) ويتوقع خلال الـ 12 شمعة القادمة:
///  - المدى المتوقع للحركة (هادئ / عادي / متحرك)
///  - منطقة 70% ومنطقة 90% لمكان السعر
///  - احتمال الوصول لأي سعر، واحتمال +1 ATR قبل −1 ATR
/// اختبار لم يره (ذهب 2019-2025، بيتكوين 2021-2026): منطقة 70% صدقت 65-72% في السوق الهادئ والمتذبذب،
/// بينما المنطقة الثابتة 84% (واسعة) في الهادئ و53% فقط في المتذبذب. احتمال لمس المستويات مُعايَر (فرق 1-5%).
class QResult {
  final int i; // الشمعة المغلقة التي بُني عليها التوقع
  final double price, atr, scale; // scale = المدى المتوقع (صعود + هبوط) بوحدات ATR
  final double pUp; // احتمال +1 ATR قبل −1 ATR
  const QResult(this.i, this.price, this.atr, this.scale, this.pUp);

  /// 0 هادئ، 1 عادي، 2 متحرك
  int get regime => scale < qScaleT[0] ? 0 : (scale < qScaleT[1] ? 1 : 2);
  String get regimeAr => const ['هادئ', 'عادي', 'متحرك'][regime];

  /// حدود السعر بعد [k] شمعة (1..12) لكوانتيل [q] من qZ (0: 5%، 1: 15%، 2: 50%، 3: 85%، 4: 95%).
  double band(int q, int k) => price + qZ[q] * scale * atr * math.sqrt(k / qH);

  /// احتمال أن يلمس السعر [level] خلال 12 شمعة.
  double touchProb(double level) {
    final up = level >= price;
    final dist = (level - price).abs() / atr / scale;
    final cdf = up ? qCdfU : qCdfD;
    if (dist <= cdf.first) return 1;
    if (dist >= cdf.last) return 0;
    var lo = 0, hi = cdf.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) >> 1;
      if (cdf[m] <= dist) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final f = (dist - cdf[lo]) / math.max(1e-12, cdf[hi] - cdf[lo]);
    final p = (lo + f) / (cdf.length - 1);
    return 1 - p;
  }
}

double _tree(List<int> st, List<int> f, List<double> t, List<int> l, List<int> r, List<double> v, List<double> x) {
  var s = 0.0;
  for (final o in st) {
    var n = o;
    while (f[n] != -1) {
      n = x[f[n]] <= t[n] ? l[n] : r[n];
    }
    s += v[n];
  }
  return s;
}

/// يحسب معلومات Q بنفس طريقة ملف التدريب تماماً (pandas: ewm adjust=False، std بعينة).
List<double>? qFeaturesAt(List<Candle> c, int i, String tf) {
  final n = c.length;
  if (i < 120 || i >= n) return null;
  final tr = List<double>.filled(n, 0);
  for (var k = 0; k < n; k++) {
    final x = c[k];
    tr[k] = k == 0
        ? x.high - x.low
        : math.max(x.high - x.low, math.max((x.high - c[k - 1].close).abs(), (x.low - c[k - 1].close).abs()));
  }
  List<double> ewm(List<double> v, double al) {
    final o = List<double>.filled(v.length, 0);
    o[0] = v[0];
    for (var k = 1; k < v.length; k++) {
      o[k] = o[k - 1] + al * (v[k] - o[k - 1]);
    }
    return o;
  }

  final a = ewm(tr, 1 / 14), a5 = ewm(tr, 1 / 5), a50 = ewm(tr, 1 / 50);
  var am = 0.0;
  for (var k = i - 99; k <= i; k++) {
    am += a[k];
  }
  am /= 100;
  final cl = [for (final x in c) x.close];
  final e20 = ewm(cl, 2 / 21), e50 = ewm(cl, 2 / 51);
  // RSI: بداية من الشمعة الثانية (الفرق الأول غير معرّف)
  var up = 0.0, dn = 0.0;
  for (var k = 1; k <= i; k++) {
    final d = cl[k] - cl[k - 1];
    final u = d > 0 ? d : 0.0, w = d < 0 ? -d : 0.0;
    if (k == 1) {
      up = u;
      dn = w;
    } else {
      up += (u - up) / 14;
      dn += (w - dn) / 14;
    }
  }
  final rsi = dn == 0 ? 100.0 : 100 - 100 / (1 + up / dn);
  var m = 0.0;
  for (var k = i - 19; k <= i; k++) {
    m += cl[k];
  }
  m /= 20;
  var ss = 0.0;
  for (var k = i - 19; k <= i; k++) {
    ss += (cl[k] - m) * (cl[k] - m);
  }
  final sd = math.sqrt(ss / 19);
  final ai = a[i];
  if (!(ai > 0) || !(am > 0)) return null;
  var h3 = -1e18, l3 = 1e18;
  for (var k = i - 2; k <= i; k++) {
    h3 = math.max(h3, c[k].high);
    l3 = math.min(l3, c[k].low);
  }
  final t = c[i].time.toUtc();
  final hr = t.hour.toDouble();
  final tfv = switch (tf) { '1h' => 1.0, '4h' || '1d' => 2.0, _ => 0.0 };
  return [
    math.log(ai / am),
    math.log(a5[i] / a50[i]),
    math.log(4 * sd / ai),
    math.log((c[i].high - c[i].low) / ai + 1e-3),
    math.log((h3 - l3) / ai + 1e-3),
    (cl[i] - cl[i - 5]) / ai,
    (cl[i] - cl[i - 20]) / ai,
    (cl[i] - e20[i]) / ai,
    (cl[i] - e50[i]) / ai,
    (rsi - 50) / 50,
    math.sin(2 * math.pi * hr / 24),
    math.cos(2 * math.pi * hr / 24),
    (t.weekday - 1).toDouble(),
    tfv,
  ];
}

/// Q على آخر شمعة مغلقة.
QResult? buildQ(List<Candle> c, String tf) {
  final i = c.length - 2;
  final x = qFeaturesAt(c, i, tf);
  if (x == null) return null;
  final sc = math.exp(_tree(qsStart, qsFeat, qsThr, qsLeft, qsRight, qsVal, x));
  final raw = _tree(qdStart, qdFeat, qdThr, qdLeft, qdRight, qdVal, x);
  final pUp = 1 / (1 + math.exp(-raw));
  // ATR (ewm 1/14) عند الشمعة
  var a = c[0].high - c[0].low;
  for (var k = 1; k <= i; k++) {
    final y = c[k];
    final tr = math.max(y.high - y.low, math.max((y.high - c[k - 1].close).abs(), (y.low - c[k - 1].close).abs()));
    a += (tr - a) / 14;
  }
  return QResult(i, c[i].close, a, sc, pUp);
}
