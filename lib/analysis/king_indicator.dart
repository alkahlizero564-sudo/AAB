import 'dart:math' as math;
import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';
import 'king_model.dart';
import 'king_model_lt.dart';
import 'sm_indicator.dart';
import 'st_indicator.dart';
import 'star_indicator.dart';

/// مؤشر King 🤖: ذكاء اصطناعي (غابة قرارات من 150 شجرة بعمق 10) يقيّم كل إشارة Mp بـ 54 معلومة:
/// 41 من السوق (الترند، التذبذب، الزخم، المتوسطات، شكل الشمعة، مكان الدخول، الساعة، الفريم الأكبر...)
/// و13 من تحليل مؤشراتنا (ST والنجوم وقريب/ضغط/قاع أعلى، SM وKM، متوسط 200 يوم، الدعم والمقاومة، عمر الشريط).
/// تدرّب على ذهب 2010-2018 وبيتكوين 2017-2020، واختُبر على إشارات لم يرها
/// (ذهب 2019-2025، بيتكوين 2021-2026، إيثيريوم، 5 أزواج عملات، مؤشرات، نفط، فضة):
///  - يعرض أعلى 30% ثقة: 59.5% بهدف 1R (كل الإشارات 55.4%).
///  - «قوي» = أعلى 15%: 62.4% (النموذج السابق 61.5%). الذهب 2019-2025: 61.0%.
///  - خيار «دخول قريب فقط» (الدخول أقل من 0.75 ATR من قاع/قمة آخر 5 شموع): أعلى 30% → 60.6% بنصف الصفقات.
class KingResult {
  final AllResult res;
  final Map<(int, int), double> conf; // (شمعة الإشارة، الاتجاه) → احتمال النجاح المقدّر
  final KingEval? eval; // لتقييم إشارات أي مؤشر آخر (SM و AAB)
  const KingResult(this.res, this.conf, [this.eval]);
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

/// King للفريمات الصغيرة (1m و5m)، ثم تحويل احتماله لنفس مقياس King الأساسي
/// (نفس ترتيب الإشارات، حتى تبقى حدود أعلى 30% و15% صالحة في كل التطبيق).
double _predictLt(List<double> x) {
  var s = 0.0;
  for (final o in kingLtTreeStart) {
    var n = o;
    while (kingLtFeat[n] != -1) {
      n = x[kingLtFeat[n]] <= kingLtThr[n] ? kingLtLeft[n] : kingLtRight[n];
    }
    s += kingLtVal[n];
  }
  final p = s / kingLtTreeStart.length;
  const from = [0.0, ...kingLtQ, 1.0];
  const to = [0.0, kingQ30, kingQ50, kingQ70, kingQ85, 1.0];
  for (var k = 1; k < from.length; k++) {
    if (p <= from[k]) return to[k - 1] + (p - from[k - 1]) / (from[k] - from[k - 1]) * (to[k] - to[k - 1]);
  }
  return 1;
}

/// يحسب خصائص الإشارات ويقيّمها. نفس حساب ملف التدريب تماماً (لا نظر للمستقبل).
class KingScorer {
  final List<Candle> c;
  late final List<double> at, a5, a50, am, e20, e50, e200, r14, r2, stK, adx, plus, minus, bbU, bbM, bbL;
  late final List<List<double>> rib;
  late final List<int> rdF, rdA, h4, hD;
  late final double tfm;
  late final bool lowTf; // 1m و5m: نموذج King الخاص بالفريمات الصغيرة
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
    lowTf = base <= 5;
  }

  double score(int i, int dir, double entry, double sl, String src, [KingCtx? ctx]) {
    final x = features(i, dir, entry, sl, src);
    if (x == null) return double.nan;
    if (kingFeatures.length > x.length) {
      if (ctx == null) return double.nan;
      x.addAll(ctx.extra(this, i, dir, src));
    }
    return lowTf ? _predictLt(x) : _predict(x);
  }

  /// الخصائص الـ 41 بنفس ترتيب [kingFeatures] (null إن لم تتوفر).
  List<double>? features(int i, int dir, double entry, double sl, String src) {
    if (i < 210 || i >= c.length) return null;
    final d = dir.toDouble();
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    if (!(a > 0)) return null;
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
    return x;
  }
}

