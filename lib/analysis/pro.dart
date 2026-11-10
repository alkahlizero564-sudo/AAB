import 'dart:math' as math;
import '../models.dart';
import '../services/settings_service.dart';
import 'flow.dart';
import 'indicators.dart';
import 'smc.dart';
import 'ut_bot.dart';

// ───────────────────────── Market structure ─────────────────────────
class Structure {
  final int trend; // +1 HH/HL, -1 LH/LL, 0 range
  final double? swingHigh, swingLow;
  final int breakDir; // last structural break (+1 / -1 / 0)
  final bool choch; // break against the previous trend
  final String label;
  const Structure(this.trend, this.swingHigh, this.swingLow, this.breakDir,
      this.choch, this.label);
}

Structure marketStructure(List<Candle> c, {int len = 3}) {
  final ph = pivotHighs(c, len, len), pl = pivotLows(c, len, len);
  if (ph.length < 2 || pl.length < 2) {
    return const Structure(0, null, null, 0, false, 'غير محدد');
  }
  final h1 = ph[ph.length - 1], h0 = ph[ph.length - 2];
  final l1 = pl[pl.length - 1], l0 = pl[pl.length - 2];
  var trend = 0;
  if (h1.p > h0.p && l1.p > l0.p) trend = 1;
  if (h1.p < h0.p && l1.p < l0.p) trend = -1;
  var label = trend == 1
      ? 'صاعد (قمم وقيعان أعلى)'
      : trend == -1
          ? 'هابط (قمم وقيعان أدنى)'
          : 'عرضي / انتقالي';
  final last = c.last.close;
  final recent = c.sublist(math.max(0, c.length - 3)).map((e) => e.close).toList();
  final brokeUp = recent.any((x) => x > h1.p);
  final brokeDn = recent.any((x) => x < l1.p);
  var brk = 0;
  var choch = false;
  if (brokeUp && last > l1.p) {
    brk = 1;
    if (trend == -1) {
      choch = true;
      label = 'CHoCH صاعد (تغيّر هيكل)';
    } else {
      label = '$label • BOS صاعد';
    }
  } else if (brokeDn && last < h1.p) {
    brk = -1;
    if (trend == 1) {
      choch = true;
      label = 'CHoCH هابط (تغيّر هيكل)';
    } else {
      label = '$label • BOS هابط';
    }
  }
  return Structure(trend, h1.p, l1.p, brk, choch, label);
}

// ───────────────────────── Chart patterns ─────────────────────────
class ChartPat {
  final String name;
  final int bias;
  final bool fresh;
  const ChartPat(this.name, this.bias, this.fresh);
}

