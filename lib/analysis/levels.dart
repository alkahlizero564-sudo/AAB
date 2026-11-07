import 'dart:math' as math;
import '../models.dart';
import 'smc.dart';

// ───────────────────── New York time helpers ─────────────────────
bool usDst(DateTime utc) {
  final y = utc.year;
  DateTime nthSunday(int month, int nth) {
    var d = DateTime.utc(y, month, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(Duration(days: 7 * (nth - 1)));
  }

  final start = nthSunday(3, 2).add(const Duration(hours: 7));
  final end = nthSunday(11, 1).add(const Duration(hours: 6));
  return !utc.isBefore(start) && utc.isBefore(end);
}

int nyOffsetSec(int ts) =>
    (usDst(DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)) ? -4 : -5) * 3600;

/// DateTime whose fields show New York wall-clock time.
DateTime nyNow(DateTime utc) =>
    utc.add(Duration(seconds: nyOffsetSec(utc.millisecondsSinceEpoch ~/ 1000)));

DateTime nyToUtc(int y, int m, int d, int h, int mi) {
  var g = DateTime.utc(y, m, d, h, mi).add(const Duration(hours: 5));
  if (usDst(g)) g = g.subtract(const Duration(hours: 1));
  return g;
}

/// Next (or currently running) session open. NY = 09:30 NY, LDN = 03:00 NY.
DateTime sessionOpenUtc(String session, DateTime nowUtc) {
  final h = session == 'NY' ? 9 : 3;
  final mi = session == 'NY' ? 30 : 0;
  final ny = nyNow(nowUtc);
  var date = DateTime.utc(ny.year, ny.month, ny.day);
  final open = nyToUtc(date.year, date.month, date.day, h, mi);
  if (nowUtc.isAfter(open.add(const Duration(hours: 7)))) {
    date = date.add(const Duration(days: 1));
  }
  while (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
    date = date.add(const Duration(days: 1));
  }
  return nyToUtc(date.year, date.month, date.day, h, mi);
}

// ───────────────────────── Fibonacci ─────────────────────────
class FibResult {
  final bool upLeg;
  final double hi, lo;
  final List<FibLevel> levels;
  const FibResult(this.upLeg, this.hi, this.lo, this.levels);
}

/// Auto Fibonacci on the dominant swing of the last [look] candles.
FibResult? fibonacci(List<Candle> c, {int look = 120}) {
  if (c.length < 30) return null;
  final start = math.max(0, c.length - look);
  var ih = start, il = start;
  for (var i = start; i < c.length; i++) {
    if (c[i].high >= c[ih].high) ih = i;
    if (c[i].low <= c[il].low) il = i;
  }
  final hi = c[ih].high, lo = c[il].low;
  final range = hi - lo;
  if (range <= 0 || ih == il) return null;
  final up = il < ih;
  final out = <FibLevel>[];
  for (final r in const [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0]) {
    out.add(FibLevel(r, up ? hi - r * range : lo + r * range));
  }
  for (final r in const [1.272, 1.618]) {
    out.add(FibLevel(r, up ? hi + (r - 1) * range : lo - (r - 1) * range));
  }
  return FibResult(up, hi, lo, out);
}

(int, String) fibVote(double price, FibResult f) {
  final range = f.hi - f.lo;
  if (range <= 0) return (0, 'لا نطاق');
  final r = f.upLeg ? (f.hi - price) / range : (price - f.lo) / range;
  if (r >= 0.5 && r <= 0.786) {
    return (f.upLeg ? 1 : -1, 'منطقة OTE (0.5–0.786)');
  }
  if (r >= 0.382 && r < 0.5) {
    return (f.upLeg ? 1 : -1, 'تصحيح 0.382–0.5');
  }
  if (r > 0.786 && r <= 1.0) return (0, 'تصحيح عميق');
  return (0, 'خارج مناطق فيبوناتشي');
}

// ───────────────────────── Volume Profile ─────────────────────────
class VpResult {
  final List<VpBin> bins;
  final double poc, vah, val;
  const VpResult(this.bins, this.poc, this.vah, this.val);
}