/// معلومات مؤشراتنا الـ 13 (بنفس حساب ملف التدريب).
class KingCtx {
  final List<Candle> c;
  final StarResult st;
  final Set<(int, int)> sm, km;
  final StScorer sc;
  final Map<int, double> sma200 = {}; // يوم → متوسط 200 يوم حتى اليوم السابق
  final List<(double, int)> piv = []; // قمم وقيعان (3 شموع كل جانب)
  KingCtx(this.c, this.st, AllResult smR, AllResult kmR, {List<Candle>? daily})
      : sc = StScorer(c),
        sm = {for (final s in smR.signals) (s.i, s.dir), for (final p in smR.pending) (p.i, p.dir)},
        km = {for (final s in kmR.signals) (s.i, s.dir), for (final p in kmR.pending) (p.i, p.dir)} {
    final dayClose = <int, double>{};
    final dayKeys = <int>[];
    final src = daily != null && daily.length >= 201 ? daily : c;
    for (final x in src) {
      final kd = x.time.millisecondsSinceEpoch ~/ 86400000;
      if (!dayClose.containsKey(kd)) dayKeys.add(kd);
      dayClose[kd] = x.close;
    }
    if (dayKeys.length > 200) {
      var s0 = 0.0;
      for (var r = 0; r < 200; r++) {
        s0 += dayClose[dayKeys[r]]!;
      }
      for (var q = 200; q < dayKeys.length; q++) {
        sma200[dayKeys[q]] = s0 / 200;
        s0 += dayClose[dayKeys[q]]! - dayClose[dayKeys[q - 200]]!;
      }
      // اليوم الحالي (لم يكتمل بعد في اليومي) يأخذ متوسط آخر 200 يوم مكتمل
      sma200.putIfAbsent(dayKeys.last + 1, () => s0 / 200);
    }
    final n = c.length;
    for (var j = 3; j < n - 3; j++) {
      var isH = true, isL = true;
      for (var q = j - 3; q <= j + 3; q++) {
        if (q == j) continue;
        if (c[q].high >= c[j].high) isH = false;
        if (c[q].low <= c[j].low) isL = false;
      }
      if (isH) piv.add((c[j].high, j));
      if (isL) piv.add((c[j].low, j));
    }
  }

  List<double> extra(KingScorer k, int i, int d, String src) {
    final a = k.at[i].isNaN ? 1.0 : k.at[i], px = c[i].close;
    var behind = 10.0, ahead = 10.0;
    for (final (lv, j) in piv) {
      if (j < i - 300 || j + 3 > i) continue;
      final dd = (px - lv) * d / a;
      if (dd >= 0) {
        behind = math.min(behind, dd);
      } else {
        ahead = math.min(ahead, -dd);
      }
    }
    final rd = k.rdF;
    var age = 0;
    for (var t = i; t > 0 && rd[t] == rd[i] && rd[i] != 0; t--) {
      age++;
    }
    final s200 = sma200[c[i].time.millisecondsSinceEpoch ~/ 86400000];
    final dUp = s200 == null ? 0.0 : (px > s200 ? 1.0 : -1.0);
    final rib = k.rib;
    final wide = !rib.first[i].isNaN && (rib.first[i] - rib.last[i]) * d / a >= 2;
    final held = st.isHeld(i, d), hot = st.isHot(i, d);
    final x = <double>[
      sc.score(i, d, src), st.of(i, d).toDouble(), st.isNear(i, d) ? 1 : 0, hot ? 1 : 0, held ? 1 : 0,
      sm.contains((i, d)) ? 1 : 0, (wide || held || hot) ? 1 : 0, km.contains((i, d)) ? 1 : 0,
      dUp * d, behind, ahead, math.min(age, 200).toDouble(), (dUp > 0 && d > 0) ? 1 : 0,
    ];
    for (var q = 0; q < x.length; q++) {
      x[q] = (x[q] * 10000).roundToDouble() / 10000;
    }
    return x;
  }
}

/// يقيّم أي إشارة بنموذج King (نفس المعلومات الـ 54).
class KingEval {
  final KingScorer sc;
  final KingCtx ctx;
  const KingEval(this.sc, this.ctx);
  double score(int i, int dir, double entry, double sl, String src) => sc.score(i, dir, entry, sl, src, ctx);
}

/// فلتر الذكاء على مؤشر آخر: يُبقي الإشارات التي يضعها King في أعلى [top]% (0 = بدون فلتر).
/// اختبار على إشارات لم يرها (1R): SM 56.7% → 60.5% (30%) → 63.9% (15%)،
/// و AAB 56.0% → 62.4% (30%) → 66.0% (15%).
/// [wide]/[wideTop]: الإشارات التي يتحقق فيها [wide] (مثل نجمتين فأكثر) يكفيها أعلى [wideTop]%.
AllResult kingFilter(AllResult r, KingEval? e, int top,
    {bool Function(int i, int dir)? keep, int wideTop = 0, bool Function(int i, int dir)? wide}) {
  if (top == 0 || e == null) return r;
  final thr = kingThreshold(top), thrW = wideTop == 0 ? thr : kingThreshold(wideTop);
  bool pass(int i, int dir, double sc) => sc >= thr || (wide != null && i >= 0 && wide(i, dir) && sc >= thrW);
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in r.signals.indexed) {
    if ((keep?.call(s.i, s.dir) ?? false) || pass(s.i, s.dir, e.score(s.i, s.dir, s.entry, s.sl, r.sources[q]))) {
      sigs.add(s);
      src.add(r.sources[q]);
    }
  }
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in r.pending.indexed) {
    if (!openDirs.contains(p.dir) && pass(p.i, p.dir, e.score(p.i, p.dir, p.trigger, p.sl, r.pendingSrc[q]))) {
      pend.add(p);
      pSrc.add(r.pendingSrc[q]);
    }
  }
  return AllResult(sigs, src, pend, pSrc, r.tag, r.extra);
}

