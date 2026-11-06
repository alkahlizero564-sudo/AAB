import 'dart:math' as math;
import '../models.dart';
import '../services/settings_service.dart';
import 'indicators.dart';
import 'patterns.dart';

class SignalEngine {
  static const _minCandles = 60;

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
      {List<Candle>? htf, required AppSettings s}) {
    final now = DateTime.now();
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

    final e20 = ema(cl, 20), e50 = ema(cl, 50), e200 = ema(cl, 200);
    final r = rsi(cl, 14);
    final m = macd(cl);
    final bb = bollinger(cl);
    final at = atr(c, 14);
    final st = stoch(c);
    final ad = adxCalc(c);
    final cc = cci(c);
    final wr = williamsR(c);

    final votes = <IndicatorVote>[];
    double sum = 0, maxW = 0;
    void add(String name, String val, int vote, double w) {
      votes.add(IndicatorVote(name, val, vote));
      sum += vote * w;
      maxW += w;
    }

    final adxNow = ad.adx[i].isNaN ? 0.0 : ad.adx[i];

    // 1) EMA 20/50 alignment
    if (!e20[i].isNaN && !e50[i].isNaN) {
      final v = (price > e20[i] && e20[i] > e50[i])
          ? 1
          : (price < e20[i] && e20[i] < e50[i])
              ? -1
              : 0;
      add('EMA 20/50', v == 1 ? 'صاعد' : v == -1 ? 'هابط' : 'متذبذب', v, 14);
    }
    // 2) EMA 200
    if (!e200[i].isNaN) {
      final v = price > e200[i] ? 1 : -1;
      add('EMA 200', price > e200[i] ? 'فوق المتوسط' : 'تحت المتوسط', v, 8);
    }
    // 3) MACD
    if (!m.hist[i].isNaN && !m.hist[i - 1].isNaN) {
      final h = m.hist[i];
      final v = h > 0 ? 1 : -1;
      var w = 12.0;
      var crossed = false;
      for (var k = 1; k <= 3; k++) {
        final prev = m.hist[i - k];
        if (!prev.isNaN && ((h > 0 && prev <= 0) || (h < 0 && prev >= 0))) {
          crossed = true;
        }
      }
      if (crossed) w += 5;
      add('MACD', '${h > 0 ? 'إيجابي' : 'سلبي'}${crossed ? ' (تقاطع)' : ''}', v, w);
    }
    // 4) RSI
    if (!r[i].isNaN) {
      int v;
      double w;
      String t;
      if (r[i] < 30) {
        v = 1; w = 10; t = 'تشبع بيعي';
      } else if (r[i] > 70) {
        v = -1; w = 10; t = 'تشبع شرائي';
      } else {
        v = r[i] > 50 ? 1 : -1; w = 5; t = r[i] > 50 ? 'زخم صاعد' : 'زخم هابط';
      }
      add('RSI 14', '${r[i].toStringAsFixed(1)} • $t', v, w);
    }
    // 5) Stochastic
    if (!st.k[i].isNaN && !st.d[i].isNaN) {
      final k = st.k[i], d = st.d[i];
      int v;
      double w;
      if (k < 20 && k > d) {
        v = 1; w = 8;
      } else if (k > 80 && k < d) {
        v = -1; w = 8;
      } else {
        v = k > d ? 1 : -1; w = 3;
      }
      add('Stochastic', 'K ${k.toStringAsFixed(0)} / D ${d.toStringAsFixed(0)}', v, w);
    }
    // 6) Bollinger
    if (!bb.mid[i].isNaN) {
      int v;
      double w;
      String t;
      if (price <= bb.lower[i]) {
        v = 1; w = 7; t = 'عند الحد السفلي';
      } else if (price >= bb.upper[i]) {
        v = -1; w = 7; t = 'عند الحد العلوي';
      } else {
        v = price > bb.mid[i] ? 1 : -1; w = 2;
        t = price > bb.mid[i] ? 'فوق المنتصف' : 'تحت المنتصف';
      }
      add('Bollinger', t, v, w);
    }
    // 7) ADX / DI
    if (!ad.plus[i].isNaN) {
      final v = ad.plus[i] > ad.minus[i] ? 1 : -1;
      add('ADX/DI', 'ADX ${adxNow.toStringAsFixed(0)} • ${adxNow > 25 ? 'اتجاه قوي' : 'اتجاه ضعيف'}',
          v, adxNow > 25 ? 10 : 4);
    }
    // 8) CCI
    if (!cc[i].isNaN) {
      int v;
      double w;
      if (cc[i] < -100) {
        v = 1; w = 5;
      } else if (cc[i] > 100) {
        v = -1; w = 5;
      } else {
        v = cc[i] > 0 ? 1 : -1; w = 2;
      }
      add('CCI 20', cc[i].toStringAsFixed(0), v, w);
    }
    // 9) Williams %R
    if (!wr[i].isNaN) {
      final v = wr[i] < -80 ? 1 : (wr[i] > -20 ? -1 : 0);
      add('Williams %R', wr[i].toStringAsFixed(0), v, 4);
    }
    // 10) Higher timeframe
    final ht = htfTrend(htf);
    if (htf != null) {
      add('الإطار الأعلى', ht == 1 ? 'صاعد' : ht == -1 ? 'هابط' : 'محايد', ht, 15);
    }
    // 11) Candlestick patterns
    final pats = detectPatterns(c);
    var ps = 0.0;
    for (final p in pats) {
      ps += p.bias * p.weight;
    }
    ps = ps.clamp(-2.5, 2.5).toDouble();
    sum += ps * 8;
    maxW += 20;

    final score = maxW == 0 ? 0.0 : (sum / maxW * 100).clamp(-100, 100).toDouble();
    var dir = Direction.neutral;
    if (score >= 30) dir = Direction.buy;
    if (score <= -30) dir = Direction.sell;

    // Levels
    final a = at[i].isNaN ? (c.last.high - c.last.low) : at[i];
    double entry = price, sl = 0, t1 = 0, t2 = 0;
    if (dir != Direction.neutral) {
      final buy = dir == Direction.buy;
      var risk = a * s.atrMult;
      final sw = _nearestSwing(c, entry, buy);
      if (sw != null) {
        final dist = (entry - sw).abs();
        if (dist >= a && dist <= a * 3) risk = dist + a * 0.25;
      }
      sl = buy ? entry - risk : entry + risk;
      t1 = buy ? entry + risk * s.rr1 : entry - risk * s.rr1;
      t2 = buy ? entry + risk * s.rr2 : entry - risk * s.rr2;
    }

    // Reasons
    final want = dir == Direction.buy ? 1 : (dir == Direction.sell ? -1 : 0);
    final reasons = <String>[];
    if (want != 0) {
      for (final v in votes) {
        if (v.vote == want) reasons.add('${v.name}: ${v.value}');
      }
      for (final p in pats) {
        if (p.bias == want) reasons.add('شمعة: ${p.ar}');
      }
      if (htf != null && ht != 0 && ht != want) {
        reasons.add('تنبيه: الإطار الأعلى عكس الإشارة');
      }
    } else {
      reasons.add('المؤشرات متضاربة — لا توجد أفضلية واضحة، الأفضل الانتظار');
    }

    return TradeSignal(
      direction: dir, score: score, price: price, entry: entry, stopLoss: sl,
      tp1: t1, tp2: t2, atr: a, votes: votes, patterns: pats,
      reasons: reasons, htfTrend: ht, time: now,
    );
  }
}
