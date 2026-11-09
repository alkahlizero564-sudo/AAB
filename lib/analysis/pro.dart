import 'dart:math' as math;
import '../models.dart';
import '../services/settings_service.dart';
import 'indicators.dart';
import 'smc.dart';

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

/// Double top/bottom and (inverse) head & shoulders, confirmed by a neckline break.
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

// ───────────────────────── Location confluence ─────────────────────────
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
  for (final k in kl) {
    if ((price - k.price).abs() > tol) continue;
    final ok = buy ? (k.side <= 0 && price >= k.price - tol) : (k.side >= 0 && price <= k.price + tol);
    if (!ok) continue;
    if (k.kind == 'day' || k.kind == 'session') {
      add('مستوى يومي/جلسة', k.side != 0 ? 2 : 1);
    } else if (k.kind == 'vp') {
      add('Volume Profile', 1);
    } else if (k.kind == 'vwap') {
      add('VWAP', 1);
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
/// 1) higher-timeframe bias  2) price at a confluence zone  3) price-action
/// trigger  4) filters (volatility, session)  5) room to run to the next
/// obstacle.  [base] is the vote-engine result, used only for its overlays.
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

    var bias = 0;
    var biasTxt = 'غير واضح';
    if (hs != null && !hs.choch && hs.trend != 0) {
      bias = hs.trend;
      biasTxt = 'هيكل الإطار الأعلى: ${hs.label}';
    } else if (base.htfTrend != 0) {
      bias = base.htfTrend;
      biasTxt = 'متوسطات الإطار الأعلى ${bias > 0 ? 'صاعدة' : 'هابطة'}';
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
      return _wait(base, votes, [...steps, 'لا اتجاه واضح على الإطار الأعلى — لا صفقة.']);
    }
    if (regime == 'quiet') {
      return _wait(base, votes, [...steps, 'السوق هادئ جداً (تقلب منخفض) — الحركة ضعيفة، انتظر.']);
    }
    if (cf.sessionOnly && sym.isFx && !kz.prime) {
      return _wait(base, votes, [...steps, 'خارج جلسات لندن/نيويورك (${kz.name}) — انتظر.']);
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
            'وانتظر شمعة تأكيد (رفض أو ابتلاع أو CHoCH). لا تدخل قبلها.',
      ]);
    }
    votes.add(IndicatorVote('التريغر', trig, want));
    steps.add('3) التريغر: $trig');

    // ── stop: structural invalidation
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
    final ceArr = buy ? base.ceLong : base.ceShort;
    if (ceArr.length == n && !ceArr[n - 1].isNaN) cands.add(ceArr[n - 1]);
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
        ]);
      }
      steps.add('5) مساحة الحركة: أقرب عائق بعد ${room.toStringAsFixed(1)}R');
    } else {
      steps.add('5) مساحة الحركة: لا عائق واضح أمام السعر');
    }
    steps.insert(3, '4) الفلاتر: ${kz.name} • التقلب $regimeAr');

    final sg = buy ? 1 : -1;
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
        tp1: price + sg * risk * s.rr1,
        tp2: price + sg * risk * s.rr2,
        tp3: price + sg * risk * s.rr3,
        votes: votes,
        reasons: steps,
        grade: grade,
        aligned: aligned);
  }
} 
