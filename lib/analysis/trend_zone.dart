import '../models.dart';

/// منطقة الاتجاه بهيكل السوق (لكل شمعة):
///  +1 أخضر: آخر قمة أعلى من التي قبلها وآخر قاع أعلى من الذي قبله (قمم وقيعان صاعدة)
///  -1 أحمر: آخر قمة أدنى وآخر قاع أدنى (قمم وقيعان هابطة)
///   0 رمادي: غير ذلك (السوق متذبذب / بلا اتجاه واضح)
/// القمة/القاع تُعتمد بعد [k] شموع من تكوّنها (بلا نظر للمستقبل): لون الشموع المغلقة لا يتغير.
/// اختبار (ذهب وبيتكوين 15m/1h): وصفية لا تتنبأ (صحة بعد 20 شمعة 47-50%) — للعرض فقط، لا تُستخدم فلتراً لـ King.
/// صندوق الهيكل لكل شمعة: الحد العلوي = آخر قمة مؤكدة، السفلي = آخر قاع مؤكد، واللون من [trendZone].
class TzData {
  final List<int> zone;
  final List<double> top, bot;
  final List<TzChan> chans; // قنوات الترند (كل قناة من آخر قمتين وآخر قاعين)
  const TzData(this.zone, this.top, this.bot, [this.chans = const []]);
}

/// قناة ترند: خط علوي يمر بآخر قمتين وخط سفلي يمر بآخر قاعين.
/// تبدأ [from] (الشمعة التي تأكدت فيها آخر قمة/قاع) وتنتهي [to] (قبل تأكد قمة/قاع جديد).
class TzChan {
  final int from, to, dir; // dir: +1 صاعدة (الخطان صاعدان) ، -1 هابطة ، 0 غير متفقة
  final int ha, hb, la, lb; // أرقام شموع القمتين والقاعين
  final double hav, hbv, lav, lbv;
  const TzChan(this.from, this.to, this.dir, this.ha, this.hav, this.hb, this.hbv, this.la, this.lav, this.lb, this.lbv);
  double upAt(double i) => hav + (hbv - hav) * (i - ha) / (hb - ha);
  double dnAt(double i) => lav + (lbv - lav) * (i - la) / (lb - la);
  int get start => [ha, la].reduce((a, b) => a < b ? a : b);
}

TzData? _cz;
String _ck = '';

/// نسخة مخزّنة: لا تُعاد الحسبة مع كل سعر لحظي (فقط عند شمعة جديدة أو تغيّر البيانات).
TzData trendZoneCached(List<Candle> c, {int k = 10}) {
  if (c.isEmpty) return const TzData([], [], [], []);
  final key = '${c.length}|${c.first.time.millisecondsSinceEpoch}|${c.last.time.millisecondsSinceEpoch}|${c.length > 1 ? c[c.length - 2].close : 0}|$k';
  if (key != _ck || _cz == null) {
    _cz = trendZone(c, k: k);
    _ck = key;
  }
  return _cz!;
}

TzData trendZone(List<Candle> c, {int k = 10}) {
  final n = c.length;
  final z = List<int>.filled(n, 0);
  final top = List<double>.filled(n, double.nan), bot = List<double>.filled(n, double.nan);
  double? h1, h2, l1, l2; // آخر قمتين وآخر قاعين
  int ih1 = -1, ih2 = -1, il1 = -1, il2 = -1;
  final chans = <TzChan>[];
  var from = -1;
  void closeChan(int to) {
    if (from >= 0 && ih2 >= 0 && il2 >= 0 && ih1 != ih2 && il1 != il2) {
      final su = (h1! - h2!) / (ih1 - ih2), sd = (l1! - l2!) / (il1 - il2);
      final d = su > 0 && sd > 0 ? 1 : (su < 0 && sd < 0 ? -1 : 0);
      chans.add(TzChan(from, to, d, ih2, h2, ih1, h1, il2, l2, il1, l1));
    }
  }
  for (var i = 2 * k; i < n; i++) {
    final j = i - k;
    var isH = true, isL = true;
    for (var q = j - k; q <= j + k; q++) {
      if (c[q].high > c[j].high) isH = false;
      if (c[q].low < c[j].low) isL = false;
    }
    if (isH || isL) closeChan(i - 1);
    if (isH) {
      h2 = h1;
      h1 = c[j].high;
      ih2 = ih1;
      ih1 = j;
    }
    if (isL) {
      l2 = l1;
      l1 = c[j].low;
      il2 = il1;
      il1 = j;
    }
    if (isH || isL) from = i;
    if (h1 != null) top[i] = h1;
    if (l1 != null) bot[i] = l1;
    if (h1 != null && h2 != null && l1 != null && l2 != null) {
      if (h1 > h2 && l1 > l2) {
        z[i] = 1;
      } else if (h1 < h2 && l1 < l2) {
        z[i] = -1;
      }
    }
  }
  closeChan(n - 1);
  return TzData(z, top, bot, chans);
}
