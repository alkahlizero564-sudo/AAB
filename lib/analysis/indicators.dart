import 'dart:math' as math;
import '../models.dart';

List<double> _nans(int n) => List<double>.filled(n, double.nan);

List<double> sma(List<double> v, int p) {
  final out = _nans(v.length);
  for (var i = p - 1; i < v.length; i++) {
    double s = 0;
    var ok = true;
    for (var j = i - p + 1; j <= i; j++) {
      if (v[j].isNaN) {
        ok = false;
        break;
      }
      s += v[j];
    }
    if (ok) out[i] = s / p;
  }
  return out;
}

List<double> ema(List<double> v, int p) {
  final out = _nans(v.length);
  if (v.length < p) return out;
  double s = 0;
  for (var i = 0; i < p; i++) {
    s += v[i];
  }
  var e = s / p;
  out[p - 1] = e;
  final k = 2 / (p + 1);
  for (var i = p; i < v.length; i++) {
    e = v[i] * k + e * (1 - k);
    out[i] = e;
  }
  return out;
}

List<double> rsi(List<double> v, [int p = 14]) {
  final out = _nans(v.length);
  if (v.length <= p) return out;
  double g = 0, l = 0;
  for (var i = 1; i <= p; i++) {
    final d = v[i] - v[i - 1];
    if (d >= 0) {
      g += d;
    } else {
      l -= d;
    }
  }
  var ag = g / p, al = l / p;
  out[p] = al == 0 ? 100 : 100 - 100 / (1 + ag / al);
  for (var i = p + 1; i < v.length; i++) {
    final d = v[i] - v[i - 1];
    ag = (ag * (p - 1) + (d > 0 ? d : 0)) / p;
    al = (al * (p - 1) + (d < 0 ? -d : 0)) / p;
    out[i] = al == 0 ? 100 : 100 - 100 / (1 + ag / al);
  }
  return out;
}

class Macd {
  final List<double> line, signal, hist;
  Macd(this.line, this.signal, this.hist);
}

Macd macd(List<double> v, [int f = 12, int s = 26, int sig = 9]) {
  final n = v.length;
  final ef = ema(v, f), es = ema(v, s);
  final line = _nans(n), signal = _nans(n), hist = _nans(n);
  for (var i = 0; i < n; i++) {
    if (!ef[i].isNaN && !es[i].isNaN) line[i] = ef[i] - es[i];
  }
  final first = s - 1;
  if (n > first + sig) {
    final valid = line.sublist(first);
    final sv = ema(valid, sig);
    for (var i = 0; i < sv.length; i++) {
      signal[first + i] = sv[i];
      if (!sv[i].isNaN) hist[first + i] = line[first + i] - sv[i];
    }
  }
  return Macd(line, signal, hist);
}

class Bands {
  final List<double> upper, mid, lower;
  Bands(this.upper, this.mid, this.lower);
}

Bands bollinger(List<double> v, [int p = 20, double k = 2]) {
  final n = v.length;
  final mid = sma(v, p);
  final up = _nans(n), lo = _nans(n);
  for (var i = p - 1; i < n; i++) {
    if (mid[i].isNaN) continue;
    double sq = 0;
    for (var j = i - p + 1; j <= i; j++) {
      sq += math.pow(v[j] - mid[i], 2).toDouble();
    }
    final sd = math.sqrt(sq / p);
    up[i] = mid[i] + k * sd;
    lo[i] = mid[i] - k * sd;
  }
  return Bands(up, mid, lo);
}

List<double> atr(List<Candle> c, [int p = 14]) {
  final n = c.length;
  final out = _nans(n);
  if (n <= p) return out;
  final tr = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    tr[i] = math.max(
        c[i].high - c[i].low,
        math.max((c[i].high - c[i - 1].close).abs(),
            (c[i].low - c[i - 1].close).abs()));
  }
  double s = 0;
  for (var i = 1; i <= p; i++) {
    s += tr[i];
  }
  var a = s / p;
  out[p] = a;
  for (var i = p + 1; i < n; i++) {
    a = (a * (p - 1) + tr[i]) / p;
    out[i] = a;
  }
  return out;
}