/// Double top/bottom, (inverse) head & shoulders, triangles, wedges and
/// ranges — all confirmed by a close beyond the neckline / trendline.
List<ChartPat> chartPatterns(List<Candle> c, double a) {
  final out = <ChartPat>[];
  final n = c.length;
  if (n < 60 || a <= 0) return out;
  final start = math.max(0, n - 150);
  final ph = pivotHighs(c, 4, 4).where((p) => p.i >= start).toList();
  final pl = pivotLows(c, 4, 4).where((p) => p.i >= start).toList();

  double troughBetween(int i0, int i1) {
    var m = double.infinity;
    for (var j = i0; j <= i1; j++) {
      m = math.min(m, c[j].low);
    }
    return m;
  }

  double peakBetween(int i0, int i1) {
    var m = -double.infinity;
    for (var j = i0; j <= i1; j++) {
      m = math.max(m, c[j].high);
    }
    return m;
  }

  bool brokeDown(int idx, double level) {
    for (var j = math.max(idx + 1, n - 10); j < n; j++) {
      if (c[j].close < level) return true;
    }
    return false;
  }

  bool brokeUp(int idx, double level) {
    for (var j = math.max(idx + 1, n - 10); j < n; j++) {
      if (c[j].close > level) return true;
    }
    return false;
  }

  if (ph.length >= 2) {
    final b = ph[ph.length - 1], aa = ph[ph.length - 2];
    final gap = b.i - aa.i;
    if (gap >= 5 && gap <= 70 && (b.p - aa.p).abs() <= 0.5 * a) {
      final neck = troughBetween(aa.i, b.i);
      if ((aa.p + b.p) / 2 - neck >= 2 * a && brokeDown(b.i, neck)) {
        out.add(const ChartPat('قمة مزدوجة', -1, true));
      }
    }
  }
  if (pl.length >= 2) {
    final b = pl[pl.length - 1], aa = pl[pl.length - 2];
    final gap = b.i - aa.i;
    if (gap >= 5 && gap <= 70 && (b.p - aa.p).abs() <= 0.5 * a) {
      final neck = peakBetween(aa.i, b.i);
      if (neck - (aa.p + b.p) / 2 >= 2 * a && brokeUp(b.i, neck)) {
        out.add(const ChartPat('قاع مزدوج', 1, true));
      }
    }
  }
  if (ph.length >= 3) {
    final r = ph[ph.length - 1], h = ph[ph.length - 2], l = ph[ph.length - 3];
    if (h.p - l.p >= 0.5 * a &&
        h.p - r.p >= 0.5 * a &&
        (l.p - r.p).abs() <= 0.8 * a &&
        r.i - l.i <= 120) {
      final t1 = troughBetween(l.i, h.i), t2 = troughBetween(h.i, r.i);
      if ((t1 - t2).abs() <= a && brokeDown(r.i, (t1 + t2) / 2)) {
        out.add(const ChartPat('رأس وكتفين', -1, true));
      }
    }
  }
  if (pl.length >= 3) {
    final r = pl[pl.length - 1], h = pl[pl.length - 2], l = pl[pl.length - 3];
    if (l.p - h.p >= 0.5 * a &&
        r.p - h.p >= 0.5 * a &&
        (l.p - r.p).abs() <= 0.8 * a &&
        r.i - l.i <= 120) {
      final t1 = peakBetween(l.i, h.i), t2 = peakBetween(h.i, r.i);
      if ((t1 - t2).abs() <= a && brokeUp(r.i, (t1 + t2) / 2)) {
        out.add(const ChartPat('رأس وكتفين مقلوب', 1, true));
      }
    }
  }

  // ---- Triangles / wedges / rectangle: breakout confirmed by a close ----
  if (ph.length >= 2 && pl.length >= 2) {
    final h2 = ph[ph.length - 1], h1 = ph[ph.length - 2];
    final l2 = pl[pl.length - 1], l1 = pl[pl.length - 2];
    final i0 = math.min(h1.i, l1.i);
    final span = math.max(h2.i, l2.i) - i0;
    if (h2.i != h1.i && l2.i != l1.i && span >= 15 && span <= 120) {
      final hs = (h2.p - h1.p) / (h2.i - h1.i); // upper line slope per candle
      final ls = (l2.p - l1.p) / (l2.i - l1.i); // lower line slope per candle
      double upper(int k) => h2.p + hs * (k - h2.i);
      double lower(int k) => l2.p + ls * (k - l2.i);
      final w0 = upper(i0) - lower(i0);
      final w1 = upper(n - 1) - lower(n - 1);
      if (w0 >= 1.5 * a) {
        final hm = hs * span, lm = ls * span;
        final flatH = hm.abs() <= 0.6 * a, flatL = lm.abs() <= 0.6 * a;
        final upH = hm > 0.6 * a, downH = hm < -0.6 * a;
        final upL = lm > 0.6 * a, downL = lm < -0.6 * a;
        final conv = w1 > 0 && w1 < w0 * 0.85; // الخطوط تضيق ولم تلتقِ بعد
        final upBreak = c[n - 1].close > upper(n - 1) + 0.1 * a &&
            c[n - 4].close <= upper(n - 4);
        final dnBreak = c[n - 1].close < lower(n - 1) - 0.1 * a &&
            c[n - 4].close >= lower(n - 4);
        if (flatH && upL && conv) {
          if (upBreak) out.add(const ChartPat('مثلث صاعد', 1, true));
        } else if (flatL && downH && conv) {
          if (dnBreak) out.add(const ChartPat('مثلث هابط', -1, true));
        } else if (downH && upL && conv) {
          if (upBreak) out.add(const ChartPat('مثلث متماثل (كسر لأعلى)', 1, true));
          if (dnBreak) out.add(const ChartPat('مثلث متماثل (كسر لأسفل)', -1, true));
        } else if (upH && upL && conv) {
          if (dnBreak) out.add(const ChartPat('وتد صاعد', -1, true));
        } else if (downH && downL && conv) {
          if (upBreak) out.add(const ChartPat('وتد هابط', 1, true));
        } else if (flatH && flatL) {
          if (upBreak) out.add(const ChartPat('نطاق عرضي (كسر لأعلى)', 1, true));
          if (dnBreak) out.add(const ChartPat('نطاق عرضي (كسر لأسفل)', -1, true));
        }
      }
    }
  }
  return out;
}

