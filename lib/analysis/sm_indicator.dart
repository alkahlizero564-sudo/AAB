import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'alka.dart';
import 'zero_one.dart';
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

/// الشريط السريع: أول 4 متوسطات (20–35) مرتبة → يلتقط بداية الاتجاه أبكر من الشريط الكامل.
List<int> smDirFast(List<List<double>> rib, int n) => smDir(rib.sublist(0, 4), n);

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
/// الشريط السريع + منع المطاردة: الإشارة أبكر بحوالي 30% (2.25 ATR بدل 3.2 من بداية الحركة).
/// مقاس على 26 سوقاً (1R ثم 2R): 58.2% ، رابح في 24 من 26 (Mp 57.1%).
AllResult buildSm(List<Candle> c, AllResult mp) {
  final n = c.length;
  final rib = smRibbon(c);
  final d = smDirFast(rib, n);
  final at = atr(c, 14);
  // منع المطاردة: لا إشارة إذا ابتعد السعر عن EMA20 أكثر من 1.5 ATR في اتجاه الصفقة
  bool notLate(int i, int dir) => at[i].isNaN || at[i] <= 0 || (c[i].close - rib.first[i]) * dir / at[i] < 1.5;
  final baseMin = n > 1 ? c[n - 1].time.difference(c[n - 2].time).inMinutes.abs() : 60;
  final h1 = baseMin > 0 && baseMin < 60 ? htfTrend(c, 60) : null;
  bool ok(int i, int dir) =>
      i >= 0 && i < n && d[i] == dir && notLate(i, dir) && (h1 == null || h1[i] == 0 || h1[i] == dir);
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

/// مؤشر KM: إشارات SM في السوق الهادئ فقط (تذبذب الآن أقل من 0.9 من متوسطه على 100 شمعة).
/// مقاس على 26 سوقاً (1R ثم 2R): 61.8% (SM 58.2%)، والربح لكل صفقة 0.26R (SM 0.18R)،
/// رابح في 21 من 26 — بثلث صفقات SM تقريباً.
AllResult buildKm(List<Candle> c, AllResult sm) {
  final n = c.length;
  final at = atr(c, 14);
  final m = sma(at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
  bool calm(int i) => i >= 0 && i < n && !at[i].isNaN && !m[i].isNaN && m[i] > 0 && at[i] / m[i] < 0.9;
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in sm.signals.indexed) {
    if (calm(s.i)) {
      sigs.add(s);
      src.add(sm.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in sm.pending.indexed) {
    if (calm(p.i)) {
      pend.add(p);
      pSrc.add(sm.pendingSrc[q]);
    }
  }
  final open = sigs.isNotEmpty && sigs.last.exitI < 0;
  return AllResult(sigs, src, open ? const [] : pend, open ? const [] : pSrc, 'KM');
}

/// اتجاه اليومي عند كل شمعة من شموع يومية منفصلة: EMA20 مقابل EMA50 لآخر يوم اكتمل قبل الشمعة.
List<int> dailyTrendFor(List<Candle> c, List<Candle> daily) {
  final n = c.length;
  final out = List<int>.filled(n, 0);
  if (daily.length < 52) return out;
  final cl = daily.map((e) => e.close).toList();
  final e20 = ema(cl, 20), e50 = ema(cl, 50);
  var p = -1;
  for (var i = 0; i < n; i++) {
    // اليوم يكتمل عند بداية اليوم التالي
    while (p + 1 < daily.length && daily[p + 1].time.add(const Duration(days: 1)).compareTo(c[i].time) <= 0) {
      p++;
    }
    if (p < 0 || e20[p].isNaN || e50[p].isNaN) continue;
    out[i] = e20[p] > e50[p] ? 1 : -1;
  }
  return out;
}

/// مؤشر DM (خاص بالذهب والمعادن) — مؤشر مستقل:
/// يأخذ مرشحي المحركات الثلاثة (AAB و Alka و 0.1) مباشرة، ويطبق قواعد الذهب عليها أولاً
/// (لا تداول يوم الجمعة + فقط مع الترند اليومي)، ثم يختار صفقاته بنفسه (صفقة واحدة كل مرة،
/// فلتر الشمعة الصغيرة على AAB و Alka، وأولوية 0.1).
/// مقاس: ذهب 2018-19 59.7% (Mp 57.5%)، ذهب 2026 77.4% (Mp 65.6%)، فضة 2026 56.8% (Mp 54.7%).
AllResult buildDm(List<Candle> c, MarketSymbol sym,
    {required Forecast aab, required AlkaResult alka, required ZeroResult zero, List<Candle>? daily}) {
  if (sym.category != 'metal' || c.length < 2) return const AllResult([], [], [], [], 'DM');
  final n = c.length;
  final dt = daily != null && daily.length >= 52 ? dailyTrendFor(c, daily) : htfTrend(c, 1440);
  bool ok(int i, int dir) => i >= 0 && i < n && c[i].time.weekday != DateTime.friday && dt[i] == dir;
  return combineAll(
    c,
    aab.signals.where((s) => ok(s.i, s.dir)).toList(),
    aab.pending.where((p) => ok(p.i, p.dir)).toList(),
    alka.signals.where((s) => ok(s.i, s.dir)).toList(),
    alka.pending.where((p) => ok(p.i, p.dir)).toList(),
    zero: zero.signals.where((s) => ok(s.i, s.dir)).toList(),
    zeroPending: zero.pending.where((p) => ok(p.i, p.dir)).toList(),
    tag: 'DM',
  );
}
