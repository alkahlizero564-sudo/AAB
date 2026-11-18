import 'dart:math' as math;
import '../models.dart';
import 'forecast.dart';
import 'indicators.dart';

/// فحص الصفقة المفتوحة: هل تواصل أم تضعف؟
/// مبني على اختبار ~28 ألف صفقة Mp حققت TP1 (ذهب وبيتكوين 10 سنوات + 20 سوقاً). الذهب 2021-2026:
///  قوية (زخم/امتداد): النصف الثاني يصل +1R في 23.5% ومتوسطه +0.79R
///  عادية: 16.5% ومتوسطه +0.51R
///  تضعف (شموع عكسية أو سوق هادئ): 10.4% ومتوسطه +0.31R
class TradeCheck {
  final int dir;
  final bool tp1Hit;
  final double nowR; // الربح/الخسارة الآن بوحدات R (للصفقة كاملة لو لم يتحقق TP1)
  final double securedR; // الربح المضمون لو ضُرب الوقف الآن (للصفقة كاملة)
  final String state; // strong | normal | weak | early
  final List<(bool, String)> reasons; // (إيجابي؟، السبب)
  const TradeCheck(this.dir, this.tp1Hit, this.nowR, this.securedR, this.state, this.reasons);
}

TradeCheck? checkTrade(List<Candle> c, PastSignal s) {
  final n = c.length;
  if (n < 30 || s.exitI >= 0) return null;
  final d = s.dir;
  final risk = (s.entry - s.sl).abs();
  if (!(risk > 0)) return null;
  final i = n - 2; // آخر شمعة مغلقة
  final at = atr(c, 14);
  final am = sma(at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
  final cl = [for (final k in c) k.close];
  final e20 = ema(cl, 20), rs = rsi(cl, 14);
  final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
  final tp1Hit = s.result >= 1;
  final nowR = (c[n - 1].close - s.entry) * d / risk;
  final tp1R = (s.tp1 - s.entry) * d / risk;
  final stop = s.curStop.isNaN ? (tp1Hit ? s.entry : s.sl) : s.curStop;
  final stopR = (stop - s.entry) * d / risk;
  final securedR = tp1Hit ? 0.5 * tp1R + 0.5 * math.max(0.0, stopR) : stopR;

  var bodies = 0.0;
  for (var q = i - 2; q <= i; q++) {
    bodies += (c[q].close - c[q].open) * d;
  }
  var opp = 0;
  for (var q = i - 4; q <= i; q++) {
    if ((c[q].close - c[q].open) * d < 0) opp++;
  }
  final momentum = a > 0 && bodies / a > 1;
  final far = !e20[i].isNaN && a > 0 && (c[i].close - e20[i]) * d / a > 2;
  final rsiExt = !rs[i].isNaN && ((d > 0 && rs[i] > 70) || (d < 0 && rs[i] < 30));
  final calm = !at[i].isNaN && am[i] > 0 && at[i] / am[i] < 0.9;
  final oppMany = opp >= 3;

  final reasons = <(bool, String)>[
    if (momentum) (true, 'زخم قوي: آخر 3 شموع في اتجاه صفقتك'),
    if (far) (true, 'السعر ممتد بعيداً عن المتوسط (EMA20) في اتجاه صفقتك'),
    if (rsiExt) (true, 'RSI ممتد في اتجاه صفقتك — الحركة القوية تميل للاستمرار'),
    if (oppMany) (false, '$opp من آخر 5 شموع عكس صفقتك'),
    if (calm) (false, 'السوق هادئ — الحركات الكبيرة أقل'),
  ];
  final String state;
  if (!tp1Hit) {
    state = 'early';
  } else if (momentum || far || rsiExt) {
    state = 'strong';
  } else if (oppMany || calm) {
    state = 'weak';
  } else {
    state = 'normal';
  }
  return TradeCheck(d, tp1Hit, nowR, securedR, state, reasons);
}
