import 'dart:math' as math;
import '../models.dart';
import 'indicators.dart';

// ───────────────────────── Pivots ─────────────────────────
class Pivot {
  final int i;
  final double p;
  const Pivot(this.i, this.p);
}

List<Pivot> pivotHighs(List<Candle> c, int left, int right) {
  final out = <Pivot>[];
  for (var i = left; i < c.length - right; i++) {
    final h = c[i].high;
    var ok = true;
    for (var j = i - left; j <= i + right; j++) {
      if (j == i) continue;
      if (j < i ? c[j].high >= h : c[j].high > h) {
        ok = false;
        break;
      }
    }
    if (ok) out.add(Pivot(i, h));
  }
  return out;
}

List<Pivot> pivotLows(List<Candle> c, int left, int right) {
  final out = <Pivot>[];
  for (var i = left; i < c.length - right; i++) {
    final l = c[i].low;
    var ok = true;
    for (var j = i - left; j <= i + right; j++) {
      if (j == i) continue;
      if (j < i ? c[j].low <= l : c[j].low < l) {
        ok = false;
        break;
      }
    }
    if (ok) out.add(Pivot(i, l));
  }
  return out;
}

// ───────────────────── Chandelier Exit ─────────────────────
class CeResult {
  final List<double> longStop, shortStop;
  final List<int> dir, sig; // sig: +1 buy flip, -1 sell flip
  CeResult(this.longStop, this.shortStop, this.dir, this.sig);
}

CeResult chandelier(List<Candle> c,
    {int period = 22, double mult = 3, bool useClose = true}) {
  final n = c.length;
  final at = atr(c, period);
  final nan = double.nan;
  final ls = List<double>.filled(n, nan), ss = List<double>.filled(n, nan);
  final dir = List<int>.filled(n, 1), sig = List<int>.filled(n, 0);
  double? lsPrev, ssPrev;
  var d = 1;
  var started = false;
  for (var i = 0; i < n; i++) {
    if (i < period || at[i].isNaN) continue;
    final a = at[i] * mult;
    double hh = -double.infinity, ll = double.infinity;
    for (var j = i - period + 1; j <= i; j++) {
      final hi = useClose ? c[j].close : c[j].high;
      final lo = useClose ? c[j].close : c[j].low;
      hh = math.max(hh, hi);
      ll = math.min(ll, lo);
    }
    var l = hh - a;
    var s = ll + a;
    final lp = lsPrev ?? l;
    final sp = ssPrev ?? s;
    if (c[i - 1].close > lp) l = math.max(l, lp);
    if (c[i - 1].close < sp) s = math.min(s, sp);
    final prevD = d;
    if (c[i].close > sp) {
      d = 1;
    } else if (c[i].close < lp) {
      d = -1;
    }
    dir[i] = d;
    if (started) {
      if (d == 1 && prevD == -1) sig[i] = 1;
      if (d == -1 && prevD == 1) sig[i] = -1;
    }
    started = true;
    ls[i] = l;
    ss[i] = s;
    lsPrev = l;
    ssPrev = s;
  }
  return CeResult(ls, ss, dir, sig);
}

// ───────────────────────── Supertrend ─────────────────────────
class StResult {
  final List<int> dir;
  StResult(this.dir);
}

StResult supertrend(List<Candle> c, [int p = 10, double m = 3]) {
  final n = c.length;
  final at = atr(c, p);
  final dir = List<int>.filled(n, 0);
  double prevUb = 0, prevLb = 0;
  var d = 1;
  for (var i = 0; i < n; i++) {
    if (i < p || at[i].isNaN) continue;
    final hl2 = (c[i].high + c[i].low) / 2;
    var ub = hl2 + m * at[i];
    var lb = hl2 - m * at[i];
    if (i > p) {
      ub = (ub < prevUb || c[i - 1].close > prevUb) ? ub : prevUb;
      lb = (lb > prevLb || c[i - 1].close < prevLb) ? lb : prevLb;
      if (d == -1 && c[i].close > prevUb) {
        d = 1;
      } else if (d == 1 && c[i].close < prevLb) {
        d = -1;
      }
    }
    dir[i] = d;
    prevUb = ub;
    prevLb = lb;
  }
  return StResult(dir);
}