VpResult? buildVp(List<Candle> c, {int look = 150, int bins = 30}) {
  if (c.length < 30) return null;
  final s = c.sublist(math.max(0, c.length - look));
  double lo = double.infinity, hi = -double.infinity;
  for (final k in s) {
    lo = math.min(lo, k.low);
    hi = math.max(hi, k.high);
  }
  if (hi <= lo) return null;
  final step = (hi - lo) / bins;
  final w = List<double>.filled(bins, 0);
  for (final k in s) {
    final v = k.volume > 0 ? k.volume : 1.0;
    final b0 = ((k.low - lo) / step).floor().clamp(0, bins - 1).toInt();
    final b1 = ((k.high - lo) / step).floor().clamp(0, bins - 1).toInt();
    final share = v / (b1 - b0 + 1);
    for (var b = b0; b <= b1; b++) {
      w[b] += share;
    }
  }
  var pocB = 0;
  for (var b = 1; b < bins; b++) {
    if (w[b] > w[pocB]) pocB = b;
  }
  final total = w.fold<double>(0, (a, b) => a + b);
  var acc = w[pocB], up = pocB, dn = pocB;
  while (acc < total * 0.7 && (up < bins - 1 || dn > 0)) {
    final nu = up < bins - 1 ? w[up + 1] : -1.0;
    final nd = dn > 0 ? w[dn - 1] : -1.0;
    if (nu >= nd) {
      up++;
      acc += w[up];
    } else {
      dn--;
      acc += w[dn];
    }
  }
  final out = [
    for (var b = 0; b < bins; b++) VpBin(lo + step * b, lo + step * (b + 1), w[b])
  ];
  return VpResult(out, lo + step * (pocB + 0.5), lo + step * (up + 1), lo + step * dn);
}

// ───────────────────────── VWAP ─────────────────────────
/// FX / metals / crypto: anchored at 17:00 New York. Stocks: 09:30 New York.
int vwapAnchorTs(MarketSymbol sym, DateTime lastUtc) {
  final ts = lastUtc.millisecondsSinceEpoch ~/ 1000;
  final off = nyOffsetSec(ts);
  final ny = ts + off;
  final dayStart = ny - ny % 86400;
  var anchorNy = sym.category == 'stock'
      ? dayStart + 9 * 3600 + 1800
      : dayStart + 17 * 3600;
  if (ny < anchorNy) anchorNy -= 86400;
  return anchorNy - off;
}

/// Volume-weighted when volume exists, otherwise equal-weighted typical price.
List<double> vwapSeries(List<Candle> c, int anchorTs) {
  final out = List<double>.filled(c.length, double.nan);
  double pv = 0, vv = 0;
  var started = false;
  for (var i = 0; i < c.length; i++) {
    if (!started && c[i].ts >= anchorTs) started = true;
    if (!started) continue;
    final tp = (c[i].high + c[i].low + c[i].close) / 3;
    final v = c[i].volume > 0 ? c[i].volume : 1.0;
    pv += tp * v;
    vv += v;
    out[i] = pv / vv;
  }
  return out;
}

// ───────────────────────── Day / session levels ─────────────────────────
class DayLevels {
  final double pdh, pdl, pdc, dayOpen, asiaH, asiaL, ldnH, ldnL;
  const DayLevels(this.pdh, this.pdl, this.pdc, this.dayOpen, this.asiaH,
      this.asiaL, this.ldnH, this.ldnL);
}

int _fxDayIdx(int ts) {
  final ny = ts + nyOffsetSec(ts);
  return ((ny - 17 * 3600) / 86400).floor();
}

int _nyHour(int ts) {
  final ny = ts + nyOffsetSec(ts);
  return ((ny % 86400) / 3600).floor();
}