class Stoch {
  final List<double> k, d;
  Stoch(this.k, this.d);
}

Stoch stoch(List<Candle> c, [int p = 14, int ks = 3, int ds = 3]) {
  final n = c.length;
  final raw = _nans(n);
  for (var i = p - 1; i < n; i++) {
    double hh = -double.infinity, ll = double.infinity;
    for (var j = i - p + 1; j <= i; j++) {
      hh = math.max(hh, c[j].high);
      ll = math.min(ll, c[j].low);
    }
    raw[i] = hh == ll ? 50 : (c[i].close - ll) / (hh - ll) * 100;
  }
  final k = sma(raw, ks);
  return Stoch(k, sma(k, ds));
}

class AdxResult {
  final List<double> adx, plus, minus;
  AdxResult(this.adx, this.plus, this.minus);
}

AdxResult adxCalc(List<Candle> c, [int p = 14]) {
  final n = c.length;
  final adxV = _nans(n), pdi = _nans(n), mdi = _nans(n);
  if (n < 2 * p + 1) return AdxResult(adxV, pdi, mdi);
  final tr = List<double>.filled(n, 0);
  final pdm = List<double>.filled(n, 0);
  final mdm = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final up = c[i].high - c[i - 1].high;
    final dn = c[i - 1].low - c[i].low;
    pdm[i] = (up > dn && up > 0) ? up : 0;
    mdm[i] = (dn > up && dn > 0) ? dn : 0;
    tr[i] = math.max(
        c[i].high - c[i].low,
        math.max((c[i].high - c[i - 1].close).abs(),
            (c[i].low - c[i - 1].close).abs()));
  }
  double str = 0, sp = 0, sm = 0;
  for (var i = 1; i <= p; i++) {
    str += tr[i];
    sp += pdm[i];
    sm += mdm[i];
  }
  final dx = _nans(n);
  void calc(int i) {
    pdi[i] = str == 0 ? 0 : 100 * sp / str;
    mdi[i] = str == 0 ? 0 : 100 * sm / str;
    final s = pdi[i] + mdi[i];
    dx[i] = s == 0 ? 0 : 100 * (pdi[i] - mdi[i]).abs() / s;
  }

  calc(p);
  for (var i = p + 1; i < n; i++) {
    str = str - str / p + tr[i];
    sp = sp - sp / p + pdm[i];
    sm = sm - sm / p + mdm[i];
    calc(i);
  }
  double a = 0;
  for (var i = p; i < 2 * p; i++) {
    a += dx[i];
  }
  a /= p;
  adxV[2 * p - 1] = a;
  for (var i = 2 * p; i < n; i++) {
    a = (a * (p - 1) + dx[i]) / p;
    adxV[i] = a;
  }
  return AdxResult(adxV, pdi, mdi);
}

List<double> cci(List<Candle> c, [int p = 20]) {
  final n = c.length;
  final out = _nans(n);
  final tp = c.map((e) => (e.high + e.low + e.close) / 3).toList();
  final m = sma(tp, p);
  for (var i = p - 1; i < n; i++) {
    double md = 0;
    for (var j = i - p + 1; j <= i; j++) {
      md += (tp[j] - m[i]).abs();
    }
    md /= p;
    out[i] = md == 0 ? 0 : (tp[i] - m[i]) / (0.015 * md);
  }
  return out;
}

List<double> williamsR(List<Candle> c, [int p = 14]) {
  final n = c.length;
  final out = _nans(n);
  for (var i = p - 1; i < n; i++) {
    double hh = -double.infinity, ll = double.infinity;
    for (var j = i - p + 1; j <= i; j++) {
      hh = math.max(hh, c[j].high);
      ll = math.min(ll, c[j].low);
    }
    out[i] = hh == ll ? -50 : (hh - c[i].close) / (hh - ll) * -100;
  }
  return out;
}
