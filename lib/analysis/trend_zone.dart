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
  final int ha, hb, la, lb; // نقطتا الخط العلوي ونقطتا الخط السفلي
  final double hav, hbv, lav, lbv;
  final List<(int, double)> upTouch, dnTouch; // كل القمم/القيعان التي يلمسها الخط
  const TzChan(this.from, this.to, this.dir, this.ha, this.hav, this.hb, this.hbv, this.la, this.lav, this.lb, this.lbv,
      [this.upTouch = const [], this.dnTouch = const []]);
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
  final chans = <TzChan>[];
  var from = -1;
  // ATR14 بسيط للتسامح في اللمس
  final atr = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final tr = [c[i].high - c[i].low, (c[i].high - c[i - 1].close).abs(), (c[i].low - c[i - 1].close).abs()].reduce((x, y) => x > y ? x : y);
    atr[i] = i < 14 ? tr : atr[i - 1] + (tr - atr[i - 1]) / 14;
  }
  final ph = <(int, double)>[], pl = <(int, double)>[]; // القمم والقيعان المؤكدة
  /// أفضل خط ترند من آخر 8 نقاط: لا يقطعه إغلاق أي شمعة بين أول لمسة والآن، ويلمس أكبر عدد من النقاط.
  (int, double, int, double, List<(int, double)>)? best(List<(int, double)> pts, int now, bool upper) {
    if (pts.length < 2) return null;
    final p = pts.length > 8 ? pts.sublist(pts.length - 8) : pts;
    final tol = atr[now] * 0.25;
    (int, double, int, double, List<(int, double)>)? res;
    var bestScore = -1.0;
    for (var a = 0; a < p.length - 1; a++) {
      for (var b = a + 1; b < p.length; b++) {
        final (ia, va) = p[a];
        final (ib, vb) = p[b];
        if (ib == ia) continue;
        final sl = (vb - va) / (ib - ia);
        double at(int x) => va + sl * (x - ia);
        var ok = true;
        for (var x = ia; x <= now && ok; x++) {
          // الخط لا يقطع الشموع: لا إغلاق فوق الخط العلوي (أو تحت السفلي)
          if (upper ? c[x].close > at(x) + tol : c[x].close < at(x) - tol) ok = false;
        }
        if (!ok) continue;
        final touches = [for (final q in p) if ((q.$2 - at(q.$1)).abs() <= tol && q.$1 >= ia) q];
        // الأفضلية: عدد اللمسات، ثم الحداثة (آخر نقطة أحدث)
        final score = touches.length * 1000.0 + ib;
        if (score > bestScore) {
          bestScore = score;
          res = (ia, va, ib, vb, touches);
        }
      }
    }
    return res;
  }

  void closeChan(int to) {
    if (from < 0) return;
    final up = best(ph, from, true), dn = best(pl, from, false);
    if (up == null || dn == null) return;
    final su = (up.$4 - up.$2) / (up.$3 - up.$1), sd = (dn.$4 - dn.$2) / (dn.$3 - dn.$1);
    final d = su > 0 && sd > 0 ? 1 : (su < 0 && sd < 0 ? -1 : 0);
    chans.add(TzChan(from, to, d, up.$1, up.$2, up.$3, up.$4, dn.$1, dn.$2, dn.$3, dn.$4, up.$5, dn.$5));
  }
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
      ph.add((j, c[j].high));
    }
    if (isL) {
      l2 = l1;
      l1 = c[j].low;
      pl.add((j, c[j].low));
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

/// مستوى أفقي: سعر لمسته قمتان/قاعان أو أكثر (قمم وقيعان مختلطة).
class TzLevel {
  final double price;
  final int touches, first; // عدد اللمسات وأول شمعة لمسته
  final List<int> at; // أرقام الشموع التي لمسته
  const TzLevel(this.price, this.touches, this.first, this.at);
}

List<TzLevel>? _cl;
String _clk = '';

/// المستويات الأفقية الحالية من القمم والقيعان المؤكدة (بعد [k] شموع — بلا نظر للمستقبل).
/// تُجمع النقاط المتقاربة (فرق ≤ 0.25 ATR) في مستوى واحد، ويُبقى المستوى إذا لمسه نقطتان أو أكثر.
List<TzLevel> tzLevels(List<Candle> c, {int k = 5, int lookback = 600}) {
  final n = c.length;
  if (n < 2 * k + 20) return const [];
  final key = '$n|${c.first.time.millisecondsSinceEpoch}|${c.last.time.millisecondsSinceEpoch}|${c[n - 2].close}';
  if (key == _clk && _cl != null) return _cl!;
  var atr = 0.0;
  for (var i = n - 15; i < n; i++) {
    atr += c[i].high - c[i].low;
  }
  atr /= 15;
  final tol = atr * 0.25;
  final pts = <(double, int)>[];
  for (var j = (n - lookback).clamp(k, n); j < n - k; j++) {
    var isH = true, isL = true;
    for (var q = j - k; q <= j + k; q++) {
      if (c[q].high > c[j].high) isH = false;
      if (c[q].low < c[j].low) isL = false;
    }
    if (isH) pts.add((c[j].high, j));
    if (isL) pts.add((c[j].low, j));
  }
  pts.sort((a, b) => a.$1.compareTo(b.$1));
  final out = <TzLevel>[];
  var g = <(double, int)>[];
  void flush() {
    if (g.length >= 2) {
      final p = g.map((e) => e.$1).reduce((a, b) => a + b) / g.length;
      final at = g.map((e) => e.$2).toList()..sort();
      out.add(TzLevel(p, g.length, at.first, at));
    }
    g = [];
  }

  for (final p in pts) {
    if (g.isNotEmpty && p.$1 - g.first.$1 > tol) flush();
    g.add(p);
  }
  flush();
  // مستوى كسره السعر بإغلاق واضح ثم ابتعد عنه كثيراً يبقى (قد يصبح دعماً/مقاومة) — لا نحذف شيئاً
  _cl = out;
  _clk = key;
  return out;
}