// ───────────────────────── Volatility / round numbers ─────────────────────────
/// 'quiet' (bottom 20% of the last 100 ATR values), 'hot' (top 10%) or 'normal'.
String volRegime(List<double> at) {
  final v = <double>[];
  for (var i = math.max(0, at.length - 100); i < at.length; i++) {
    if (!at[i].isNaN) v.add(at[i]);
  }
  if (v.length < 30) return 'normal';
  final cur = v.last;
  final below = v.where((x) => x < cur).length / v.length;
  if (below < 0.2) return 'quiet';
  if (below > 0.9) return 'hot';
  return 'normal';
}

/// Nearest round numbers around [price]: (below, above).
(double, double) roundBand(MarketSymbol sym, double price) {
  double step;
  if (sym.category == 'metal') {
    step = sym.code.startsWith('XAG') ? 0.5 : 10;
  } else if (sym.category == 'crypto') {
    step = price > 20000
        ? 1000
        : price > 2000
            ? 100
            : price > 100
                ? 10
                : price > 1
                    ? 0.5
                    : 0.05;
  } else if (sym.category == 'stock') {
    step = price < 50 ? 5 : (price < 500 ? 10 : 50);
  } else {
    step = price >= 50 ? 1.0 : (price >= 10 ? 0.5 : 0.01);
  }
  final below = (price / step).floorToDouble() * step;
  return (below, below + step);
}

// ───────────────────────── Location confluence (price action only) ─────────────────────────
class LocFactor {
  final String name;
  final int w;
  const LocFactor(this.name, this.w);
}

List<LocFactor> locationFactors({
  required bool buy,
  required double price,
  required double a,
  required List<Zone> zones,
  required List<KeyLevel> kl,
  required List<FibLevel> fibs,
  required bool fibUp,
  required Structure st,
  required MarketSymbol sym,
}) {
  final f = <LocFactor>[];
  final seen = <String>{};
  void add(String name, int w) {
    if (seen.add(name)) f.add(LocFactor(name, w));
  }

  final tol = 0.35 * a;
  final want = buy ? 1 : -1;
  for (final z in zones) {
    final inside = price <= z.top + 0.2 * a && price >= z.bottom - 0.2 * a;
    if (!inside || z.bias != want) continue;
    if (z.kind == 'OB') add('Order Block', 2);
    if (z.kind == 'FVG') add('FVG', 1);
    if (z.kind == 'SR') add('دعم/مقاومة', 1);
  }
  // مستويات اليوم والجلسة فقط (قمم وقيعان سابقة) — بدون VWAP وVolume Profile
  for (final k in kl) {
    if ((price - k.price).abs() > tol) continue;
    final ok = buy ? (k.side <= 0 && price >= k.price - tol) : (k.side >= 0 && price <= k.price + tol);
    if (!ok) continue;
    if (k.kind == 'day' || k.kind == 'session') {
      add('مستوى يومي/جلسة', k.side != 0 ? 2 : 1);
    }
  }
  double? p50, p786;
  for (final x in fibs) {
    if (x.ratio == 0.5) p50 = x.price;
    if (x.ratio == 0.786) p786 = x.price;
  }
  if (p50 != null && p786 != null && fibUp == buy) {
    final lo = math.min(p50, p786) - tol, hi = math.max(p50, p786) + tol;
    if (price >= lo && price <= hi) add('Fibonacci OTE', 2);
  }
  final rb = roundBand(sym, price);
  if (buy ? (price >= rb.$1 - tol && price - rb.$1 <= tol) : (price <= rb.$2 + tol && rb.$2 - price <= tol)) {
    add('رقم نفسي', 1);
  }
  if (buy && st.swingLow != null && (price - st.swingLow!).abs() <= tol) {
    add('قاع هيكلي', 1);
  }
  if (!buy && st.swingHigh != null && (price - st.swingHigh!).abs() <= tol) {
    add('قمة هيكلية', 1);
  }
  return f;
}

