import 'dart:math' as math;
import '../models.dart';
import 'forecast.dart';
import 'indicator_panel.dart';
import 'indicators.dart';
import 'smc.dart';
import 'tv_indicators.dart';

/// نتيجة مؤشر واحد في المقارنة.
class BenchRow {
  final String name;
  final int wins, trades;
  final double totalR;
  final bool ours;
  const BenchRow(this.name, this.wins, this.trades, this.totalR, {this.ours = false});
  double get winRate => trades == 0 ? 0 : wins / trades;
  double get avgR => trades == 0 ? 0 : totalR / trades;
}

/// نفس إدارة الصفقة لكل المؤشرات (عادلة): دخول افتتاح الشمعة التالية، وقف خلف
/// آخر 3 شموع (0.7–2.5 ATR)، هدف أول 1R ثم الوقف للدخول، هدف ثانٍ 2R، صفقة واحدة كل مرة.
(int, int, double) _sim(List<Candle> c, List<int> sig) {
  final n = c.length;
  final at = atr(c, 14);
  var w = 0, tn = 0, busy = -1;
  var r = 0.0;
  for (var i = 60; i < n - 1; i++) {
    final d = sig[i];
    if (d == 0 || i <= busy || at[i].isNaN) continue;
    final a = at[i];
    final entry = c[i + 1].open;
    var ext = d > 0 ? c[i].low : c[i].high;
    for (var j = i - 2; j <= i; j++) {
      ext = d > 0 ? math.min(ext, c[j].low) : math.max(ext, c[j].high);
    }
    final risk =
        ((d > 0 ? entry - ext : ext - entry) + 0.1 * a).clamp(0.7 * a, 2.5 * a).toDouble();
    final t1 = entry + d * risk, t2 = entry + d * 2 * risk;
    var stop = entry - d * risk, got = false, res = 0, exitI = -1;
    for (var j = i + 1; j < n; j++) {
      final k = c[j];
      if (d > 0 ? k.low <= stop : k.high >= stop) {
        res = got ? 1 : -1;
        exitI = j;
        break;
      }
      if (!got && (d > 0 ? k.high >= t1 : k.low <= t1)) {
        got = true;
        stop = entry;
      }
      if (got && (d > 0 ? k.high >= t2 : k.low <= t2)) {
        res = 2;
        exitI = j;
        break;
      }
      if (j >= i + 80) {
        res = got ? 1 : -1;
        exitI = j;
        break;
      }
    }
    if (exitI < 0) {
      if (!got) break; // صفقة مفتوحة بلا نتيجة بعد
      res = 1;
    }
    tn++;
    if (res > 0) w++;
    r += res == 2 ? 1.5 : res == 1 ? 0.5 : -1;
    busy = exitI < 0 ? n : exitI;
  }
  return (w, tn, r);
}

List<int> _cross(List<double> a, List<double> b) {
  final s = List<int>.filled(a.length, 0);
  for (var i = 1; i < a.length; i++) {
    if (a[i].isNaN || b[i].isNaN || a[i - 1].isNaN || b[i - 1].isNaN) continue;
    if (a[i - 1] <= b[i - 1] && a[i] > b[i]) s[i] = 1;
    if (a[i - 1] >= b[i - 1] && a[i] < b[i]) s[i] = -1;
  }
  return s;
}

List<int> _flips(List<int> dir) {
  final s = List<int>.filled(dir.length, 0);
  for (var i = 1; i < dir.length; i++) {
    if (dir[i] != 0 && dir[i - 1] != 0 && dir[i] != dir[i - 1]) s[i] = dir[i];
  }
  return s;
}

/// يقارن مؤشرنا بأشهر مؤشرات TradingView (بإعداداتها الافتراضية) على نفس الشموع.
List<BenchRow> benchmark(List<Candle> c) {
  final n = c.length;
  if (n < 120) return const [];
  final cl = c.map((e) => e.close).toList();
  final sigs = <String, List<int>>{};
  final r = rsi(cl, 14);
  final rs = List<int>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    if (r[i].isNaN || r[i - 1].isNaN) continue;
    if (r[i - 1] < 30 && r[i] >= 30) rs[i] = 1;
    if (r[i - 1] > 70 && r[i] <= 70) rs[i] = -1;
  }
  sigs['RSI 30/70'] = rs;
  final m = macd(cl);
  sigs['MACD'] = _cross(m.line, m.signal);
  sigs['Supertrend'] = _flips(supertrend(c).dir);
  sigs['EMA 9/21'] = _cross(ema(cl, 9), ema(cl, 21));
  sigs['Chandelier Exit'] = chandelier(c).sig;
  {
    final at = atr(c, 10);
    final s = List<int>.filled(n, 0);
    var stop = 0.0, pos = 0;
    for (var i = 1; i < n; i++) {
      if (at[i].isNaN) continue;
      final src = cl[i], prev = cl[i - 1], ps = stop;
      if (src > ps && prev > ps) {
        stop = math.max(ps, src - at[i]);
      } else if (src < ps && prev < ps) {
        stop = math.min(ps, src + at[i]);
      } else {
        stop = src > ps ? src - at[i] : src + at[i];
      }
      var np = pos;
      if (prev < ps && src > ps) np = 1;
      if (prev > ps && src < ps) np = -1;
      if (np != pos && pos != 0) s[i] = np;
      pos = np;
    }
    sigs['UT Bot'] = s;
  }
  final panel = {for (final p in buildPanel(c, atr(c, 14))) p.key: p.trig};
  const names = {
    'bb': 'Bollinger Bands',
    'stoch': 'Stochastic',
    'ichi': 'Ichimoku',
    'psar': 'Parabolic SAR',
    'ha': 'Heikin Ashi',
    'donch': 'Donchian',
    'adx': 'ADX / DMI',
    'cci': 'CCI',
  };
  names.forEach((k, v) {
    final t = panel[k];
    if (t != null) sigs[v] = t;
  });
  for (final p in tvIndicators(c)) {
    sigs[p.name] = p.trig;
  }

  final rows = <BenchRow>[];
  sigs.forEach((k, s) {
    final (w, tn, tr) = _sim(c, s);
    rows.add(BenchRow(k, w, tn, tr));
  });
  final f = buildForecast(c, history: c.length, rr1: 1, rr2: 2);
  var fr = 0.0;
  for (final x in f.signals) {
    if (x.result == 0) continue;
    fr += x.result == 2 ? 1.5 : x.result == 1 ? 0.5 : -1;
  }
  rows.add(BenchRow('★ مؤشر AAB', f.wins, f.closed, fr, ours: true));
  rows.sort((a, b) {
    final c1 = b.winRate.compareTo(a.winRate);
    return c1 != 0 ? c1 : b.avgR.compareTo(a.avgR);
  });
  return rows;
}
