import 'dart:math' as math;

import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';

/// منطقة فيبوناتشي: بعد موجة صاعدة منطقة شراء خضراء، وبعد موجة هابطة منطقة بيع حمراء.
class FibZone {
  final int dir; // +1 خضراء (بعد موجة صاعدة) ، -1 حمراء
  final int from, to; // من شمعة ظهورها إلى شمعة انتهائها
  final double z5, z618, z786;
  const FibZone(this.dir, this.from, this.to, this.z5, this.z618, this.z786);
}

class FzResult {
  final List<FibZone> zones;
  final AllResult res; // الإشارات: ارتداد من المنطقة أو كسرها
  const FzResult(this.zones, this.res);
}

/// مؤشر FZ — مناطق الفيبوناتشي (0.5 إلى 0.618 من آخر موجة ≥ 3 ATR).
/// • ارتداد: السعر دخل المنطقة ثم أغلقت شمعة خارجها باتجاه الموجة ← إشارة مع الموجة.
/// • كسر: إغلاق بعد مستوى 0.786 ← إشارة عكس الموجة.
/// الإشارة تظهر فقط إذا وافقتها إشارة Mp بنفس الاتجاه خلال آخر 3 شموع.
/// اختبار (ذهب 2019+ بعد السبريد، بيتكوين 2021+، دقة الهدف 1R): 53-55% — مثل Mp تقريباً.
/// بدون موافقة Mp كانت ~50% (مثل العشوائي)، لذلك هي شرط.
FzResult buildFz(List<Candle> c, AllResult? mp, {double minStop = 0}) {
  final n = c.length;
  final zones = <FibZone>[];
  final sigs = <PastSignal>[];
  final kinds = <String>[];
  if (n < 60) return FzResult(zones, AllResult(sigs, kinds, const [], const [], 'FZ'));
  final a = atr(c);
  // إشارات Mp: (شمعة، اتجاه)
  final mpAt = <(int, int)>{};
  for (final s in mp?.signals ?? const <PastSignal>[]) {
    for (var q = s.i; q <= s.i + 3; q++) {
      mpAt.add((q, s.dir));
    }
  }
  const k = 5;
  var ph = -1, pl = -1;
  // المنطقة الفعّالة
  int? zDir, zFrom, zEnd;
  double z5 = 0, z6 = 0, z7 = 0;
  var entered = false;
  void close(int i) {
    if (zDir != null) zones.add(FibZone(zDir!, zFrom!, i, z5, z6, z7));
    zDir = null;
  }

  for (var i = 2 * k + 15; i < n - 1; i++) {
    final j = i - k;
    var newP = false;
    var hMax = true, lMin = true;
    for (var q = j - k; q <= j + k; q++) {
      if (c[q].high > c[j].high) hMax = false;
      if (c[q].low < c[j].low) lMin = false;
    }
    if (hMax) {
      ph = j;
      newP = true;
    }
    if (lMin) {
      pl = j;
      newP = true;
    }
    if (newP && ph > 0 && pl > 0) {
      final d = pl < ph ? 1 : -1;
      final hi = c[ph].high, lo = c[pl].low, leg = hi - lo;
      final s1 = math.max(ph, pl);
      final av = a[s1];
      if (!av.isNaN && leg >= 3 * av) {
        close(i);
        double fib(double x) => d > 0 ? hi - x * leg : lo + x * leg;
        zDir = d;
        zFrom = i;
        zEnd = s1 + 80;
        z5 = fib(0.5);
        z6 = fib(0.618);
        z7 = fib(0.786);
        entered = false;
      }
    }
    if (zDir == null) continue;
    final d = zDir!;
    if (i > zEnd!) {
      close(i);
      continue;
    }
    final k0 = c[i];
    if (d > 0 ? k0.low <= z5 : k0.high >= z5) entered = true;
    int sig = 0;
    String kind = '';
    if (entered && (d > 0 ? k0.close < z7 : k0.close > z7)) {
      sig = -d;
      kind = 'كسر منطقة الفيبو';
    } else if (entered &&
        (d > 0 ? (k0.close > z5 && k0.low > z7 && k0.close > k0.open) : (k0.close < z5 && k0.high < z7 && k0.close < k0.open))) {
      sig = d;
      kind = 'ارتداد من منطقة الفيبو';
    }
    if (sig == 0) continue;
    close(i);
    if (!mpAt.contains((i, sig))) continue;
    // الدخول افتتاح الشمعة التالية، الوقف خلف آخر 3 شموع (0.7-2.5 ATR)، الأهداف 1R و2R
    final av = a[i];
    if (av.isNaN || av <= 0) continue;
    final e = c[i + 1].open;
    var ext = sig > 0 ? c[i].low : c[i].high;
    for (var q = i - 2; q <= i; q++) {
      ext = sig > 0 ? math.min(ext, c[q].low) : math.max(ext, c[q].high);
    }
    final rk = math.max(((e - ext) * sig + 0.1 * av).clamp(0.7 * av, 2.5 * av).toDouble(), minStop);
    final sl = e - sig * rk, t1 = e + sig * rk, t2 = e + 2 * sig * rk;
    var stop = sl, got = false, res = 0, exitI = -1;
    var exitP = double.nan;
    for (var q = i + 1; q < n; q++) {
      final b = c[q];
      if (sig > 0 ? b.low <= stop : b.high >= stop) {
        res = got ? 1 : -1;
        exitI = q;
        exitP = stop;
        break;
      }
      if (!got && (sig > 0 ? b.high >= t1 : b.low <= t1)) {
        got = true;
        stop = e;
      }
      if (got && (sig > 0 ? b.high >= t2 : b.low <= t2)) {
        res = 2;
        exitI = q;
        exitP = t2;
        break;
      }
    }
    if (res == 0 && got) res = 1;
    sigs.add(PastSignal(i, sig, e, sl, t1, t2, exitI < 0 ? (got ? 1 : 0) : res, exitI, kind, false, 0, 0, exitP,
        exitI < 0 ? stop : double.nan));
    kinds.add(kind);
  }
  close(n - 1);
  return FzResult(zones, AllResult(sigs, kinds, const [], const [], 'FZ'));
}