String? findTrigger({
  required bool buy,
  required List<Candle> c,
  required TradeSignal base,
  required Structure st,
  required List<ChartPat> cp,
  required double a,
}) {
  final want = buy ? 1 : -1;
  for (final v in base.votes) {
    if (v.name == 'Liquidity Sweep' && v.vote == want) {
      return 'سحب سيولة وإغلاق عكسي (${v.value})';
    }
  }
  for (final p in base.patterns) {
    if (p.bias == want && p.weight >= 0.8) return 'شمعة: ${p.ar}';
  }
  final k = c.last;
  final rng = k.high - k.low;
  if (rng > 0.5 * a) {
    final lw = math.min(k.open, k.close) - k.low;
    final uw = k.high - math.max(k.open, k.close);
    if (buy && lw >= 0.6 * rng && k.close >= k.open) return 'شمعة رفض سفلي (Pin Bar)';
    if (!buy && uw >= 0.6 * rng && k.close <= k.open) return 'شمعة رفض علوي (Pin Bar)';
  }
  if (st.choch && st.breakDir == want) return 'CHoCH — ${st.label}';
  for (final p in cp) {
    if (p.bias == want && p.fresh) return 'نموذج: ${p.name}';
  }
  return null;
}

// ───────────────────────── The trader-style decision ─────────────────────────
/// 1) market-structure bias  2) price at a confluence zone  3) price-action
/// trigger  4) filters (volatility, session)  5) room to run to the next
/// obstacle.  Price action only: no indicator takes part in the decision;
/// RSI / MACD / MAs / UT Bot / real volume are shown as a confirmation line only.
/// [base] is the vote-engine result, used only for its overlays.
class ProEngine {
  static TradeSignal _build(TradeSignal b,
      {required Direction dir,
      required double score,
      required double entry,
      required double sl,
      required double tp1,
      required double tp2,
      required double tp3,
      required List<IndicatorVote> votes,
      required List<String> reasons,
      required String grade,
      required int aligned}) {
    return TradeSignal(
      direction: dir, score: score, price: b.price, entry: entry, stopLoss: sl,
      tp1: tp1, tp2: tp2, tp3: tp3, atr: b.atr, votes: votes, patterns: b.patterns,
      reasons: reasons, htfTrend: b.htfTrend, time: b.time, grade: grade,
      aligned: aligned, killzone: b.killzone, zones: b.zones, marks: b.marks,
      ceLong: b.ceLong, ceShort: b.ceShort, equilibrium: b.equilibrium,
      poc: b.poc, vah: b.vah, val: b.val, fibs: b.fibs, fibUp: b.fibUp,
      vpBins: b.vpBins, vwap: b.vwap, keyLevels: b.keyLevels,
    );
  }

  static TradeSignal _wait(TradeSignal b, List<IndicatorVote> votes, List<String> why) {
    return _build(b,
        dir: Direction.neutral, score: 0, entry: b.price, sl: 0, tp1: 0, tp2: 0,
        tp3: 0, votes: votes, reasons: why, grade: 'C', aligned: 0);
  }

