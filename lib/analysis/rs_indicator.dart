import 'dart:math' as math;
import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';
import 'star_indicator.dart';

/// مؤشر RS: مؤشر النجوم + دخول أذكى.
///  1) إشارات Mp ومعها نجوم الثقة (ثقة ST + هدوء السوق) — تُعرض التي نجومها ≥ [minStars]
///  2) بعد تأكيد الإشارة لا ندخل فوراً: أمر معلّق عند منتصف شمعة الإشارة صالح 5 شموع
///     (سعر أفضل ووقف أقرب) — إن لم يرجع السعر تُلغى الإشارة.
///  3) نفس إدارة التطبيق: نصف عند TP1، الوقف للدخول، ثم وقف متحرك.
/// مقاس (ذهب وبيتكوين 2021-2026 + أسواق لم يرها): بهدف 1R ≈ 65% (النجوم بالدخول العادي ≈ 57%)،
/// والربح الكلي ≈ الضعف. 3 نجوم ≈ 67%.
class RsResult {
  final AllResult res;
  final Map<(int, int), int> stars;
  const RsResult(this.res, this.stars);
  static const empty = RsResult(AllResult([], [], [], [], 'RS'), {});
  int of(int i, int dir) => stars[(i, dir)] ?? 0;
}

RsResult buildRs(List<Candle> c, AllResult mp, {int minStars = 1, double rr1 = 0.35, double rr2 = 2}) {
  final n = c.length;
  if (n < 120) return RsResult.empty;
  final sr = buildStar(c, mp);
  final at = atr(c, 14);
  final sigs = <PastSignal>[], src = <String>[];
  final pend = <PendingSetup>[], pSrc = <String>[];
  final stars = <(int, int), int>{};
  var busy = -1;
  for (final (q0, s) in mp.signals.indexed) {
    final i = s.i, d = s.dir;
    final g = sr.of(i, d);
    if (g < minStars || i <= busy || i >= n - 1) continue;
    final stop = s.sl;
    // شمعة التأكيد (كسر طرف شمعة الإشارة)
    var ei = -1;
    for (var q = i; q <= i + 3 && q < n; q++) {
      if (d > 0 ? c[q].high >= s.entry : c[q].low <= s.entry) {
        ei = q;
        break;
      }
    }
    if (ei < 0) continue;
    final mid = (c[i].high + c[i].low) / 2;
    if ((mid - stop) * d <= 0) continue;
    final risk = (mid - stop).abs();
    final t1 = mid + d * risk * rr1, t2 = mid + d * risk * rr2;
    // انتظار رجوع السعر لمنتصف الشمعة خلال 5 شموع
    var fill = -1;
    var dead = false;
    for (var q = ei + 1; q <= ei + 5 && q < n; q++) {
      if (d > 0 ? c[q].low <= stop : c[q].high >= stop) {
        dead = true;
        break;
      }
      if (d > 0 ? c[q].low <= mid : c[q].high >= mid) {
        fill = q;
        break;
      }
    }
    if (fill < 0) {
      // ما زال الأمر المعلّق صالحاً (آخر الشموع) → إشارة معلّقة
      if (!dead && ei + 5 >= n - 1) {
        stars[(i, d)] = g;
        pend
          ..clear()
          ..add(PendingSetup(d, mid, stop, t1, t2, 'أمر معلّق عند منتصف شمعة الإشارة — صالح 5 شموع', i));
        pSrc
          ..clear()
          ..add(mp.sources[q0]);
      }
      continue;
    }
    // إدارة الصفقة: نصف عند TP1 ثم الوقف للدخول ثم وقف متحرك (أعلى 22 شمعة − 3 ATR)
    var st = stop, got = false, res = 0, exitI = -1;
    var exitPrice = double.nan;
    for (var j = fill; j < n; j++) {
      final b = c[j];
      if (d > 0 ? b.low <= st : b.high >= st) {
        res = got ? ((st - t2) * d >= 0 ? 2 : 1) : -1;
        exitPrice = st;
        exitI = j;
        break;
      }
      if (j == fill) continue; // لا نحسب الأهداف في شمعة الدخول (تحفّظ)
      if (!got && (d > 0 ? b.high >= t1 : b.low <= t1)) {
        got = true;
        st = mid;
      } else if (got) {
        var hh = d > 0 ? -double.infinity : double.infinity;
        for (var r = math.max(0, j - 21); r <= j; r++) {
          hh = d > 0 ? math.max(hh, c[r].high) : math.min(hh, c[r].low);
        }
        final a = at[j].isNaN ? b.high - b.low : at[j];
        final cand = hh - d * 3 * a;
        st = d > 0 ? math.max(st, cand) : math.min(st, cand);
      }
      if (!got && j >= i + 80) {
        res = -2;
        exitPrice = b.close;
        exitI = j;
        break;
      }
      if (got && j >= i + 300) {
        res = (b.close - t2) * d >= 0 ? 2 : 1;
        exitPrice = b.close;
        exitI = j;
        break;
      }
    }
    if (exitI < 0 && got) res = 1;
    stars[(i, d)] = g;
    sigs.add(PastSignal(i, d, mid, stop, t1, t2, res, exitI,
        'RS: ${s.why} — دخول بأمر معلّق عند منتصف شمعة الإشارة', false, 0, 0, exitPrice, exitI < 0 ? st : double.nan));
    src.add(mp.sources[q0]);
    busy = exitI < 0 ? n : exitI;
  }
  final open = sigs.isNotEmpty && sigs.last.exitI < 0;
  return RsResult(AllResult(sigs, src, open ? const [] : pend, open ? const [] : pSrc, 'RS'), stars);
}