/// نفس فلتر الذكاء على توصيات AAB.
Forecast kingFilterForecast(Forecast f, KingEval? e, int top, {bool Function(int i, int dir)? keep}) {
  if (top == 0 || e == null) return f;
  final thr = kingThreshold(top);
  final sigs = [for (final s in f.signals) if ((keep?.call(s.i, s.dir) ?? false) || e.score(s.i, s.dir, s.entry, s.sl, 'AAB') >= thr) s];
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final pend = [for (final p in f.pending) if (!openDirs.contains(p.dir) && e.score(p.i, p.dir, p.trigger, p.sl, 'AAB') >= thr) p];
  return Forecast(
    patterns: f.patterns,
    signals: sigs,
    predHits: f.predHits,
    predN: f.predN,
    predOk: f.predOk,
    next: f.next,
    pending: pend,
    ema20: f.ema20,
    ema50: f.ema50,
    ema200: f.ema200,
    liveSignal: f.liveSignal,
    indicators: f.indicators,
    liveDir: f.liveDir,
  );
}

/// حد الثقة لكل خيار عرض: أعلى 15% / 30% / 50% / 70% من إشارات التدريب.
/// بهدف 1R على بيانات لم يرها (كل الأسواق): 62.4% / 59.5% / 57.8% / 56.5% تقريباً (كل الإشارات 55.4%).
double kingThreshold(int top) => switch (top) {
      15 => kingQ85,
      50 => kingQ50,
      70 => kingQ30,
      _ => kingQ70,
    };

/// بُعد سعر الدخول عن قاع (للشراء) / قمة (للبيع) آخر 5 شموع بوحدات ATR.
double kingEntryDist(List<Candle> c, List<double> at, int i, int d, double entry) {
  if (i < 4 || i >= c.length || at[i].isNaN || !(at[i] > 0)) return 1;
  var ext = d > 0 ? double.infinity : -double.infinity;
  for (var q = i - 4; q <= i; q++) {
    ext = d > 0 ? math.min(ext, c[q].low) : math.max(ext, c[q].high);
  }
  return (entry - ext) * d / at[i];
}

/// King: إشارات Mp التي يضعها الذكاء الاصطناعي في أعلى [top]% ثقة (الافتراضي 30%).
/// [nearOnly]: يعرض فقط الإشارات التي دخولها قريب (< 0.75 ATR من قاع/قمة آخر 5 شموع).
KingResult buildKing(List<Candle> c, AllResult mp,
    {int top = 30, StarResult? stars, AllResult? sm, AllResult? km, List<Candle>? daily, bool nearOnly = false, bool Function(int i, int dir)? stick}) {
  final thr = kingThreshold(top);
  if (c.length < 260) return KingResult.empty;
  final sc = KingScorer(c);
  final st = stars ?? buildStar(c, mp);
  final smR = sm ?? buildSm(c, mp, stars: st);
  final ctx = KingCtx(c, st, smR, km ?? buildKm(c, smR), daily: daily);
  bool far(int i, int d, double e) => nearOnly && kingEntryDist(c, sc.at, i, d, e) >= 0.75;
  final conf = <(int, int), double>{};
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    final p = sc.score(s.i, s.dir, s.entry, s.sl, mp.sources[q], ctx);
    if (p.isNaN) continue;
    conf[(s.i, s.dir)] = p;
    if ((stick?.call(s.i, s.dir) ?? false) || (p >= thr && !far(s.i, s.dir, s.entry))) {
      sigs.add(s);
      src.add(mp.sources[q]);
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    final pr = sc.score(p.i, p.dir, p.trigger, p.sl, mp.pendingSrc[q], ctx);
    if (pr.isNaN) continue;
    conf[(p.i, p.dir)] = pr;
    if (pr >= thr && !far(p.i, p.dir, p.trigger)) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
    }
  }
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  final keep = [for (var q = 0; q < pend.length; q++) if (!openDirs.contains(pend[q].dir)) q];
  return KingResult(AllResult(sigs, src, [for (final q in keep) pend[q]], [for (final q in keep) pSrc[q]], 'King'), conf, KingEval(sc, ctx));
}