  /// سطر تأكيد من المؤشرات: للعلم فقط، لا يدخل في قرار الدخول.
  static List<String> _confirm(List<Candle> c, bool buy) {
    final n = c.length;
    if (n < 60) return const [];
    final cl = c.map((e) => e.close).toList();
    final price = cl[n - 1];
    final want = buy ? 1 : -1;
    final items = <String>[];
    var agree = 0, total = 0;
    void chk(String name, String val, int vote) {
      total++;
      if (vote == want) agree++;
      items.add('$name $val ${vote == 0 ? '•' : (vote == want ? '✓' : '✗')}');
    }

    final r = rsi(cl, 14)[n - 1];
    if (!r.isNaN) {
      final v = r > 70 ? -1 : (r < 30 ? 1 : (r > 50 ? 1 : -1));
      final t = r > 70
          ? 'تشبع شرائي'
          : (r < 30 ? 'تشبع بيعي' : (r > 50 ? 'زخم صاعد' : 'زخم هابط'));
      chk('RSI', '${r.toStringAsFixed(0)} $t', v);
    }
    final mh = macd(cl).hist[n - 1];
    if (!mh.isNaN) chk('MACD', mh > 0 ? 'إيجابي' : 'سلبي', mh > 0 ? 1 : -1);
    final e20 = ema(cl, 20)[n - 1], e50 = ema(cl, 50)[n - 1];
    if (!e20.isNaN && !e50.isNaN) {
      final v = (price > e20 && e20 > e50) ? 1 : ((price < e20 && e20 < e50) ? -1 : 0);
      chk('EMA 20/50', v == 1 ? 'صاعد' : (v == -1 ? 'هابط' : 'متذبذب'), v);
    }
    final e200 = ema(cl, 200)[n - 1];
    if (!e200.isNaN) {
      chk('EMA 200', price > e200 ? 'فوق' : 'تحت', price > e200 ? 1 : -1);
    }
    double? sma(int p) {
      if (n < p) return null;
      var s = 0.0;
      for (var i = n - p; i < n; i++) {
        s += cl[i];
      }
      return s / p;
    }

    final s50 = sma(50), s200 = sma(200);
    if (s50 != null && s200 != null) {
      chk('SMA 50/200', s50 > s200 ? '50 فوق 200' : '50 تحت 200', s50 > s200 ? 1 : -1);
    }

    // UT Bot (وقف متحرك مبني على ATR)
    final ut = utBot(c);
    if (ut.$1 != 0) {
      final fresh = ut.$2 >= 0 && ut.$2 <= 2;
      chk('UT Bot',
          '${ut.$1 == 1 ? 'شراء' : 'بيع'}${fresh ? ' (إشارة جديدة)' : ''}', ut.$1);
    }

    // الحجم الحقيقي (العملات الرقمية من Binance فقط)
    final fl = flowOf(c);
    if (fl != null) {
      int dv(double x) => x > 0.08 ? 1 : (x < -0.08 ? -1 : 0);
      String who(double x) => x > 0.08 ? 'مشترين' : (x < -0.08 ? 'بائعين' : 'متوازن');
      chk('ضغط آخر 10 شموع (حجم حقيقي)', who(fl.delta10), dv(fl.delta10));
      chk('ضغط آخر 30 شمعة', who(fl.delta30), dv(fl.delta30));
      if (fl.volRatio >= 1.8) {
        chk('حجم الشمعة الأخيرة', '${fl.volRatio.toStringAsFixed(1)}× المتوسط',
            dv(fl.lastDelta));
      }
    }

    if (total == 0) return const [];
    return [
      'تأكيد المؤشرات (للعلم فقط — لا يغيّر القرار): $agree من $total تتفق مع ${buy ? 'الشراء' : 'البيع'}',
      items.join(' • '),
    ];
  }

  /// سيناريو معلّق: أقرب منطقة OB/FVG في اتجاه الاتجاه العام، قبل وصول السعر لها.
  static List<String> _pendingScenario({
    required bool buy,
    required double price,
    required double a,
    required List<Zone> zones,
    required AppSettings s,
    required MarketSymbol sym,
  }) {
    final want = buy ? 1 : -1;
    Zone? best;
    var bestDist = double.infinity;
    for (final z in zones) {
      if (z.bias != want) continue;
      if (z.kind != 'OB' && z.kind != 'FVG') continue;
      final ahead = buy ? z.top < price : z.bottom > price;
      if (!ahead) continue;
      final dist = buy ? price - z.top : z.bottom - price;
      if (dist > 5 * a) continue;
      if (dist < bestDist) {
        bestDist = dist;
        best = z;
      }
    }
    final b = best;
    if (b == null) return const [];
    final sg = buy ? 1 : -1;
    final entry = buy ? b.top : b.bottom;
    var sl = buy ? b.bottom - 0.1 * a : b.top + 0.1 * a;
    var risk = (entry - sl).abs();
    if (risk < 0.8 * a) {
      risk = 0.8 * a;
      sl = entry - sg * risk;
    }
    if (risk > 3 * a) return const [];
    final t1 = entry + sg * risk * s.rr1;
    final t2 = entry + sg * risk * s.rr2;
    final side = buy ? 'شراء' : 'بيع';
    return [
      'سيناريو معلّق ($side): انتظر وصول السعر لمنطقة ${b.kind} بين ${sym.fmt(b.bottom)} و ${sym.fmt(b.top)}',
      'الدخول المقترح: ${sym.fmt(entry)} • الوقف: ${sym.fmt(sl)} • الهدف 1: ${sym.fmt(t1)} • الهدف 2: ${sym.fmt(t2)}',
      'لا تدخل إلا بعد ظهور شمعة تأكيد عند المنطقة.',
    ];
  }

