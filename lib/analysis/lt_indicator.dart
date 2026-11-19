import 'dart:math' as math;
import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';

/// مؤشر LT بعيد المدى (فريم يومي، شراء فقط):
///  1) شراء الترند: إغلاق فوق أعلى قمة 55 يوماً وفوق متوسط 200 يوم. الخروج عند إغلاق تحت أدنى قاع 20 يوماً.
///  2) شراء الارتداد: فوق متوسط 200 يوم و RSI(2) < 30. الخروج عند أول إغلاق فوق متوسط 5 أيام أو بعد 10 أيام،
///     ووقف 3×ATR.
/// الذهب يومي 2017-2026: الترند 18 صفقة، ربح 67%، مركّب +116%، أقصى هبوط 6.3%.
/// الارتداد ~21-26 صفقة سنوياً، ربح 70% في الفترتين.
/// البيع لم ينجح على المدى البعيد (الذهب: الترند -18%، الارتداد -14%)، فالمؤشر شراء فقط.
/// [c] شموع يومية. الإشارة من شمعة مغلقة، والدخول عند افتتاح اليوم التالي.
AllResult buildLt(List<Candle> c) {
  final n = c.length;
  if (n < 230) return const AllResult([], [], [], [], 'LT');
  final cl = [for (final k in c) k.close];
  final s200 = sma(cl, 200), s5 = sma(cl, 5);
  final r2 = rsi(cl, 2);
  final at = atr(c, 14);
  final out = <(PastSignal, String)>[];
  final last = n - 2; // آخر شمعة مغلقة

  double minLow(int a, int b) {
    var m = double.infinity;
    for (var q = math.max(0, a); q <= b; q++) {
      m = math.min(m, c[q].low);
    }
    return m;
  }

  double maxHigh(int a, int b) {
    var m = -double.infinity;
    for (var q = math.max(0, a); q <= b; q++) {
      m = math.max(m, c[q].high);
    }
    return m;
  }

  // ── 1) شراء الترند
  var busy = -1;
  for (var i = 201; i <= last; i++) {
    if (i <= busy || s200[i].isNaN) continue;
    if (!(cl[i] > maxHigh(i - 55, i - 1) && cl[i] > s200[i])) continue;
    final e = c[i + 1].open;
    var sl = minLow(i - 19, i);
    if (!(e - sl > 0)) sl = e - 2 * (at[i].isNaN ? (c[i].high - c[i].low) : at[i]);
    final risk = e - sl;
    var exitI = -1;
    for (var j = i + 1; j <= last; j++) {
      if (cl[j] < minLow(j - 20, j - 1)) {
        exitI = j;
        break;
      }
    }
    const why = 'كسر قمة 55 يوماً فوق متوسط 200 يوم — الخروج عند إغلاق تحت أدنى قاع 20 يوماً (الوقف المتحرك)';
    if (exitI >= 0) {
      final x = cl[exitI];
      final win = x > e;
      out.add((
        PastSignal(i, 1, e, sl, win ? x : e + 2 * risk, win ? x : e + 4 * risk, win ? 1 : -1, exitI, why, true, 0, 0, x),
        'ترند'
      ));
      busy = exitI;
    } else {
      final trail = math.max(sl, minLow(last - 19, last));
      // لا هدف ثابت في الترند (الخروج بالوقف المتحرك). للعرض: أقرب مضاعف 2R فوق السعر الحالي ثم +2R
      final px = c[n - 1].close;
      var k = 2;
      while (e + k * risk <= px && k < 400) {
        k += 2;
      }
      out.add((PastSignal(i, 1, e, sl, e + k * risk, e + (k + 2) * risk, 0, -1, why, true, 0, 0, double.nan, trail), 'ترند'));
      busy = n;
    }
  }

  // ── 2) شراء الارتداد
  busy = -1;
  for (var i = 201; i <= last; i++) {
    if (i <= busy || s200[i].isNaN || r2[i].isNaN || at[i].isNaN) continue;
    if (!(cl[i] > s200[i] && r2[i] < 30)) continue;
    final e = c[i + 1].open, stop = e - 3 * at[i], risk = e - stop;
    var exitI = -1;
    var x = double.nan;
    for (var j = i + 1; j < n; j++) {
      if (c[j].low <= stop) {
        exitI = j;
        x = stop;
        break;
      }
      if (j <= last && (cl[j] > s5[j] || j - i >= 10)) {
        exitI = j;
        x = cl[j];
        break;
      }
    }
    const why = 'هبوط قصير حاد (RSI2 < 30) في ترند صاعد فوق متوسط 200 يوم — الخروج عند إغلاق فوق متوسط 5 أيام أو بعد 10 أيام';
    if (exitI >= 0) {
      final win = x > e;
      out.add((
        PastSignal(i, 1, e, stop, win ? x : e + risk, win ? x : e + 2 * risk, win ? 1 : -1, exitI, why, false, 0, 0, x),
        'ارتداد'
      ));
      busy = exitI;
    } else {
      out.add((PastSignal(i, 1, e, stop, e + risk, e + 2 * risk, 0, -1, why, false, 0, 0, double.nan, stop), 'ارتداد'));
      busy = n;
    }
  }
  out.sort((a, b) => a.$1.i.compareTo(b.$1.i));
  return AllResult([for (final x in out) x.$1], [for (final x in out) x.$2], const [], const [], 'LT');
}

/// حالة السوق لمؤشر LT (للعرض): هل السعر فوق متوسط 200 يوم؟
bool ltUptrend(List<Candle> c) {
  if (c.length < 202) return false;
  final cl = [for (final k in c) k.close];
  final s = sma(cl, 200);
  return cl[c.length - 2] > s[c.length - 2];
}
