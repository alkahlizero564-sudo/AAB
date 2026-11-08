import 'dart:math' as math;
import '../models.dart';
import '../services/settings_service.dart';
import 'indicators.dart';
import 'levels.dart';
import 'patterns.dart';
import 'pro.dart';
import 'smc.dart';

class SignalEngine {
  static const _minCandles = 60;

  static const _core = {
    'EMA 20/50', 'MACD', 'ADX/DI', 'Supertrend', 'Ichimoku',
    'Chandelier Exit', 'SR Breaks', 'Order Block', 'FVG',
    'Liquidity Sweep', 'Premium/Discount', 'الإطار الأعلى',
    'Fibonacci', 'VWAP',
  };

  static int htfTrend(List<Candle>? h) {
    if (h == null || h.length < 55) return 0;
    final cl = h.map((e) => e.close).toList();
    final e20 = ema(cl, 20).last, e50 = ema(cl, 50).last, p = cl.last;
    if (e20.isNaN || e50.isNaN) return 0;
    if (p > e20 && e20 > e50) return 1;
    if (p < e20 && e20 < e50) return -1;
    return 0;
  }

  static double? _nearestSwing(List<Candle> c, double entry, bool low) {
    double? best;
    final start = math.max(3, c.length - 60);
    for (var i = start; i < c.length - 3; i++) {
      if (low) {
        final v = c[i].low;
        final isPivot = v < c[i - 1].low && v < c[i - 2].low &&
            v < c[i + 1].low && v < c[i + 2].low;
        if (isPivot && v < entry && (best == null || v > best)) best = v;
      } else {
        final v = c[i].high;
        final isPivot = v > c[i - 1].high && v > c[i - 2].high &&
            v > c[i + 1].high && v > c[i + 2].high;
        if (isPivot && v > entry && (best == null || v < best)) best = v;
      }
    }
    return best;
  }

