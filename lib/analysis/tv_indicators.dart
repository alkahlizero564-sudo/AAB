import 'dart:math' as math;
import '../models.dart';
import 'indicator_panel.dart';
import 'indicators.dart';

/// مؤشرات TradingView الشهيرة (بإعداداتها الافتراضية) كإشارات دخول + اتجاه
/// لكل شمعة، بدون نظر للمستقبل. تُستخدم في المقارنة وكأسباب دخول اختيارية في محركنا.
List<int> _z(int n) => List<int>.filled(n, 0);

List<double> _wma(List<double> v, int p) {
  final out = List<double>.filled(v.length, double.nan);
  final den = p * (p + 1) / 2;
  for (var i = p - 1; i < v.length; i++) {
    var s = 0.0, ok = true;
    for (var j = 0; j < p; j++) {
      final x = v[i - j];
      if (x.isNaN) {
        ok = false;
        break;
      }
      s += x * (p - j);
    }
    if (ok) out[i] = s / den;
  }
  return out;
}

List<Ind> tvIndicators(List<Candle> c) {
  final n = c.length;
  final cl = c.map((e) => e.close).toList();
  final at = atr(c, 14);
  final out = <Ind>[];

  // ── Volume Profile (نافذة متحركة 150 شمعة، 24 مستوى، منطقة القيمة 70%)
  //    شراء: لمس VAL ثم إغلاق فوقها • بيع: لمس VAH ثم إغلاق تحتها • الاتجاه: فوق/تحت POC
  {
    final t = _z(n), b = _z(n);
    const look = 150, bins = 24;
    final hasVol = c.where((e) => e.volume > 0).length > n * 0.8;
    for (var i = look; i < n; i += 1) {
      var lo = double.infinity, hi = -double.infinity;
      for (var j = i - look; j < i; j++) {
        lo = math.min(lo, c[j].low);
        hi = math.max(hi, c[j].high);
      }
      if (!(hi > lo)) continue;
      final w = (hi - lo) / bins;
      final vol = List<double>.filled(bins, 0);
      for (var j = i - look; j < i; j++) {
        final k = c[j];
        final v = hasVol ? k.volume : 1.0;
        final b0 = ((k.low - lo) / w).floor().clamp(0, bins - 1);
        final b1 = ((k.high - lo) / w).floor().clamp(0, bins - 1);
        final share = v / (b1 - b0 + 1);
        for (var q = b0; q <= b1; q++) {
          vol[q] += share;
        }
      }
      var poc = 0;
      for (var q = 1; q < bins; q++) {
        if (vol[q] > vol[poc]) poc = q;
      }
      final total = vol.fold(0.0, (a, x) => a + x);
      var lo2 = poc, hi2 = poc;
      var acc = vol[poc];
      while (acc < total * 0.7 && (lo2 > 0 || hi2 < bins - 1)) {
        final down = lo2 > 0 ? vol[lo2 - 1] : -1.0;
        final up = hi2 < bins - 1 ? vol[hi2 + 1] : -1.0;
        if (up >= down) {
          hi2++;
          acc += vol[hi2];
        } else {
          lo2--;
          acc += vol[lo2];
        }
      }
      final val = lo + lo2 * w, vah = lo + (hi2 + 1) * w, pocP = lo + (poc + 0.5) * w;
      b[i] = cl[i] > pocP ? 1 : -1;
      final k = c[i];
      if (k.low <= val && k.close > val && k.close > k.open) t[i] = 1;
      if (k.high >= vah && k.close < vah && k.close < k.open) t[i] = -1;
    }
    out.add(Ind('vp', 'Volume Profile',
        'منطقة القيمة (70% من التداول): رفض السعر من حدها السفلي VAL = شراء، ومن حدها العلوي VAH = بيع. POC = أكثر سعر تداولاً.',
        t, b));
  }

  // ── VWAP (يومي): عودة فوقه/تحته
  {
    final t = _z(n), b = _z(n);
    var pv = 0.0, vv = 0.0;
    var day = -1;
    for (var i = 0; i < n; i++) {
      final d = c[i].time.toUtc().day;
      if (d != day) {
        day = d;
        pv = 0;
        vv = 0;
      }
      final v = c[i].volume > 0 ? c[i].volume : 1.0;
      final tp = (c[i].high + c[i].low + c[i].close) / 3;
      pv += tp * v;
      vv += v;
      final vw = pv / vv;
      b[i] = cl[i] > vw ? 1 : -1;
      if (i > 0 && b[i - 1] != 0 && b[i] != b[i - 1]) t[i] = b[i];
    }
    out.add(Ind('vwap', 'VWAP', 'السعر يغلق فوق متوسط السعر المرجّح بالحجم اليومي = شراء، وتحته = بيع.', t, b));
  }

  // ── Squeeze Momentum (LazyBear 20/2/1.5): انطلاق بعد الضغط في اتجاه الزخم
  {
    final t = _z(n), b = _z(n);
    final bb = bollinger(cl, 20, 2);
    final e20 = ema(cl, 20);
    final at20 = atr(c, 20);
    final mom = List<double>.filled(n, double.nan);
    for (var i = 20; i < n; i++) {
      var hh = -double.infinity, ll = double.infinity;
      for (var j = i - 19; j <= i; j++) {
        hh = math.max(hh, c[j].high);
        ll = math.min(ll, c[j].low);
      }
      final mid = ((hh + ll) / 2 + (e20[i].isNaN ? cl[i] : e20[i])) / 2;
      mom[i] = cl[i] - mid;
    }
    var wasSqz = false;
    for (var i = 21; i < n; i++) {
      if (bb.upper[i].isNaN || e20[i].isNaN || at20[i].isNaN || mom[i].isNaN) continue;
      final sqz = bb.upper[i] < e20[i] + 1.5 * at20[i] && bb.lower[i] > e20[i] - 1.5 * at20[i];
      b[i] = mom[i] > 0 ? 1 : -1;
      if (wasSqz && !sqz) t[i] = b[i]; // إطلاق الضغط
      wasSqz = sqz;
    }
    out.add(Ind('sqzm', 'Squeeze Momentum',
        'عندما يخرج Bollinger من داخل قناة Keltner (انتهاء الضغط) يدخل في اتجاه الزخم.', t, b));
  }

  // ── WaveTrend (LazyBear 10/21): تقاطع في مناطق التشبع
  {
    final t = _z(n), b = _z(n);
    final ap = c.map((e) => (e.high + e.low + e.close) / 3).toList();
    final esa = ema(ap, 10);
    final dd = List<double>.filled(n, double.nan);
    for (var i = 0; i < n; i++) {
      if (!esa[i].isNaN) dd[i] = (ap[i] - esa[i]).abs();
    }
    final d = _emaNan(dd, 10);
    final ci = List<double>.filled(n, double.nan);
    for (var i = 0; i < n; i++) {
      if (!d[i].isNaN && d[i] != 0) ci[i] = (ap[i] - esa[i]) / (0.015 * d[i]);
    }
    final wt1 = _emaNan(ci, 21);
    final wt2 = sma(wt1, 4);
    for (var i = 1; i < n; i++) {
      if ([wt1[i], wt2[i], wt1[i - 1], wt2[i - 1]].any((x) => x.isNaN)) continue;
      b[i] = wt1[i] > wt2[i] ? 1 : -1;
      if (wt1[i - 1] <= wt2[i - 1] && wt1[i] > wt2[i] && wt1[i] < -53) t[i] = 1;
      if (wt1[i - 1] >= wt2[i - 1] && wt1[i] < wt2[i] && wt1[i] > 53) t[i] = -1;
    }
    out.add(Ind('wt', 'WaveTrend', 'تقاطع صاعد تحت -53 (تشبع بيعي) = شراء، وتقاطع هابط فوق +53 = بيع.', t, b));
  }

  // ── QQE (RSI 14 مُنعّم 5 + خط ATR للـRSI × 4.236)
  {
    final t = _z(n), b = _z(n);
    final r = _emaNan(rsi(cl, 14), 5);
    final tr = List<double>.filled(n, double.nan);
    for (var i = 1; i < n; i++) {
      if (!r[i].isNaN && !r[i - 1].isNaN) tr[i] = (r[i] - r[i - 1]).abs();
    }
    final dar = _emaNan(_emaNan(tr, 27), 27);
    var long = double.nan, short = double.nan;
    var trend = 0;
    var prevShort = double.nan, prevLong = double.nan;
    for (var i = 1; i < n; i++) {
      if (r[i].isNaN || dar[i].isNaN) continue;
      final dv = dar[i] * 4.236;
      final nl = r[i] - dv, ns = r[i] + dv;
      final prev = trend;
      if (trend == 0) trend = r[i] >= 50 ? 1 : -1;
      // الاختراق يقاس مقابل خط الشمعة السابقة
      if (!prevShort.isNaN && r[i] > prevShort) trend = 1;
      if (!prevLong.isNaN && r[i] < prevLong) trend = -1;
      long = (!long.isNaN && r[i - 1] > long && r[i] > long) ? math.max(long, nl) : nl;
      short = (!short.isNaN && r[i - 1] < short && r[i] < short) ? math.min(short, ns) : ns;
      prevShort = short;
      prevLong = long;
      b[i] = trend;
      if (prev != 0 && trend != prev) t[i] = trend;
    }
    out.add(Ind('qqe', 'QQE', 'RSI مُنعّم مع خط تتبع متكيّف: اختراق الخط = تغيّر الاتجاه.', t, b));
  }

  // ── Hull MA 55: تغيّر الميل
  {
    final t = _z(n), b = _z(n);
    final w1 = _wma(cl, 27), w2 = _wma(cl, 55);
    final raw = List<double>.filled(n, double.nan);
    for (var i = 0; i < n; i++) {
      if (!w1[i].isNaN && !w2[i].isNaN) raw[i] = 2 * w1[i] - w2[i];
    }
    final hma = _wma(raw, 7);
    for (var i = 2; i < n; i++) {
      if (hma[i].isNaN || hma[i - 2].isNaN) continue;
      b[i] = hma[i] > hma[i - 2] ? 1 : -1;
      if (b[i - 1] != 0 && b[i] != b[i - 1]) t[i] = b[i];
    }
    out.add(Ind('hull', 'Hull MA 55', 'متوسط سريع بلا تأخر تقريباً: انقلاب ميله = تغيّر الاتجاه.', t, b));
  }

  // ── SSL Channel 10
  {
    final t = _z(n), b = _z(n);
    final hs = sma(c.map((e) => e.high).toList(), 10), ls = sma(c.map((e) => e.low).toList(), 10);
    var hlv = 0;
    for (var i = 0; i < n; i++) {
      if (hs[i].isNaN) continue;
      final prev = hlv;
      if (cl[i] > hs[i]) hlv = 1;
      if (cl[i] < ls[i]) hlv = -1;
      b[i] = hlv;
      if (prev != 0 && hlv != prev) t[i] = hlv;
    }
    out.add(Ind('ssl', 'SSL Channel', 'إغلاق فوق متوسط القمم = اتجاه صاعد، وتحت متوسط القيعان = هابط.', t, b));
  }

  // ── Range Filter (100 ، 3)
  {
    final t = _z(n), b = _z(n);
    final diff = List<double>.filled(n, double.nan);
    for (var i = 1; i < n; i++) {
      diff[i] = (cl[i] - cl[i - 1]).abs();
    }
    final avr = _emaNan(diff, 100);
    final smr = _emaNan(avr, 199);
    var filt = cl[0];
    var dir = 0;
    for (var i = 1; i < n; i++) {
      if (smr[i].isNaN) continue;
      final r = smr[i] * 3;
      final prevF = filt;
      if (cl[i] > prevF) {
        filt = math.max(prevF, cl[i] - r);
      } else {
        filt = math.min(prevF, cl[i] + r);
      }
      final prev = dir;
      if (filt > prevF) dir = 1;
      if (filt < prevF) dir = -1;
      b[i] = dir;
      if (prev != 0 && dir != prev) t[i] = dir;
    }
    out.add(Ind('rf', 'Range Filter', 'فلتر يتجاهل الحركات الصغيرة: تغيّر اتجاهه = إشارة.', t, b));
  }
  if (at.isEmpty) return out;
  return out;
}

/// EMA يتجاهل القيم NaN في البداية.
List<double> _emaNan(List<double> v, int p) {
  final out = List<double>.filled(v.length, double.nan);
  var start = 0;
  while (start < v.length && v[start].isNaN) {
    start++;
  }
  if (v.length - start < p) return out;
  final sub = ema(v.sublist(start), p);
  for (var i = 0; i < sub.length; i++) {
    out[start + i] = sub[i];
  }
  return out;
}