// ───────────────────────── Ichimoku ─────────────────────────
double _mid(List<Candle> c, int end, int len) {
  double hh = -double.infinity, ll = double.infinity;
  for (var j = end - len + 1; j <= end; j++) {
    hh = math.max(hh, c[j].high);
    ll = math.min(ll, c[j].low);
  }
  return (hh + ll) / 2;
}

(int, String) ichimokuVote(List<Candle> c) {
  final i = c.length - 1;
  final k = i - 26;
  if (k < 52) return (0, 'بيانات قليلة');
  final spanA = (_mid(c, k, 9) + _mid(c, k, 26)) / 2;
  final spanB = _mid(c, k, 52);
  final top = math.max(spanA, spanB), bot = math.min(spanA, spanB);
  final p = c[i].close;
  if (p > top) return (1, 'فوق السحابة');
  if (p < bot) return (-1, 'تحت السحابة');
  return (0, 'داخل السحابة');
}

// ─────────────── SR Breaks & Retests (ChartPrime style) ───────────────
class SrEvent {
  final int i;
  final int bias;
  final bool retest;
  final double level;
  const SrEvent(this.i, this.bias, this.retest, this.level);
}

class SrResult {
  final List<SrEvent> events;
  final double? res, sup;
  final int resI, supI;
  SrResult(this.events, this.res, this.sup, this.resI, this.supI);
}

SrResult srBreaks(List<Candle> c, List<double> at,
    {int left = 15, int right = 3}) {
  final n = c.length;
  final ph = {for (final p in pivotHighs(c, left, right)) p.i + right: p};
  final pl = {for (final p in pivotLows(c, left, right)) p.i + right: p};
  double? res, sup;
  var resI = -1, supI = -1;
  var resOn = false, supOn = false;
  double? upLvl, dnLvl;
  var upAt = -1, dnAt = -1;
  final ev = <SrEvent>[];
  for (var i = 1; i < n; i++) {
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    final tol = 0.3 * a;
    final pH = ph[i];
    if (pH != null) {
      res = pH.p;
      resI = pH.i;
      resOn = true;
    }
    final pL = pl[i];
    if (pL != null) {
      sup = pL.p;
      supI = pL.i;
      supOn = true;
    }
    if (res != null && resOn && c[i - 1].close <= res && c[i].close > res) {
      ev.add(SrEvent(i, 1, false, res));
      resOn = false;
      upLvl = res;
      upAt = i;
    }
    if (sup != null && supOn && c[i - 1].close >= sup && c[i].close < sup) {
      ev.add(SrEvent(i, -1, false, sup));
      supOn = false;
      dnLvl = sup;
      dnAt = i;
    }
    if (upLvl != null) {
      final d = i - upAt;
      if (d >= 2 && d <= 15) {
        if (c[i].low <= upLvl + tol && c[i].close > upLvl) {
          ev.add(SrEvent(i, 1, true, upLvl));
          upLvl = null;
        } else if (c[i].close < upLvl - tol) {
          upLvl = null;
        }
      } else if (d > 15) {
        upLvl = null;
      }
    }
    if (dnLvl != null) {
      final d = i - dnAt;
      if (d >= 2 && d <= 15) {
        if (c[i].high >= dnLvl - tol && c[i].close < dnLvl) {
          ev.add(SrEvent(i, -1, true, dnLvl));
          dnLvl = null;
        } else if (c[i].close > dnLvl + tol) {
          dnLvl = null;
        }
      } else if (d > 15) {
        dnLvl = null;
      }
    }
  }
  return SrResult(ev, res, sup, resI, supI);
}

// ───────────────────────── Order Blocks ─────────────────────────
class _RawZone {
  final int idx, bias;
  final double top, bottom;
  _RawZone(this.idx, this.bias, this.top, this.bottom);
}

