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

/// مؤشر SM: إشارات Mp التي يوافقها شريط المتوسطات فقط.
/// مقاس على 26 سوقاً (1R ثم 2R): 57.9% مقابل 57.1% لـ Mp، وعلى الذهب 59.3% مقابل 57.9%،
/// بنصف عدد صفقات Mp تقريباً.
AllResult buildSm(List<Candle> c, AllResult mp) {
  final d = smDir(smRibbon(c), c.length);
  bool ok(int i, int dir) => i >= 0 && i < c.length && d[i] == dir;
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
