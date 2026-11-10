import 'dart:math' as math;
import '../models.dart';
import 'indicators.dart';

/// مؤشر واحد ضمن اللوحة: اسمه، طريقة عمله، وقيمه على كل شمعة.
///  • trig[i]  = +1/-1 لو أعطى المؤشر "إشارة دخول" عند الشمعة i (حدث).
///  • bias[i]  = +1/-1 اتجاه المؤشر عند الشمعة i (حالة) — يُستخدم كتأكيد.
/// كل القيم عند i تعتمد فقط على الشموع حتى i (بدون نظر للمستقبل).
class Ind {
  final String key, name, how;
  final List<int> trig, bias;
  const Ind(this.key, this.name, this.how, this.trig, this.bias);
}

List<int> _z(int n) => List<int>.filled(n, 0);

/// Parabolic SAR (اتجاه: +1 السعر فوق النقاط).
List<int> psarDir(List<Candle> c, {double step = 0.02, double maxAf = 0.2}) {
  final n = c.length;
  final dir = _z(n);
  if (n < 3) return dir;
  var up = c[1].close >= c[0].close;
  var sar = up ? c[0].low : c[0].high;
  var ep = up ? c[1].high : c[1].low;
  var af = step;
  for (var i = 1; i < n; i++) {
    sar = sar + af * (ep - sar);
    if (up) {
      sar = math.min(sar, math.min(c[i - 1].low, i > 1 ? c[i - 2].low : c[i - 1].low));
      if (c[i].low < sar) {
        up = false;
        sar = ep;
        ep = c[i].low;
        af = step;
      } else if (c[i].high > ep) {
        ep = c[i].high;
        af = math.min(af + step, maxAf);
      }
    } else {
      sar = math.max(sar, math.max(c[i - 1].high, i > 1 ? c[i - 2].high : c[i - 1].high));
      if (c[i].high > sar) {
        up = true;
        sar = ep;
        ep = c[i].high;
        af = step;
      } else if (c[i].low < ep) {
        ep = c[i].low;
        af = math.min(af + step, maxAf);
      }
    }
    dir[i] = up ? 1 : -1;
  }
  return dir;
}

double _mid(List<Candle> c, int end, int len) {
  var hh = -double.infinity, ll = double.infinity;
  for (var j = end - len + 1; j <= end; j++) {
    hh = math.max(hh, c[j].high);
    ll = math.min(ll, c[j].low);
  }
  return (hh + ll) / 2;
}