List<Zone> orderBlocks(List<Candle> c, {int len = 5}) {
  final n = c.length;
  final phAt = {for (final p in pivotHighs(c, len, len)) p.i + len: p};
  final plAt = {for (final p in pivotLows(c, len, len)) p.i + len: p};
  double? hi, lo;
  var hiI = 0, loI = 0;
  var hiB = false, loB = false;
  final raws = <_RawZone>[];
  for (var i = 0; i < n; i++) {
    final a = phAt[i];
    if (a != null) {
      hi = a.p;
      hiI = a.i;
      hiB = false;
    }
    final b = plAt[i];
    if (b != null) {
      lo = b.p;
      loI = b.i;
      loB = false;
    }
    if (hi != null && !hiB && c[i].close > hi) {
      hiB = true;
      var li = hiI;
      var mn = double.infinity;
      for (var j = hiI; j <= i; j++) {
        if (c[j].low < mn) {
          mn = c[j].low;
          li = j;
        }
      }
      for (var j = li; j >= math.max(0, li - 6); j--) {
        if (c[j].close < c[j].open) {
          raws.add(_RawZone(j, 1, c[j].high, c[j].low));
          break;
        }
      }
    }
    if (lo != null && !loB && c[i].close < lo) {
      loB = true;
      var hI = loI;
      var mx = -double.infinity;
      for (var j = loI; j <= i; j++) {
        if (c[j].high > mx) {
          mx = c[j].high;
          hI = j;
        }
      }
      for (var j = hI; j >= math.max(0, hI - 6); j--) {
        if (c[j].close > c[j].open) {
          raws.add(_RawZone(j, -1, c[j].high, c[j].low));
          break;
        }
      }
    }
  }
  final bull = <Zone>[], bear = <Zone>[];
  final seen = <int>{};
  for (final z in raws.reversed) {
    if (!seen.add(z.idx * 10 + (z.bias > 0 ? 1 : 0))) continue;
    var mit = false;
    for (var j = z.idx + 1; j < n; j++) {
      if (z.bias > 0 ? c[j].close < z.bottom : c[j].close > z.top) {
        mit = true;
        break;
      }
    }
    if (mit) continue;
    final zone = Zone('OB', z.bias, z.top, z.bottom, c[z.idx].ts,
        z.bias > 0 ? 'OB ▲' : 'OB ▼');
    if (z.bias > 0) {
      if (bull.length < 3) bull.add(zone);
    } else {
      if (bear.length < 3) bear.add(zone);
    }
  }
  return [...bull, ...bear];
}

// ───────────────────────── Fair Value Gaps ─────────────────────────
List<Zone> fairValueGaps(List<Candle> c, List<double> at) {
  final n = c.length;
  final bull = <Zone>[], bear = <Zone>[];
  for (var i = n - 1; i >= math.max(2, n - 150); i--) {
    final a = at[i].isNaN ? 0.0 : at[i];
    final minGap = 0.15 * a;
    if (bull.length < 3 &&
        c[i].low > c[i - 2].high &&
        c[i].low - c[i - 2].high >= minGap) {
      final bottom = c[i - 2].high;
      var filled = false;
      for (var j = i + 1; j < n; j++) {
        if (c[j].close < bottom) {
          filled = true;
          break;
        }
      }
      if (!filled) {
        bull.add(Zone('FVG', 1, c[i].low, bottom, c[i - 1].ts, 'FVG ▲'));
      }
    }
    if (bear.length < 3 &&
        c[i].high < c[i - 2].low &&
        c[i - 2].low - c[i].high >= minGap) {
      final top = c[i - 2].low;
      var filled = false;
      for (var j = i + 1; j < n; j++) {
        if (c[j].close > top) {
          filled = true;
          break;
        }
      }
      if (!filled) {
        bear.add(Zone('FVG', -1, top, c[i].high, c[i - 1].ts, 'FVG ▼'));
      }
    }
    if (bull.length >= 3 && bear.length >= 3) break;
  }
  return [...bull, ...bear];
}

