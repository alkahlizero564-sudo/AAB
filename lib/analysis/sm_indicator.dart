import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';

/// شريط المتوسطات (مثل DTC): 8 متوسطات EMA من 20 إلى 55.
const smPeriods = [20, 25, 30, 35, 40, 45, 50, 55];

List<List<double>> smRibbon(List<Candle> c) {
  final cl = c.map((e) => e.close).toList();
  return [for (final p in smPeriods) ema(cl, p)];
}

/// اتجاه الشريط عند كل شمعة: +1 كل المتوسطات مرتبة صاعدة، -1 هابطة، 0 متشابكة.
List<int> smDir(List<List<double>> rib, int n) {
  final out = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    if (rib.any((r) => r[i].isNaN)) continue;
    var up = true, dn = true;
    for (var q = 0; q < rib.length - 1; q++) {
      if (!(rib[q][i] > rib[q + 1][i])) up = false;
      if (!(rib[q][i] < rib[q + 1][i])) dn = false;
    }
    out[i] = up ? 1 : (dn ? -1 : 0);
  }
  return out;
}

/// اتجاه فريم أكبر ([mins] دقيقة) عند كل شمعة: EMA20 مقابل EMA50 على إغلاقات
/// الشموع الكبيرة المكتملة فقط (+1 صاعد ، -1 هابط ، 0 غير معروف).
List<int> htfTrend(List<Candle> c, int mins) {
  final n = c.length;
  final out = List<int>.filled(n, 0);
  final sec = mins * 60;
  final closes = <double>[];
  final ends = <int>[];
  for (var i = 0; i < n; i++) {
    final b = c[i].time.millisecondsSinceEpoch ~/ 1000 ~/ sec;
    final nb = i + 1 < n ? c[i + 1].time.millisecondsSinceEpoch ~/ 1000 ~/ sec : b + 1;
    if (nb != b) {
      closes.add(c[i].close);
      ends.add(i);
    }
  }
  final e20 = ema(closes, 20), e50 = ema(closes, 50);
  var p = -1;
  for (var i = 0; i < n; i++) {
    while (p + 1 < ends.length && ends[p + 1] <= i) {
      p++;
    }
    if (p < 0 || e20[p].isNaN || e50[p].isNaN) continue;
    out[i] = e20[p] > e50[p] ? 1 : -1;
  }
  return out;
}

/// اتجاه آخر شمعة مكتملة من شموع فريم معيّن (للوحة الاتجاهات).
int trendOf(List<Candle> c) {
  if (c.length < 52) return 0;
  final cl = c.map((e) => e.close).toList();
  final e20 = ema(cl, 20), e50 = ema(cl, 50);
  final i = c.length - 2;
  if (e20[i].isNaN || e50[i].isNaN) return 0;
  return e20[i] > e50[i] ? 1 : -1;
}

/// مؤشر SM: إشارات Mp التي يوافقها شريط المتوسطات فقط.
/// وعلى الفريمات الأقل من ساعة: يجب أن يوافقها أيضاً اتجاه الساعة (مثل لوحة DTC).
/// مقاس على 26 سوقاً (1R ثم 2R): 58.3% (بدون فلتر الساعة 57.9%، و Mp 57.1%).
AllResult buildSm(List<Candle> c, AllResult mp) {
  final n = c.length;
  final d = smDir(smRibbon(c), n);
  final baseMin = n > 1 ? c[n - 1].time.difference(c[n - 2].time).inMinutes.abs() : 60;
  final h1 = baseMin > 0 && baseMin < 60 ? htfTrend(c, 60) : null;
  bool ok(int i, int dir) =>
      i >= 0 && i < n && d[i] == dir && (h1 == null || h1[i] == 0 || h1[i] == dir);
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    if (ok(s.i, s.dir)) {
      sigs.add(s);
      src.add(mp.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    if (ok(p.i, p.dir)) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
    }
  }
  // لا إشارة منتظرة وهناك صفقة SM مفتوحة
  final open = sigs.isNotEmpty && sigs.last.exitI < 0;
  return AllResult(sigs, src, open ? const [] : pend, open ? const [] : pSrc, 'SM');
}
