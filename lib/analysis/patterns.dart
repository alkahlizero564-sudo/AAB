import 'dart:math' as math;
import '../models.dart';

double _body(Candle x) => (x.close - x.open).abs();
double _rng(Candle x) => x.high - x.low;
double _up(Candle x) => x.high - math.max(x.open, x.close);
double _lo(Candle x) => math.min(x.open, x.close) - x.low;
bool _bull(Candle x) => x.close > x.open;
bool _bear(Candle x) => x.close < x.open;

/// Detects classic candlestick patterns ending at the last candle
/// (1, 2, 3 and 5-candle patterns).
List<PatternHit> detectPatterns(List<Candle> c) {
  final hits = <PatternHit>[];
  final n = c.length;
  if (n < 12) return hits;

  final a = c[n - 1], b = c[n - 2], d = c[n - 3];
  var avgBody = 0.0;
  for (var i = n - 10; i < n; i++) {
    avgBody += _body(c[i]);
  }
  avgBody /= 10;

  bool downBefore(int idx) => c[idx - 1].close < c[idx - 4].close;
  bool upBefore(int idx) => c[idx - 1].close > c[idx - 4].close;

  void add(String en, String ar, int bias, double w) =>
      hits.add(PatternHit(en, ar, bias, w));

  // ---- Single candle ----
  if (_rng(a) > 0) {
    final ra = _rng(a), ba = _body(a), ua = _up(a), la = _lo(a);
    if (ba <= 0.1 * ra) {
      if (la >= 0.6 * ra && ua <= 0.1 * ra) {
        add('Dragonfly Doji', 'دوجي اليعسوب', downBefore(n - 1) ? 1 : 0,
            downBefore(n - 1) ? 0.9 : 0.3);
      } else if (ua >= 0.6 * ra && la <= 0.1 * ra) {
        add('Gravestone Doji', 'دوجي شاهد القبر', upBefore(n - 1) ? -1 : 0,
            upBefore(n - 1) ? 0.9 : 0.3);
      } else if (ua >= 0.3 * ra && la >= 0.3 * ra) {
        add('Long-legged Doji', 'دوجي طويل الأرجل (تردد قوي)', 0, 0.4);
      } else {
        add('Doji', 'دوجي (تردد)', 0, 0.3);
      }
    } else if (la >= 2 * ba && ua <= 0.5 * ba) {
      if (downBefore(n - 1)) {
        add('Hammer', 'المطرقة', 1, 1.0);
      } else if (upBefore(n - 1)) {
        add('Hanging Man', 'الرجل المشنوق', -1, 0.8);
      }
    } else if (ua >= 2 * ba && la <= 0.5 * ba) {
      if (downBefore(n - 1)) {
        add('Inverted Hammer', 'المطرقة المقلوبة', 1, 0.7);
      } else if (upBefore(n - 1)) {
        add('Shooting Star', 'النجمة الهاوية', -1, 1.0);
      }
    } else if (ba >= 0.9 * ra && ba >= avgBody) {
      if (_bull(a)) add('Bullish Marubozu', 'ماروبوزو صاعدة', 1, 0.7);
      if (_bear(a)) add('Bearish Marubozu', 'ماروبوزو هابطة', -1, 0.7);
    } else if (ba <= 0.3 * ra && ua > ba && la > ba) {
      add('Spinning Top', 'القمة الدوارة', 0, 0.2);
    }
  }

  // ---- Two candles (b, a) ----
  final dn2 = downBefore(n - 2), up2 = upBefore(n - 2);

  // Harami Cross: دوجي داخل جسم شمعة كبيرة
  var haramiCross = false;
  if (_body(b) >= avgBody &&
      _rng(a) > 0 &&
      _body(a) <= 0.1 * _rng(a) &&
      math.max(a.open, a.close) < math.max(b.open, b.close) &&
      math.min(a.open, a.close) > math.min(b.open, b.close)) {
    haramiCross = true;
    if (_bear(b)) {
      add('Bullish Harami Cross', 'هارامي كروس صاعد', 1, dn2 ? 0.8 : 0.3);
    }
    if (_bull(b)) {
      add('Bearish Harami Cross', 'هارامي كروس هابط', -1, up2 ? 0.8 : 0.3);
    }
  }

  var engulfed = false;
  if (_bear(b) && _bull(a) && a.open <= b.close && a.close >= b.open &&
      _body(a) > _body(b)) {
    engulfed = true;
    add('Bullish Engulfing', 'ابتلاع صاعد', 1, dn2 ? 1.3 : 0.6);
  }
  if (_bull(b) && _bear(a) && a.open >= b.close && a.close <= b.open &&
      _body(a) > _body(b)) {
    engulfed = true;
    add('Bearish Engulfing', 'ابتلاع هابط', -1, up2 ? 1.3 : 0.6);
  }
  if (_bear(b) && _bull(a) && a.open < b.close &&
      a.close > (b.open + b.close) / 2 && a.close < b.open) {
    add('Piercing Line', 'خط الاختراق', 1, dn2 ? 1.0 : 0.5);
  }
  if (_bull(b) && _bear(a) && a.open > b.close &&
      a.close < (b.open + b.close) / 2 && a.close > b.open) {
    add('Dark Cloud Cover', 'الغطاء الأسود', -1, up2 ? 1.0 : 0.5);
  }
  if (!haramiCross && _bear(b) && _bull(a) && a.open > b.close &&
      a.close < b.open && _body(b) >= avgBody) {
    add('Bullish Harami', 'هارامي صاعد', 1, dn2 ? 0.7 : 0.3);
  }
  if (!haramiCross && _bull(b) && _bear(a) && a.open < b.close &&
      a.close > b.open && _body(b) >= avgBody) {
    add('Bearish Harami', 'هارامي هابط', -1, up2 ? 0.7 : 0.3);
  }
  final tol = 0.05 * math.max(_rng(a), _rng(b));
  if (_bear(b) && _bull(a) && (a.low - b.low).abs() <= tol && dn2) {
    add('Tweezer Bottom', 'قاع الملقط', 1, 0.8);
  }
  if (_bull(b) && _bear(a) && (a.high - b.high).abs() <= tol && up2) {
    add('Tweezer Top', 'قمة الملقط', -1, 0.8);
  }

  // Outside Bar: شمعة تغطي مدى السابقة (لا تُحسب لو في ابتلاع)
  if (!engulfed && a.high > b.high && a.low < b.low && _body(a) >= avgBody) {
    if (_bull(a)) {
      add('Bullish Outside Bar', 'شمعة خارجية صاعدة', 1, dn2 ? 0.7 : 0.4);
    }
    if (_bear(a)) {
      add('Bearish Outside Bar', 'شمعة خارجية هابطة', -1, up2 ? 0.7 : 0.4);
    }
  }
  // Inside Bar: ضغط قبل حركة (محايدة)
  if (a.high < b.high && a.low > b.low) {
    add('Inside Bar', 'شمعة داخلية (ضغط)', 0, 0.2);
  }

  // ---- Three candles (d, b, a) ----
  final dn3 = downBefore(n - 3), up3 = upBefore(n - 3);
  if (_bear(d) && _body(d) >= avgBody && _body(b) <= 0.5 * _body(d) &&
      _bull(a) && a.close > (d.open + d.close) / 2) {
    add('Morning Star', 'نجمة الصباح', 1, dn3 ? 1.5 : 0.8);
  }
  if (_bull(d) && _body(d) >= avgBody && _body(b) <= 0.5 * _body(d) &&
      _bear(a) && a.close < (d.open + d.close) / 2) {
    add('Evening Star', 'نجمة المساء', -1, up3 ? 1.5 : 0.8);
  }
  if (_bull(d) && _bull(b) && _bull(a) && b.close > d.close &&
      a.close > b.close && b.open > d.open && b.open < d.close &&
      a.open > b.open && a.open < b.close) {
    add('Three White Soldiers', 'ثلاثة جنود بيض', 1, 1.4);
  }
  if (_bear(d) && _bear(b) && _bear(a) && b.close < d.close &&
      a.close < b.close && b.open < d.open && b.open > d.close &&
      a.open < b.open && a.open > b.close) {
    add('Three Black Crows', 'ثلاثة غربان سود', -1, 1.4);
  }
  // Three Inside Up / Down: هارامي ثم شمعة تأكيد
  if (_bear(d) && _body(d) >= avgBody && _bull(b) && b.open > d.close &&
      b.close < d.open && _bull(a) && a.close > d.open) {
    add('Three Inside Up', 'ثلاثة داخل صاعد', 1, dn3 ? 1.2 : 0.6);
  }
  if (_bull(d) && _body(d) >= avgBody && _bear(b) && b.open < d.close &&
      b.close > d.open && _bear(a) && a.close < d.open) {
    add('Three Inside Down', 'ثلاثة داخل هابط', -1, up3 ? 1.2 : 0.6);
  }
  // Three Outside Up / Down: ابتلاع ثم شمعة تأكيد
  if (_bear(d) && _bull(b) && b.open <= d.close && b.close >= d.open &&
      _body(b) > _body(d) && _bull(a) && a.close > b.close) {
    add('Three Outside Up', 'ثلاثة خارج صاعد', 1, dn3 ? 1.3 : 0.6);
  }
  if (_bull(d) && _bear(b) && b.open >= d.close && b.close <= d.open &&
      _body(b) > _body(d) && _bear(a) && a.close < b.close) {
    add('Three Outside Down', 'ثلاثة خارج هابط', -1, up3 ? 1.3 : 0.6);
  }

  // ---- Five candles: Rising / Falling Three Methods (استمرارية) ----
  final e = c[n - 5], f = c[n - 4];
  final mids = [f, d, b];
  final up5 = upBefore(n - 5), dn5 = downBefore(n - 5);
  bool insideRange(Candle x) => x.high <= e.high && x.low >= e.low;
  bool smallBody(Candle x) => _body(x) <= 0.6 * _body(e);
  if (_bull(e) && _body(e) >= avgBody && mids.every(insideRange) &&
      mids.every(smallBody) && _bull(a) && a.close > e.close) {
    add('Rising Three Methods', 'ثلاث طرق صاعدة (استمرار)', 1, up5 ? 1.0 : 0.5);
  }
  if (_bear(e) && _body(e) >= avgBody && mids.every(insideRange) &&
      mids.every(smallBody) && _bear(a) && a.close < e.close) {
    add('Falling Three Methods', 'ثلاث طرق هابطة (استمرار)', -1, dn5 ? 1.0 : 0.5);
  }
  return hits;
}