// ───────────────────── Equal Highs / Equal Lows ─────────────────────
List<Zone> equalLevels(List<Candle> c, double a) {
  final start = math.max(0, c.length - 150);
  final ph = pivotHighs(c, 3, 3).where((p) => p.i >= start).toList();
  final pl = pivotLows(c, 3, 3).where((p) => p.i >= start).toList();
  final tol = 0.15 * a;
  final out = <Zone>[];
  var nh = 0, nl = 0;
  for (var x = ph.length - 1; x >= 1 && nh < 2; x--) {
    for (var y = x - 1; y >= 0 && y >= x - 4; y--) {
      if ((ph[x].p - ph[y].p).abs() <= tol) {
        final lvl = (ph[x].p + ph[y].p) / 2;
        out.add(Zone('EQH', -1, lvl + 0.03 * a, lvl - 0.03 * a, c[ph[y].i].ts, 'EQH'));
        nh++;
        break;
      }
    }
  }
  for (var x = pl.length - 1; x >= 1 && nl < 2; x--) {
    for (var y = x - 1; y >= 0 && y >= x - 4; y--) {
      if ((pl[x].p - pl[y].p).abs() <= tol) {
        final lvl = (pl[x].p + pl[y].p) / 2;
        out.add(Zone('EQL', 1, lvl + 0.03 * a, lvl - 0.03 * a, c[pl[y].i].ts, 'EQL'));
        nl++;
        break;
      }
    }
  }
  return out;
}

// ─────────── Liquidity Sweep Hunter / ICT Turtle Soup ───────────
class SweepEvent {
  final int i, bias;
  final String name;
  final double extreme;
  const SweepEvent(this.i, this.bias, this.name, this.extreme);
}

List<SweepEvent> liquiditySweeps(List<Candle> c, List<Zone> eq,
    {int lookback = 20, int recent = 3}) {
  final out = <SweepEvent>[];
  final n = c.length;
  for (var i = math.max(lookback, n - recent); i < n; i++) {
    double hh = -double.infinity, ll = double.infinity;
    for (var j = i - lookback; j < i; j++) {
      hh = math.max(hh, c[j].high);
      ll = math.min(ll, c[j].low);
    }
    if (c[i].high > hh && c[i].close < hh) {
      out.add(SweepEvent(i, -1, 'سحب سيولة علوية (Turtle Soup)', c[i].high));
    } else if (c[i].low < ll && c[i].close > ll) {
      out.add(SweepEvent(i, 1, 'سحب سيولة سفلية (Turtle Soup)', c[i].low));
    } else {
      for (final z in eq) {
        final lvl = (z.top + z.bottom) / 2;
        if (z.kind == 'EQH' && c[i].high > lvl && c[i].close < lvl) {
          out.add(SweepEvent(i, -1, 'سحب EQH', c[i].high));
          break;
        }
        if (z.kind == 'EQL' && c[i].low < lvl && c[i].close > lvl) {
          out.add(SweepEvent(i, 1, 'سحب EQL', c[i].low));
          break;
        }
      }
    }
  }
  return out;
}

// ─────────────── Premium / Discount (Dynamic 50%) ───────────────
double equilibrium(List<Candle> c, {int look = 100}) {
  final start = math.max(0, c.length - look);
  double hh = -double.infinity, ll = double.infinity;
  for (var j = start; j < c.length; j++) {
    hh = math.max(hh, c[j].high);
    ll = math.min(ll, c[j].low);
  }
  return (hh + ll) / 2;
}

// ───────────────────────── Volume Profile ─────────────────────────
class VProfile {
  final double poc, vah, val;
  const VProfile(this.poc, this.vah, this.val);
}

VProfile? volumeProfile(List<Candle> c, {int look = 150, int bins = 30}) {
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
  double center(int b) => lo + step * (b + 0.5);
  return VProfile(center(pocB), lo + step * (up + 1), lo + step * dn);
}

// ───────────────────── ICT Killzones (New York time) ─────────────────────
class Killzone {
  final String name;
  final bool prime, avoid;
  const Killzone(this.name, this.prime, this.avoid);
}

bool _usDst(DateTime utc) {
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

Killzone killzone(DateTime utc) {
  final ny = utc.add(Duration(hours: _usDst(utc) ? -4 : -5));
  final m = ny.hour * 60 + ny.minute;
  if (m >= 20 * 60) return const Killzone('جلسة آسيا', false, true);
  if (m >= 2 * 60 && m < 5 * 60) return const Killzone('كيل زون لندن', true, false);
  if (m >= 9 * 60 + 30 && m < 11 * 60) {
    return const Killzone('كيل زون نيويورك AM', true, false);
  }
  if (m >= 12 * 60 && m < 13 * 60) return const Killzone('غداء نيويورك', false, true);
  if (m >= 13 * 60 + 30 && m < 16 * 60) {
    return const Killzone('كيل زون نيويورك PM', true, false);
  }
  return const Killzone('بين الجلسات', false, false);
}