  static TradeSignal decide(TradeSignal base, List<Candle> c, List<Candle>? htf,
      AppSettings s, MarketSymbol sym, EngineConfig cf) {
    final n = c.length;
    if (n < 60 || base.votes.isEmpty) return base;
    final price = base.price, a = base.atr;
    final at = atr(c, 14);
    final st = marketStructure(c);
    final hs = (htf != null && htf.length >= 40) ? marketStructure(htf) : null;

    // الاتجاه من هيكل السوق فقط (قمم وقيعان)
    var bias = 0;
    var biasTxt = 'غير واضح';
    if (hs != null && !hs.choch && hs.trend != 0) {
      bias = hs.trend;
      biasTxt = 'هيكل الإطار الأعلى: ${hs.label}';
    } else if (hs == null && st.trend != 0 && !st.choch) {
      bias = st.trend;
      biasTxt = 'هيكل الإطار الحالي: ${st.label}';
    }
    final kz = killzone(c.last.time);
    final regime = volRegime(at);
    final regimeAr = regime == 'quiet' ? 'هادئ' : (regime == 'hot' ? 'عالي' : 'طبيعي');
    final votes = <IndicatorVote>[
      IndicatorVote('اتجاه الإطار الأعلى', biasTxt, bias),
      IndicatorVote('هيكل السوق', st.label, st.trend),
      IndicatorVote('التقلب', regimeAr, 0),
      IndicatorVote('الجلسة (Killzone)', kz.name, 0),
    ];
    final steps = <String>['1) الاتجاه: $biasTxt'];

    if (bias == 0) {
      return _wait(base, votes, [...steps, 'لا اتجاه واضح في هيكل السوق — لا صفقة.']);
    }
    final conf = _confirm(c, bias > 0);
    if (regime == 'quiet') {
      return _wait(base, votes,
          [...steps, 'السوق هادئ جداً (تقلب منخفض) — الحركة ضعيفة، انتظر.', ...conf]);
    }
    if (cf.sessionOnly && sym.isFx && !kz.prime) {
      return _wait(base, votes,
          [...steps, 'خارج جلسات لندن/نيويورك (${kz.name}) — انتظر.', ...conf]);
    }

    final buy = bias > 0;
    final want = bias;
    final loc = locationFactors(
        buy: buy, price: price, a: a, zones: base.zones, kl: base.keyLevels,
        fibs: base.fibs, fibUp: base.fibUp, st: st, sym: sym);
    var locW = 0;
    for (final f in loc) {
      locW += f.w;
      votes.add(IndicatorVote('موقع: ${f.name}', 'عند المنطقة', want));
    }
    if (loc.length < cf.minLoc) {
      final scen = _pendingScenario(
          buy: buy, price: price, a: a, zones: base.zones, s: s, sym: sym);
      return _wait(base, votes, [
        ...steps,
        '2) الموقع: ${loc.isEmpty ? 'السعر ليس عند منطقة مهمة' : loc.map((f) => f.name).join(' + ')} '
            '(${loc.length} من ${cf.minLoc} مطلوب) — انتظر وصول السعر لمنطقة توافق.',
        ...scen,
        ...conf,
      ]);
    }
    steps.add('2) الموقع: ${loc.map((f) => f.name).join(' + ')} (${loc.length} عوامل)');

    final cp = chartPatterns(c, a);
    final trig = findTrigger(buy: buy, c: c, base: base, st: st, cp: cp, a: a);
    if (trig == null) {
      return _wait(base, votes, [
        ...steps,
        'لا تريغر بعد — انتظر شمعة تأكيد عند المنطقة.',
        'سيناريو معلّق (${buy ? 'شراء' : 'بيع'}): السعر عند منطقة التوافق الآن، جهّز الدخول '
            'وانتظر شمعة تأكيد (رفض أو ابتلاع أو CHoCH أو كسر نموذج). لا تدخل قبلها.',
        ...conf,
      ]);
    }
    votes.add(IndicatorVote('التريغر', trig, want));
    steps.add('3) التريغر: $trig');

    // ── stop: structural invalidation (zones, swings, last candles)
    final cands = <double>[];
    for (final z in base.zones) {
      if (z.bias == want && (z.kind == 'OB' || z.kind == 'FVG') &&
          price <= z.top + 0.2 * a && price >= z.bottom - 0.2 * a) {
        cands.add(buy ? z.bottom : z.top);
      }
    }
    if (buy && st.swingLow != null && st.swingLow! < price) cands.add(st.swingLow!);
    if (!buy && st.swingHigh != null && st.swingHigh! > price) cands.add(st.swingHigh!);
    final last3 = c.sublist(n - 3);
    cands.add(buy
        ? last3.map((e) => e.low).reduce(math.min)
        : last3.map((e) => e.high).reduce(math.max));
    var risk = a * s.atrMult;
    double? best;
    for (final cnd in cands) {
      final rk = (buy ? price - cnd : cnd - price) + a * 0.1;
      if (rk >= a * 0.8 && rk <= a * 3 && (best == null || rk < best)) best = rk;
    }
    if (best != null) risk = best;

    // ── room to run: nearest real obstacle on the way to the target
    double? obstacle;
    void consider(double p) {
      if (buy ? p > price : p < price) {
        if (obstacle == null || (buy ? p < obstacle! : p > obstacle!)) obstacle = p;
      }
    }

    for (final k in base.keyLevels) {
      if (k.kind == 'vp' || k.kind == 'vwap') continue;
      if (k.side == (buy ? 1 : -1)) consider(k.price);
    }
    for (final z in base.zones) {
      if (z.bias == -want) consider(buy ? z.bottom : z.top);
    }
    if (buy && st.swingHigh != null) consider(st.swingHigh!);
    if (!buy && st.swingLow != null) consider(st.swingLow!);
    if (obstacle != null) {
      final room = (obstacle! - price).abs() / risk;
      if (room < 1.5) {
        return _wait(base, votes, [
          ...steps,
          '5) مساحة الحركة: أقرب عائق على بعد ${room.toStringAsFixed(1)}R فقط (أقل من 1.5R) — لا صفقة.',
          ...conf,
        ]);
      }
      steps.add('5) مساحة الحركة: أقرب عائق بعد ${room.toStringAsFixed(1)}R');
    } else {
      steps.add('5) مساحة الحركة: لا عائق واضح أمام السعر');
    }
    steps.insert(3, '4) الفلاتر: ${kz.name} • التقلب $regimeAr');

    final sg = buy ? 1 : -1;

    // ── targets: never beyond the nearest obstacle
    final obs0 = obstacle;
    var capped = false;
    double cap(double t) {
      if (obs0 == null) return t;
      final lim = obs0 - sg * 0.1 * a; // نخرج قبل العائق بشوية
      final over = buy ? t > lim : t < lim;
      if (over) capped = true;
      return over ? lim : t;
    }

    final tp1 = cap(price + sg * risk * s.rr1);
    final tp2 = cap(price + sg * risk * s.rr2);
    final tp3 = cap(price + sg * risk * s.rr3);
    if (capped && obs0 != null) {
      steps.add('تنبيه: الأهداف اتقصّت عند أقرب عائق ${sym.fmt(obs0)}');
    }
    steps.addAll(conf);

    final aligned = loc.length + 1 + 1 + (st.trend == want ? 1 : 0);
    final strength = math.min(
        100.0, 35.0 + 9 * locW + (st.trend == want ? 8 : 0) + ((sym.isFx && kz.prime) ? 7 : 0));
    final grade = (locW >= 5 && st.trend == want && (!sym.isFx || kz.prime))
        ? 'A'
        : (locW >= 3 ? 'B' : 'C');
    return _build(base,
        dir: buy ? Direction.buy : Direction.sell,
        score: sg * strength,
        entry: price,
        sl: price - sg * risk,
        tp1: tp1,
        tp2: tp2,
        tp3: tp3,
        votes: votes,
        reasons: steps,
        grade: grade,
        aligned: aligned);
  }
} 