/// لوحة المؤشرات الاحترافية محسوبة على كل الشموع.
List<Ind> buildPanel(List<Candle> c, List<double> at) {
  final n = c.length;
  final cl = c.map((e) => e.close).toList();
  final out = <Ind>[];
  double a(int i) => at[i].isNaN ? (c[i].high - c[i].low) : at[i];

  // ── Stochastic 14/3/3
  {
    final s = stoch(c);
    final t = _z(n), b = _z(n);
    for (var i = 1; i < n; i++) {
      final k = s.k[i], d = s.d[i], kp = s.k[i - 1], dp = s.d[i - 1];
      if (k.isNaN || d.isNaN || kp.isNaN || dp.isNaN) continue;
      b[i] = k > d ? 1 : -1;
      if (kp <= dp && k > d && math.min(kp, k) < 25) t[i] = 1;
      if (kp >= dp && k < d && math.max(kp, k) > 75) t[i] = -1;
    }
    out.add(Ind('stoch', 'Stochastic',
        'تقاطع خط K فوق D من منطقة التشبع البيعي (<25) = شراء، والعكس من التشبع الشرائي (>75) = بيع',
        t, b));
  }

  // ── Bollinger Bands 20/2: ارتداد من الحد + انفجار بعد الضغط
  {
    final bb = bollinger(cl);
    final t = _z(n), b = _z(n), sq = _z(n);
    final width = List<double>.filled(n, double.nan);
    for (var i = 0; i < n; i++) {
      if (!bb.mid[i].isNaN && bb.mid[i] != 0) {
        width[i] = (bb.upper[i] - bb.lower[i]) / bb.mid[i];
      }
    }
    for (var i = 1; i < n; i++) {
      if (bb.mid[i].isNaN || bb.mid[i - 1].isNaN) continue;
      b[i] = cl[i] > bb.mid[i] ? 1 : -1;
      // ارتداد: الشمعة السابقة لمست/خرجت من الحد ثم أغلقت الحالية داخله
      if (c[i - 1].low <= bb.lower[i - 1] && cl[i] > bb.lower[i] && cl[i] > c[i].open) t[i] = 1;
      if (c[i - 1].high >= bb.upper[i - 1] && cl[i] < bb.upper[i] && cl[i] < c[i].open) t[i] = -1;
      // ضغط: أضيق عرض في 50 شمعة ثم إغلاق خارج الحد
      if (i >= 51) {
        var minW = double.infinity;
        for (var j = i - 50; j < i; j++) {
          if (!width[j].isNaN) minW = math.min(minW, width[j]);
        }
        final squeezed = !width[i - 1].isNaN && width[i - 1] <= minW * 1.15;
        if (squeezed && cl[i] > bb.upper[i]) sq[i] = 1;
        if (squeezed && cl[i] < bb.lower[i]) sq[i] = -1;
      }
    }
    out.add(Ind('bb', 'Bollinger Bands',
        'لمس الحد السفلي ثم إغلاق شمعة صاعدة داخل الحزام = ارتداد شراء، والعكس عند الحد العلوي',
        t, b));
    out.add(Ind('squeeze', 'Bollinger Squeeze',
        'بعد أضيق حزام في 50 شمعة (هدوء)، الإغلاق خارج الحزام يعلن بداية حركة قوية في اتجاهه',
        sq, b));
  }

  // ── CCI 20
  {
    final v = cci(c);
    final t = _z(n), b = _z(n);
    for (var i = 1; i < n; i++) {
      if (v[i].isNaN || v[i - 1].isNaN) continue;
      b[i] = v[i] > 0 ? 1 : -1;
      if (v[i - 1] < -100 && v[i] >= -100) t[i] = 1;
      if (v[i - 1] > 100 && v[i] <= 100) t[i] = -1;
    }
    out.add(Ind('cci', 'CCI',
        'عودة CCI فوق -100 بعد التشبع البيعي = شراء، وعودته تحت +100 بعد التشبع الشرائي = بيع',
        t, b));
  }

  // ── Williams %R 14
  {
    final v = williamsR(c);
    final t = _z(n), b = _z(n);
    for (var i = 1; i < n; i++) {
      if (v[i].isNaN || v[i - 1].isNaN) continue;
      b[i] = v[i] > -50 ? 1 : -1;
      if (v[i - 1] < -80 && v[i] >= -80) t[i] = 1;
      if (v[i - 1] > -20 && v[i] <= -20) t[i] = -1;
    }
    out.add(Ind('wr', 'Williams %R',
        'خروج المؤشر من تحت -80 = نهاية البيع، وخروجه من فوق -20 = نهاية الشراء', t, b));
  }

  // ── Stochastic RSI
  {
    final r = rsi(cl, 14);
    final raw = List<double>.filled(n, double.nan);
    for (var i = 27; i < n; i++) {
      var hh = -double.infinity, ll = double.infinity, ok = true;
      for (var j = i - 13; j <= i; j++) {
        if (r[j].isNaN) {
          ok = false;
          break;
        }
        hh = math.max(hh, r[j]);
        ll = math.min(ll, r[j]);
      }
      if (ok) raw[i] = hh == ll ? 50 : (r[i] - ll) / (hh - ll) * 100;
    }
    final k = sma(raw, 3), d = sma(k, 3);
    final t = _z(n), b = _z(n);
    for (var i = 1; i < n; i++) {
      if (k[i].isNaN || d[i].isNaN || k[i - 1].isNaN || d[i - 1].isNaN) continue;
      b[i] = k[i] > d[i] ? 1 : -1;
      if (k[i - 1] <= d[i - 1] && k[i] > d[i] && k[i - 1] < 20) t[i] = 1;
      if (k[i - 1] >= d[i - 1] && k[i] < d[i] && k[i - 1] > 80) t[i] = -1;
    }
    out.add(Ind('srsi', 'Stoch RSI',
        'Stochastic مطبّق على RSI: تقاطع صاعد تحت 20 = شراء، وتقاطع هابط فوق 80 = بيع (أسرع من RSI)',
        t, b));
  }

  // ── ADX / DI
  {
    final ad = adxCalc(c);
    final t = _z(n), b = _z(n);
    for (var i = 1; i < n; i++) {
      final p = ad.plus[i], m = ad.minus[i], pp = ad.plus[i - 1], mp = ad.minus[i - 1];
      if (p.isNaN || m.isNaN || pp.isNaN || mp.isNaN) continue;
      final strong = !ad.adx[i].isNaN && ad.adx[i] >= 20;
      b[i] = p > m ? 1 : -1;
      if (pp <= mp && p > m && strong) t[i] = 1;
      if (pp >= mp && p < m && strong) t[i] = -1;
    }
    out.add(Ind('adx', 'ADX / DMI',
        '+DI فوق -DI = المشترون أقوى. التقاطع مع ADX فوق 20 (اتجاه حقيقي) = إشارة دخول', t, b));
  }

  // ── Parabolic SAR
  {
    final dir = psarDir(c);
    final t = _z(n);
    for (var i = 1; i < n; i++) {
      if (dir[i] != 0 && dir[i - 1] != 0 && dir[i] != dir[i - 1]) t[i] = dir[i];
    }
    out.add(Ind('psar', 'Parabolic SAR',
        'انتقال النقاط من فوق السعر لتحته = بداية صعود، والعكس = بداية هبوط', t, dir));
  }

  // ── Ichimoku: موقع السعر من السحابة + تقاطع Tenkan/Kijun
  {
    final t = _z(n), b = _z(n);
    var prevTk = 0;
    for (var i = 78; i < n; i++) {
      final tenkan = _mid(c, i, 9), kijun = _mid(c, i, 26);
      final k = i - 26;
      final spanA = (_mid(c, k, 9) + _mid(c, k, 26)) / 2;
      final spanB = _mid(c, k, 52);
      final top = math.max(spanA, spanB), bot = math.min(spanA, spanB);
      final cloud = cl[i] > top ? 1 : (cl[i] < bot ? -1 : 0);
      b[i] = cloud;
      final tk = tenkan > kijun ? 1 : (tenkan < kijun ? -1 : prevTk);
      if (prevTk != 0 && tk != prevTk && cloud == tk) t[i] = tk;
      prevTk = tk;
    }
    out.add(Ind('ichi', 'Ichimoku',
        'السعر فوق السحابة = اتجاه صاعد. تقاطع Tenkan فوق Kijun والسعر فوق السحابة = شراء قوي',
        t, b));
  }

  // ── Heikin Ashi: شموع مُنعّمة تُظهر الاتجاه الحقيقي
  {
    final t = _z(n), b = _z(n);
    var hao = (c[0].open + c[0].close) / 2, hac = (c[0].open + c[0].high + c[0].low + c[0].close) / 4;
    for (var i = 1; i < n; i++) {
      final o = (hao + hac) / 2;
      final cc = (c[i].open + c[i].high + c[i].low + c[i].close) / 4;
      final lo = math.min(c[i].low, math.min(o, cc));
      final hi = math.max(c[i].high, math.max(o, cc));
      final d = cc > o ? 1 : -1;
      // شمعة HA قوية: بدون ذيل في عكس الاتجاه
      final strong = d > 0 ? (math.min(o, cc) - lo) < 1e-12 + 0.05 * (hi - lo)
          : (hi - math.max(o, cc)) < 1e-12 + 0.05 * (hi - lo);
      if (i > 1 && b[i - 1] != d && strong) t[i] = d;
      b[i] = d;
      hao = o;
      hac = cc;
    }
    out.add(Ind('ha', 'Heikin Ashi',
        'تغيّر لون شمعة Heikin Ashi مع شمعة قوية بلا ذيل عكسي = بداية اتجاه جديد', t, b));
  }

  // ── Donchian 20: اختراق أعلى/أدنى 20 شمعة (نظام السلاحف)
  {
    final t = _z(n), b = _z(n);
    for (var i = 21; i < n; i++) {
      var hh = -double.infinity, ll = double.infinity;
      for (var j = i - 20; j < i; j++) {
        hh = math.max(hh, c[j].high);
        ll = math.min(ll, c[j].low);
      }
      b[i] = cl[i] > (hh + ll) / 2 ? 1 : -1;
      if (cl[i] > hh) t[i] = 1;
      if (cl[i] < ll) t[i] = -1;
    }
    out.add(Ind('donch', 'Donchian 20',
        'إغلاق فوق أعلى قمة لآخر 20 شمعة = اختراق صاعد (طريقة السلاحف)، والعكس = كسر هابط', t, b));
  }

  // ── سحب السيولة (Liquidity Sweep / Turtle Soup)
  {
    final t = _z(n), b = _z(n);
    for (var i = 21; i < n; i++) {
      var hh = -double.infinity, ll = double.infinity;
      for (var j = i - 20; j < i; j++) {
        hh = math.max(hh, c[j].high);
        ll = math.min(ll, c[j].low);
      }
      if (c[i].low < ll && cl[i] > ll && cl[i] > c[i].open) t[i] = 1;
      if (c[i].high > hh && cl[i] < hh && cl[i] < c[i].open) t[i] = -1;
    }
    out.add(Ind('sweep', 'Liquidity Sweep',
        'السعر يكسر القاع ليضرب وقوف المتداولين ثم يغلق فوقه = فخ بيع وانعكاس صاعد (والعكس)', t, b));
  }

  // ── هيكل السوق: كسر آخر قمة/قاع محوري (BOS)
  {
    final t = _z(n), b = _z(n);
    double? lastPH, lastPL;
    var trend = 0;
    for (var i = 5; i < n; i++) {
      final p = i - 2; // محور يتأكد بعد شمعتين
      var ph = true, pl = true;
      for (var j = p - 3; j <= p + 2; j++) {
        if (j == p || j < 0) continue;
        if (c[j].high >= c[p].high) ph = false;
        if (c[j].low <= c[p].low) pl = false;
      }
      if (ph) lastPH = c[p].high;
      if (pl) lastPL = c[p].low;
      if (lastPH != null && cl[i] > lastPH && cl[i - 1] <= lastPH) {
        t[i] = 1;
        trend = 1;
      } else if (lastPL != null && cl[i] < lastPL && cl[i - 1] >= lastPL) {
        t[i] = -1;
        trend = -1;
      }
      b[i] = trend;
    }
    out.add(Ind('bos', 'هيكل السوق (BOS)',
        'إغلاق فوق آخر قمة = كسر هيكل صاعد (قمم وقيعان أعلى)، وإغلاق تحت آخر قاع = كسر هيكل هابط',
        t, b));
  }

  // ── الحجم: OBV + MFI + شمعة بحجم مرتفع
  final hasVol = c.where((e) => e.volume > 0).length > n * 0.8;
  if (hasVol) {
    final obv = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      obv[i] = obv[i - 1] +
          (cl[i] > cl[i - 1] ? c[i].volume : (cl[i] < cl[i - 1] ? -c[i].volume : 0));
    }
    final obvE = ema(obv, 20);
    final t = _z(n), b = _z(n);
    for (var i = 21; i < n; i++) {
      if (obvE[i].isNaN) continue;
      b[i] = obv[i] > obvE[i] ? 1 : -1;
      var avg = 0.0;
      for (var j = i - 20; j < i; j++) {
        avg += c[j].volume;
      }
      avg /= 20;
      // شمعة بحجم ضعف المتوسط وجسم كبير = دخول أموال كبيرة
      final body = (c[i].close - c[i].open).abs();
      if (avg > 0 && c[i].volume >= 2 * avg && body >= 0.6 * a(i)) {
        t[i] = c[i].close > c[i].open ? 1 : -1;
      }
    }
    out.add(Ind('vol', 'OBV / الحجم',
        'OBV فوق متوسطه = تجميع شرائي. شمعة كبيرة بحجم ضعف المتوسط = دخول سيولة كبيرة في اتجاهها',
        t, b));

    final mfi = List<double>.filled(n, double.nan);
    final tp = c.map((e) => (e.high + e.low + e.close) / 3).toList();
    for (var i = 15; i < n; i++) {
      var pos = 0.0, neg = 0.0;
      for (var j = i - 13; j <= i; j++) {
        final f = tp[j] * c[j].volume;
        if (tp[j] > tp[j - 1]) pos += f;
        if (tp[j] < tp[j - 1]) neg += f;
      }
      mfi[i] = neg == 0 ? 100 : 100 - 100 / (1 + pos / neg);
    }
    final mt = _z(n), mb = _z(n);
    for (var i = 16; i < n; i++) {
      mb[i] = mfi[i] > 50 ? 1 : -1;
      if (mfi[i - 1] < 20 && mfi[i] >= 20) mt[i] = 1;
      if (mfi[i - 1] > 80 && mfi[i] <= 80) mt[i] = -1;
    }
    out.add(Ind('mfi', 'MFI',
        'RSI مرجّح بالحجم: خروجه من تحت 20 = شراء، ومن فوق 80 = بيع', mt, mb));
  }
  return out;
}