/// [chart] = candles of the chart timeframe, [higher] = coarser candles that
/// cover the previous days (used for PDH/PDL/PDC).
DayLevels dayLevels(List<Candle> chart, List<Candle>? higher, DateTime lastUtc) {
  const nan = double.nan;
  if (chart.isEmpty) return const DayLevels(nan, nan, nan, nan, nan, nan, nan, nan);
  final lastTs = chart.last.ts;
  final cur = _fxDayIdx(lastTs);
  final src = (higher != null && higher.length >= 10) ? higher : chart;
  final g = <int, List<double>>{};
  for (final k in src) {
    final id = _fxDayIdx(k.ts);
    final v = g[id];
    if (v == null) {
      g[id] = [k.high, k.low, k.close];
    } else {
      v[0] = math.max(v[0], k.high);
      v[1] = math.min(v[1], k.low);
      v[2] = k.close;
    }
  }
  int? prev;
  for (final id in g.keys) {
    if (id < cur && (prev == null || id > prev)) prev = id;
  }
  var pdh = nan, pdl = nan, pdc = nan;
  if (prev != null) {
    pdh = g[prev]![0];
    pdl = g[prev]![1];
    pdc = g[prev]![2];
  }
  // New York midnight open
  final off = nyOffsetSec(lastTs);
  final ny = lastTs + off;
  final midnightUtc = (ny - ny % 86400) - off;
  var dayOpen = nan;
  for (final k in chart) {
    if (k.ts >= midnightUtc) {
      dayOpen = k.open;
      break;
    }
  }
  // Asia 20:00–24:00 NY, London 02:00–05:00 NY inside the current FX day
  var aH = -double.infinity, aL = double.infinity;
  var lH = -double.infinity, lL = double.infinity;
  var hasA = false, hasL = false;
  for (final k in chart) {
    if (_fxDayIdx(k.ts) != cur) continue;
    final h = _nyHour(k.ts);
    if (h >= 20) {
      hasA = true;
      aH = math.max(aH, k.high);
      aL = math.min(aL, k.low);
    } else if (h >= 2 && h < 5) {
      hasL = true;
      lH = math.max(lH, k.high);
      lL = math.min(lL, k.low);
    }
  }
  return DayLevels(pdh, pdl, pdc, dayOpen, hasA ? aH : nan, hasA ? aL : nan,
      hasL ? lH : nan, hasL ? lL : nan);
}

List<KeyLevel> buildKeyLevels(DayLevels d, VpResult? vp, double vwap) {
  final l = <KeyLevel>[];
  void add(String n, double p, int side, String kind) {
    if (!p.isNaN) l.add(KeyLevel(n, p, side, kind));
  }

  add('PDH', d.pdh, 1, 'day');
  add('PDL', d.pdl, -1, 'day');
  add('PDC', d.pdc, 0, 'day');
  add('Open', d.dayOpen, 0, 'day');
  add('Asia H', d.asiaH, 1, 'session');
  add('Asia L', d.asiaL, -1, 'session');
  add('London H', d.ldnH, 1, 'session');
  add('London L', d.ldnL, -1, 'session');
  if (vp != null) {
    add('POC', vp.poc, 0, 'vp');
    add('VAH', vp.vah, 0, 'vp');
    add('VAL', vp.val, 0, 'vp');
  }
  add('VWAP', vwap, 0, 'vwap');
  return l;
}

/// Sweeps of PDH / PDL / Asia / London highs and lows.
List<SweepEvent> levelSweeps(List<Candle> c, List<KeyLevel> lv, {int recent = 3}) {
  final out = <SweepEvent>[];
  final n = c.length;
  for (var i = math.max(1, n - recent); i < n; i++) {
    for (final l in lv) {
      if (l.side == 0 || (l.kind != 'day' && l.kind != 'session')) continue;
      if (l.side > 0 && c[i].high > l.price && c[i].close < l.price) {
        out.add(SweepEvent(i, -1, 'سحب ${l.name}', c[i].high));
      } else if (l.side < 0 && c[i].low < l.price && c[i].close > l.price) {
        out.add(SweepEvent(i, 1, 'سحب ${l.name}', c[i].low));
      }
    }
  }
  return out;
}

// ───────────────────────── Opening Range ─────────────────────────
class OpeningRange {
  final double hi, lo;
  final bool complete;
  const OpeningRange(this.hi, this.lo, this.complete);
}

OpeningRange? openingRange(List<Candle> c, int openTs, {int minutes = 30}) {
  double hi = -double.infinity, lo = double.infinity;
  var any = false;
  for (final k in c) {
    if (k.ts >= openTs && k.ts < openTs + minutes * 60) {
      any = true;
      hi = math.max(hi, k.high);
      lo = math.min(lo, k.low);
    }
  }
  if (!any || c.isEmpty) return null;
  return OpeningRange(hi, lo, c.last.ts >= openTs + minutes * 60);
}
