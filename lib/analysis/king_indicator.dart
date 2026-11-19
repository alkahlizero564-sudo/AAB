import 'dart:math' as math;
import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';
import 'king_model.dart';
import 'sm_indicator.dart';

/// مؤشر King 🤖: ذكاء اصطناعي (غابة قرارات من 100 شجرة) يقيّم كل إشارة Mp بـ 41 معلومة
/// (الترند، التذبذب، الزخم، المتوسطات، شكل الشمعة، مكان الدخول، الساعة، الفريم الأكبر...).
/// تدرّب على ذهب 2010-2018 وبيتكوين 2017-2020، واختُبر على 20 ألف إشارة لم يرها
/// (ذهب 2019-2025، بيتكوين 2021-2026، إيثيريوم، 5 أزواج عملات، مؤشرات، نفط، فضة):
///  - يعرض أعلى 30% ثقة: 59.4% بهدف 1R (كل الإشارات 55.4%، النجوم بنجمتين 58.5%).
///  - «قوي» = أعلى 15%: 61.6%. الذهب 2019-2025: ~61%.
class KingResult {
  final AllResult res;
  final Map<(int, int), double> conf; // (شمعة الإشارة، الاتجاه) → احتمال النجاح المقدّر
  const KingResult(this.res, this.conf);
  static const empty = KingResult(AllResult([], [], [], [], 'King'), {});
  double of(int i, int d) => conf[(i, d)] ?? double.nan;
  bool isStrong(int i, int d) => (conf[(i, d)] ?? 0) >= kingQ85;
  /// الثقة كنسبة مئوية للعرض (الاحتمال المقدّر)
  int pct(int i, int d) => ((conf[(i, d)] ?? 0) * 100).round();
}

double _predict(List<double> x) {
  var s = 0.0;
  for (final o in kingTreeStart) {
    var n = o;
    while (kingFeat[n] != -1) {
      n = x[kingFeat[n]] <= kingThr[n] ? kingLeft[n] : kingRight[n];
    }
    s += kingVal[n];
  }
  return s / kingTreeStart.length;
}