  static TradeSignal analyze(List<Candle> c,
      {List<Candle>? htf,
      required AppSettings s,
      required MarketSymbol sym,
      EngineConfig? cfg}) {
    final cf = cfg ?? EngineConfig.current;
    final now = DateTime.now();
    if (cf.mode == 'pro') {
      // trader-style pipeline: compute overlays with the vote engine, then decide
      final base = analyze(c,
          htf: htf,
          s: s,
          sym: sym,
          cfg: cf.copy(mode: 'vote', minScore: 0, minAligned: 0, htfGate: false, prune: false));
      return ProEngine.decide(base, c, htf, s, sym, cf);
    }
    if (c.length < _minCandles) {
      return TradeSignal(
        direction: Direction.neutral, score: 0,
        price: c.isEmpty ? 0 : c.last.close, entry: 0, stopLoss: 0,
        tp1: 0, tp2: 0, atr: 0, votes: const [], patterns: const [],
        reasons: const ['بيانات غير كافية للتحليل'], htfTrend: 0, time: now,
      );
    }
    final n = c.length, i = n - 1;
    final cl = c.map((e) => e.close).toList();
    final price = cl[i];

    // ── classic indicators
    final e20 = ema(cl, 20), e50 = ema(cl, 50), e200 = ema(cl, 200);
    final r = rsi(cl, 14);
    final m = macd(cl);
    final bb = bollinger(cl);
    final at = atr(c, 14);
    final sto = stoch(c);
    final ad = adxCalc(c);
    final cc = cci(c);
    final wr = williamsR(c);
    final a = at[i].isNaN ? (c.last.high - c.last.low) : at[i];

    // ── indicators from the videos (SMC / ICT)
    final ce = chandelier(c, period: s.cePeriod, mult: s.ceMult);
    final sup = supertrend(c);
    final sr = srBreaks(c, at);
    final obs = orderBlocks(c);
    final fvg = fairValueGaps(c, at);
    final eq = equalLevels(c, a);
    final eqLvl = equilibrium(c);
    final vp = buildVp(c);
    final kz = killzone(c.last.time);

    // ── Fibonacci / VWAP / day & session levels
    final fibRes = fibonacci(c);
    final vw = vwapSeries(c, vwapAnchorTs(sym, c.last.time));
    final vwapLast = vw[i];
    final day = dayLevels(c, htf, c.last.time);
    final kl = buildKeyLevels(day, vp, vwapLast);
    final sw = [...liquiditySweeps(c, eq), ...levelSweeps(c, kl)]
      ..sort((x, y) => x.i.compareTo(y.i));

    final votes = <IndicatorVote>[];
    double sum = 0, maxW = 0;
    void add(String name, String val, int vote, double w, {bool event = false}) {
      votes.add(IndicatorVote(name, val, vote));
      if (event && vote == 0) return;
      sum += vote * w;
      maxW += w;
    }

    final adxNow = ad.adx[i].isNaN ? 0.0 : ad.adx[i];

    if (!cf.prune && !e20[i].isNaN && !e50[i].isNaN) {
      final v = (price > e20[i] && e20[i] > e50[i])
          ? 1
          : (price < e20[i] && e20[i] < e50[i])
              ? -1
              : 0;
      add('EMA 20/50', v == 1 ? 'صاعد' : v == -1 ? 'هابط' : 'متذبذب', v, 12);
    }
    if (!e200[i].isNaN) {
      add('EMA 200', price > e200[i] ? 'فوق المتوسط' : 'تحت المتوسط',
          price > e200[i] ? 1 : -1, 6);
    }
    if (!cf.lean && !m.hist[i].isNaN && !m.hist[i - 1].isNaN) {
      final h = m.hist[i];
      var w = 10.0;
      var crossed = false;
      for (var k = 1; k <= 3; k++) {
        final prev = m.hist[i - k];
        if (!prev.isNaN && ((h > 0 && prev <= 0) || (h < 0 && prev >= 0))) {
          crossed = true;
        }
      }
      if (crossed) w += 4;
      add('MACD', '${h > 0 ? 'إيجابي' : 'سلبي'}${crossed ? ' (تقاطع)' : ''}',
          h > 0 ? 1 : -1, w);
    }
    if (!r[i].isNaN) {
      int v;
      double w;
      String t;
      if (r[i] < 30) {
        v = 1; w = 8; t = 'تشبع بيعي';
      } else if (r[i] > 70) {
        v = -1; w = 8; t = 'تشبع شرائي';
      } else {
        v = r[i] > 50 ? 1 : -1; w = 4; t = r[i] > 50 ? 'زخم صاعد' : 'زخم هابط';
      }
      add('RSI 14', '${r[i].toStringAsFixed(1)} • $t', v, w);
    }
    if (!cf.lean && !sto.k[i].isNaN && !sto.d[i].isNaN) {
      final k = sto.k[i], d = sto.d[i];
      int v;
      double w;
      if (k < 20 && k > d) {
        v = 1; w = 6;
      } else if (k > 80 && k < d) {
        v = -1; w = 6;
      } else {
        v = k > d ? 1 : -1; w = 2;
      }
      add('Stochastic', 'K ${k.toStringAsFixed(0)} / D ${d.toStringAsFixed(0)}', v, w);
    }
    if (!cf.lean && !bb.mid[i].isNaN) {
      int v;
      double w;
      String t;
      if (price <= bb.lower[i]) {
        v = 1; w = 6; t = 'عند الحد السفلي';
      } else if (price >= bb.upper[i]) {
        v = -1; w = 6; t = 'عند الحد العلوي';
      } else {
        v = price > bb.mid[i] ? 1 : -1; w = 2;
        t = price > bb.mid[i] ? 'فوق المنتصف' : 'تحت المنتصف';
      }
      add('Bollinger', t, v, w);
    }
    if (!ad.plus[i].isNaN) {
      add('ADX/DI', 'ADX ${adxNow.toStringAsFixed(0)} • ${adxNow > 25 ? 'اتجاه قوي' : 'اتجاه ضعيف'}',
          ad.plus[i] > ad.minus[i] ? 1 : -1, adxNow > 25 ? 8 : 3);
    }
    if (!cf.lean && !cc[i].isNaN) {
      int v;
      double w;
      if (cc[i] < -100) {
        v = 1; w = 4;
      } else if (cc[i] > 100) {
        v = -1; w = 4;
      } else {
        v = cc[i] > 0 ? 1 : -1; w = 2;
      }
      add('CCI 20', cc[i].toStringAsFixed(0), v, w);
    }
    if (!cf.lean && !wr[i].isNaN) {
      add('Williams %R', wr[i].toStringAsFixed(0),
          wr[i] < -80 ? 1 : (wr[i] > -20 ? -1 : 0), 3);
    }

    // Supertrend
    if (sup.dir[i] != 0) {
      add('Supertrend', sup.dir[i] == 1 ? 'صاعد' : 'هابط', sup.dir[i], 8);
    }
    // Ichimoku
    if (!cf.lean) {
      final ich = ichimokuVote(c);
      add('Ichimoku', ich.$2, ich.$1, 8);
    }

    // Chandelier Exit (video 1 / image 2)
    if (!ce.longStop[i].isNaN || !ce.shortStop[i].isNaN) {
      var recent = 0;
      for (var k = math.max(0, i - 2); k <= i; k++) {
        if (ce.sig[k] != 0) recent = ce.sig[k];
      }
      final dirNow = ce.dir[i];
      final flipped = recent == dirNow;
      add('Chandelier Exit',
          '${dirNow == 1 ? 'شراء' : 'بيع'}${flipped ? ' (إشارة جديدة)' : ''}',
          dirNow, flipped ? 20 : 12);
    }

    // SR Breaks & Retests (video 1)
    SrEvent? lastSr;
    for (final e in sr.events) {
      if (e.i >= n - 4) lastSr = e;
    }
    if (cf.prune) {
      // SR Breaks tested negative → skipped in pruned mode
    } else if (lastSr != null) {
      add('SR Breaks',
          lastSr.retest
              ? 'إعادة اختبار ${lastSr.bias > 0 ? 'دعم' : 'مقاومة'}'
              : 'كسر ${lastSr.bias > 0 ? 'مقاومة' : 'دعم'}',
          lastSr.bias, lastSr.retest ? 14 : 12, event: true);
    } else {
      add('SR Breaks', 'لا حدث', 0, 12, event: true);
    }

    // Order Blocks (Flux Charts)
    int obVote = 0;
    for (final z in obs) {
      final inside = price <= z.top + a * 0.1 && price >= z.bottom - a * 0.2;
      if (inside) obVote = z.bias;
    }
    add('Order Block',
        obVote == 0 ? 'خارج المناطق' : (obVote > 0 ? 'داخل OB صاعد' : 'داخل OB هابط'),
        obVote, 14, event: true);

    // Fair Value Gap
    int fvgVote = 0;
    for (final z in fvg) {
      if (price <= z.top && price >= z.bottom) fvgVote = z.bias;
    }
    add('FVG',
        fvgVote == 0 ? 'لا فجوة نشطة' : (fvgVote > 0 ? 'داخل FVG صاعد' : 'داخل FVG هابط'),
        fvgVote, 8, event: true);

    // Liquidity Sweep Hunter / ICT Turtle Soup
    if (sw.isNotEmpty) {
      final e = sw.last;
      add('Liquidity Sweep', e.name, e.bias, 14, event: true);
    } else {
      add('Liquidity Sweep', 'لا سحب سيولة', 0, 14, event: true);
    }

    // Premium / Discount (Dynamic 50%)
    if (!cf.prune) {
      add('Premium/Discount', price < eqLvl ? 'منطقة خصم (Discount)' : 'منطقة علاوة (Premium)',
          price < eqLvl ? 1 : -1, 5);
    }

    // Fibonacci (auto swing, OTE zone)
    if (fibRes != null) {
      final fv = fibVote(price, fibRes);
      add('Fibonacci', fv.$2, fv.$1, 8, event: true);
    }

    // VWAP + daily open
    if (!vwapLast.isNaN) {
      add('VWAP', price > vwapLast ? 'فوق VWAP' : 'تحت VWAP',
          price > vwapLast ? 1 : -1, 6);
    }
    if (!day.dayOpen.isNaN) {
      add('Daily Open', price > day.dayOpen ? 'فوق افتتاح اليوم' : 'تحت افتتاح اليوم',
          price > day.dayOpen ? 1 : -1, 4);
    }

    // Volume profile
    if (!cf.prune && vp != null) {
      add('Volume Profile', price > vp.poc ? 'فوق POC' : 'تحت POC',
          price > vp.poc ? 1 : -1, 3);
    }

    // Higher timeframe
    final ht = htfTrend(htf);
    if (htf != null) {
      add('الإطار الأعلى', ht == 1 ? 'صاعد' : ht == -1 ? 'هابط' : 'محايد', ht, 14);
    }

    // Candlestick patterns
    final pats = detectPatterns(c);
    if (pats.isNotEmpty) {
      var ps = 0.0;
      for (final p in pats) {
        ps += p.bias * p.weight;
      }
      ps = ps.clamp(-2.5, 2.5).toDouble();
      sum += ps * 8;
      maxW += 20;
    }

    // Session / killzone (info + quality filter for FX & metals)
    votes.add(IndicatorVote('الجلسة (Killzone)', kz.name, 0));

    var score = maxW == 0 ? 0.0 : sum / maxW * 100;
    if (htf != null && ht != 0 && ((score > 0 && ht < 0) || (score < 0 && ht > 0))) {
      score *= 0.8;
    }
    if (sym.isFx) {
      if (kz.prime) score *= 1.12;
      if (kz.avoid) score *= 0.85;
    }
    score = score.clamp(-100, 100).toDouble();

    var want = score >= cf.minScore ? 1 : (score <= -cf.minScore ? -1 : 0);
    var aligned = 0;
    if (want != 0) {
      aligned = votes.where((v) => _core.contains(v.name) && v.vote == want).length;
      if (aligned < cf.minAligned) want = 0;
    }
    // optional hard filter: only trade with the higher-timeframe trend
    if (want != 0 && cf.htfGate && ht != want) want = 0;
    final dir = want == 1
        ? Direction.buy
        : want == -1
            ? Direction.sell
            : Direction.neutral;
    final grade = (aligned >= 8 && (htf == null || ht == want))
        ? 'A'
        : aligned >= 6
            ? 'B'
            : 'C';

    // ── Levels (QNA-style: Entry / SL / TP1-2-3 as 1R-2R-3R)
    double entry = price, sl = 0, t1 = 0, t2 = 0, t3 = 0;
    if (dir != Direction.neutral) {
      final buy = dir == Direction.buy;
      final cands = <double>[];
      for (final z in obs) {
        if (z.bias == (buy ? 1 : -1) &&
            price >= z.bottom - a * 0.3 &&
            price <= z.top + a * 0.3) {
          cands.add(buy ? z.bottom : z.top);
        }
      }
      for (final e in sw) {
        if (e.bias == (buy ? 1 : -1)) cands.add(e.extreme);
      }
      final ceStop = buy ? ce.longStop[i] : ce.shortStop[i];
      if (!ceStop.isNaN) cands.add(ceStop);
      final swp = _nearestSwing(c, entry, buy);
      if (swp != null) cands.add(swp);
      var risk = a * s.atrMult;
      double? best;
      for (final cnd in cands) {
        final rk = (buy ? entry - cnd : cnd - entry) + a * 0.1;
        if (rk >= a * 0.8 && rk <= a * 3 && (best == null || rk < best)) best = rk;
      }
      if (best != null) risk = best;
      final sgn = buy ? 1 : -1;
      sl = entry - sgn * risk;
      t1 = entry + sgn * risk * s.rr1;
      t2 = entry + sgn * risk * s.rr2;
      t3 = entry + sgn * risk * s.rr3;
    }

    // ── Reasons
    final reasons = <String>[];
    if (want != 0) {
      for (final v in votes) {
        if (v.vote == want && _core.contains(v.name)) reasons.add('${v.name}: ${v.value}');
      }
      for (final p in pats) {
        if (p.bias == want) reasons.add('شمعة: ${p.ar}');
      }
      if (htf != null && ht != 0 && ht != want) {
        reasons.add('تنبيه: الإطار الأعلى عكس الإشارة');
      }
      if (sym.isFx && kz.avoid) reasons.add('تنبيه: ${kz.name} — سيولة ضعيفة');
    } else {
      reasons.add('التوافق بين المؤشرات غير كافٍ — الأفضل الانتظار');
    }

    // ── Chart overlays
    final zones = <Zone>[...obs, ...fvg, ...eq];
    if (sr.res != null && sr.resI >= 0) {
      zones.add(Zone('SR', -1, sr.res! + 0.08 * a, sr.res! - 0.08 * a, c[sr.resI].ts, 'R'));
    }
    if (sr.sup != null && sr.supI >= 0) {
      zones.add(Zone('SR', 1, sr.sup! + 0.08 * a, sr.sup! - 0.08 * a, c[sr.supI].ts, 'S'));
    }
    final marks = <ChartMark>[];
    for (var k = math.max(1, n - 150); k < n; k++) {
      if (ce.sig[k] != 0) {
        marks.add(ChartMark(c[k].ts, ce.sig[k], ce.sig[k] > 0 ? 'Buy' : 'Sell'));
      }
    }
    for (final e in sr.events) {
      if (e.i >= n - 150) marks.add(ChartMark(c[e.i].ts, e.bias, e.retest ? 'RT' : 'BRK'));
    }
    for (final e in sw) {
      marks.add(ChartMark(c[e.i].ts, e.bias, 'SWEEP'));
    }
    marks.sort((x, y) => x.ts.compareTo(y.ts));
    final marksOut = marks.length > 30 ? marks.sublist(marks.length - 30) : marks;

    final ceL = List<double>.filled(n, double.nan);
    final ceS = List<double>.filled(n, double.nan);
    for (var k = 0; k < n; k++) {
      if (ce.longStop[k].isNaN) continue;
      if (ce.dir[k] == 1) {
        ceL[k] = ce.longStop[k];
      } else {
        ceS[k] = ce.shortStop[k];
      }
    }

    return TradeSignal(
      direction: dir, score: score, price: price, entry: entry, stopLoss: sl,
      tp1: t1, tp2: t2, tp3: t3, atr: a, votes: votes, patterns: pats,
      reasons: reasons, htfTrend: ht, time: now, grade: grade,
      aligned: aligned, killzone: kz.name, zones: zones, marks: marksOut,
      ceLong: ceL, ceShort: ceS, equilibrium: eqLvl,
      poc: vp?.poc ?? double.nan,
      vah: vp?.vah ?? double.nan,
      val: vp?.val ?? double.nan,
      fibs: fibRes?.levels ?? const [],
      fibUp: fibRes?.upLeg ?? true,
      vpBins: vp?.bins ?? const [],
      vwap: vw,
      keyLevels: kl,
    );
  }
}