/// يحسب خصائص الإشارات ويقيّمها. نفس حساب ملف التدريب تماماً (لا نظر للمستقبل).
class KingScorer {
  final List<Candle> c;
  late final List<double> at, a5, a50, am, e20, e50, e200, r14, r2, stK, adx, plus, minus, bbU, bbM, bbL;
  late final List<List<double>> rib;
  late final List<int> rdF, rdA, h4, hD;
  late final double tfm;
  KingScorer(this.c) {
    final n = c.length;
    final cl = [for (final x in c) x.close];
    at = atr(c, 14);
    a5 = atr(c, 5);
    a50 = atr(c, 50);
    am = sma(at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
    e20 = ema(cl, 20);
    e50 = ema(cl, 50);
    e200 = ema(cl, 200);
    r14 = rsi(cl, 14);
    r2 = rsi(cl, 2);
    rib = smRibbon(c);
    rdF = smDirFast(rib, n);
    rdA = smDir(rib, n);
    final bb = bollinger(cl, 20, 2);
    bbU = bb.upper;
    bbM = bb.mid;
    bbL = bb.lower;
    final ax = adxCalc(c, 14);
    adx = ax.adx;
    plus = ax.plus;
    minus = ax.minus;
    stK = stoch(c, 14, 3, 3).k;
    final gaps = [for (var i = 1; i < math.min(n, 400); i++) c[i].time.difference(c[i - 1].time).inMinutes.abs()]..sort();
    final base = gaps.isEmpty ? 60 : gaps[gaps.length ~/ 2];
    h4 = htfTrend(c, base < 60 ? 60 : base < 240 ? 240 : 1440);
    hD = htfTrend(c, 1440);
    // التدريب كان على 15m و1h و4h فقط: الفريمات الأخرى تُقرّب لأقربها
    tfm = base <= 30 ? 15 : base <= 120 ? 60 : 240;
  }

  double score(int i, int dir, double entry, double sl, String src) {
    if (i < 210 || i >= c.length) return double.nan;
    final d = dir.toDouble();
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    if (!(a > 0)) return double.nan;
    double nz(double x) => x.isNaN || x.isInfinite ? 0 : x;
    final kk = c[i], rng = math.max(1e-9, kk.high - kk.low);
    double ret(int b) => (kk.close - c[i - b].close) * d / a;
    var ext5 = d > 0 ? 1e18 : -1e18;
    for (var t = i - 4; t <= i; t++) {
      ext5 = d > 0 ? math.min(ext5, c[t].low) : math.max(ext5, c[t].high);
    }
    var hi20 = -1e18, lo20 = 1e18;
    for (var t = i - 19; t <= i; t++) {
      hi20 = math.max(hi20, c[t].high);
      lo20 = math.min(lo20, c[t].low);
    }
    var hi50 = -1e18, lo50 = 1e18;
    for (var t = i - 49; t <= i; t++) {
      hi50 = math.max(hi50, c[t].high);
      lo50 = math.min(lo50, c[t].low);
    }
    var same = 0;
    for (var t = i; t > i - 10 && (c[t].close - c[t].open) * d > 0; t--) {
      same++;
    }
    var opp5 = 0;
    for (var t = i - 4; t <= i; t++) {
      if ((c[t].close - c[t].open) * d < 0) opp5++;
    }
    final pos50 = (kk.close - lo50) / math.max(1e-9, hi50 - lo50);
    final x = <double>[
      nz(at[i] / am[i]), nz(a5[i] / a50[i]),
      ret(3), ret(5), ret(10), ret(20), ret(50),
      nz((kk.close - e20[i]) * d / a), nz((kk.close - e50[i]) * d / a), nz((kk.close - e200[i]) * d / a),
      nz((e20[i] - e20[i - 5]) * d / a), rdF[i] * d, rdA[i] * d,
      nz((rib.first[i] - rib.last[i]) * d / a),
      nz((r14[i] - 50) * d / 50), nz((r2[i] - 50) * d / 50),
      nz((stK[i] - 50) * d / 50), nz(adx[i] / 50), nz((plus[i] - minus[i]) * d / 50),
      nz(((kk.close - bbM[i]) / math.max(1e-9, bbU[i] - bbM[i])) * d), nz((bbU[i] - bbL[i]) / a),
      (kk.close - kk.open) * d / rng, rng / a,
      ((d > 0 ? math.min(kk.open, kk.close) - kk.low : kk.high - math.max(kk.open, kk.close)) / rng),
      ((d > 0 ? kk.high - math.max(kk.open, kk.close) : math.min(kk.open, kk.close) - kk.low) / rng),
      (entry - ext5) * d / a, (entry - sl).abs() / a,
      (d > 0 ? hi20 - kk.close : kk.close - lo20) / a, (d > 0 ? kk.close - lo20 : hi20 - kk.close) / a,
      d > 0 ? pos50 : 1 - pos50, same.toDouble(), opp5.toDouble(),
      h4[i] * d, hD[i] * d,
      math.sin(2 * math.pi * kk.time.hour / 24), math.cos(2 * math.pi * kk.time.hour / 24), kk.time.weekday.toDouble(),
      src == 'Alka' ? 1 : 0, src == 'AAB' ? 1 : 0, src == '0.1' ? 1 : 0, tfm,
    ];
    // نفس دقة ملف التدريب (4 أرقام عشرية)
    for (var q = 0; q < x.length; q++) {
      x[q] = (x[q] * 10000).roundToDouble() / 10000;
    }
    return _predict(x);
  }
}

/// King: إشارات Mp التي يضعها الذكاء الاصطناعي في أعلى 30% ثقة.
KingResult buildKing(List<Candle> c, AllResult mp) {
  if (c.length < 260) return KingResult.empty;
  final sc = KingScorer(c);
  final conf = <(int, int), double>{};
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    final p = sc.score(s.i, s.dir, s.entry, s.sl, mp.sources[q]);
    if (p.isNaN) continue;
    conf[(s.i, s.dir)] = p;
    if (p >= kingQ70) {
      sigs.add(s);
      src.add(mp.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    final pr = sc.score(p.i, p.dir, p.trigger, p.sl, mp.pendingSrc[q]);
    if (pr.isNaN) continue;
    conf[(p.i, p.dir)] = pr;
    if (pr >= kingQ70) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
    }
  }
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final keep = [for (var q = 0; q < pend.length; q++) if (!openDirs.contains(pend[q].dir)) q];
  return KingResult(AllResult(sigs, src, [for (final q in keep) pend[q]], [for (final q in keep) pSrc[q]], 'King'), conf);
}
