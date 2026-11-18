import 'dart:math' as math;
import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';
import 'indicators.dart';
import 'sm_indicator.dart';

/// مؤشر ST: نموذج تعلّم من 8395 إشارة Mp على الذهب والبيتكوين (2016-2020)،
/// يعطي كل إشارة Mp درجة ثقة، ولا يُظهر إلا أعلى 30% منها.
/// مختبر على بيانات لم يرها: ذهب وبيتكوين 2021-2026 + 26 سوقاً:
///  - إدارة التطبيق: 82.6% (مثل KM 82.7%) بضعف صفقاته وضعف ربحه، رابح في 26/26 (KM 20/26).
///  - 1R ثم 2R: 58.9% (Mp 57.1% ، SM 58.2% ، KM 61.8%).
/// كل الخصائص من الشموع المغلقة حتى شمعة الإشارة (لا ينظر للمستقبل).

const _mu = [
  1.0325467775996149, -0.12972416484240565, 0.11995235259082651, 0.13496128648004577,
  -0.019531683163944918, 0.02133463009569931, 0.4162371196069981, -0.01647880830546077,
  -0.46587991790097183, -0.0256588349980249, 0.20774270399046613, 0.6110780226325851,
  0.18117927337700665, 0.800659573856181,
];
const _sd = [
  0.28334118633115407, 1.1008147068086753, 0.9426817900691559, 0.9898886587715814,
  0.7154780195392539, 0.6980362120224923, 0.33704045860089515, 0.21861477704651266,
  1.0703344938791461, 2.6887227322501195, 0.405691599297554, 0.48750556290473435,
  0.38516664581180704, 0.33634548655226454,
];
const _w = [
  -0.029352514761688136, 0.028556854951703736, 0.011226636009344147, 0.04256433681719648,
  -0.020394683068186342, -0.004036329483256483, -0.040700922954852795, -0.023102055620983556,
  -0.02185710341514212, 0.027089443118025833, 0.0037933461852805903, 0.0005069230893657793,
  -0.0046371006577262, -0.0906499229547533,
];
const _bias = 0.19928948355510054;

/// حد أعلى 30% من إشارات التدريب
const stThreshold = 0.5648245769585736;

class StResult {
  final AllResult res;
  final Map<int, double> conf; // شمعة الإشارة → احتمال النجاح المقدّر
  const StResult(this.res, this.conf);
  static const empty = StResult(AllResult([], [], [], [], 'ST'), {});
}

/// يحسب درجة ثقة ST لإشارات في الشموع [c].
class StScorer {
  final List<Candle> c;
  late final List<double> _at, _atm, _e20, _rs;
  late final List<int> _rd, _htf;
  StScorer(this.c) {
    final n = c.length;
    _at = atr(c, 14);
    _atm = sma(_at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
    final cl = [for (final k in c) k.close];
    _e20 = ema(cl, 20);
    _rs = rsi(cl, 14);
    _rd = smDirFast(smRibbon(c), n);
    final gaps = [for (var i = 1; i < math.min(n, 400); i++) c[i].time.difference(c[i - 1].time).inMinutes.abs()]..sort();
    final baseMin = gaps.isEmpty ? 60 : gaps[gaps.length ~/ 2];
    _htf = htfTrend(c, baseMin < 60 ? 60 : baseMin < 240 ? 240 : baseMin < 1440 ? 1440 : 10080);
  }

  double score(int i, int d, String src) {
    if (i < 0 || i >= c.length) return 0;
    final k = c[i];
    final a = _at[i].isNaN ? (k.high - k.low) : _at[i];
    if (!(a > 0)) return 0;
    final rng = math.max(1e-9, k.high - k.low);
    double ret(int b) => i - b >= 0 ? (k.close - c[i - b].close) * d / a : 0;
    final h = k.time.toUtc().hour;
    final f = [
      _atm[i] > 0 && !_at[i].isNaN ? _at[i] / _atm[i] : 1.0,
      _e20[i].isNaN ? 0.0 : (k.close - _e20[i]) * d / a,
      _rd[i] == d ? 1.0 : (_rd[i] == 0 ? 0.0 : -1.0),
      _htf[i] == d ? 1.0 : (_htf[i] == 0 ? 0.0 : -1.0),
      math.sin(2 * math.pi * h / 24),
      math.cos(2 * math.pi * h / 24),
      (k.close - k.open) * d / rng,
      _rs[i].isNaN ? 0.0 : (_rs[i] - 50) * d / 50,
      ret(5),
      ret(20),
      src == 'AAB' ? 1.0 : 0.0,
      src == 'Alka' ? 1.0 : 0.0,
      src == 'AAB' || src == 'Alka' ? 0.0 : 1.0,
      rng / a,
    ];
    var s = _bias;
    for (var j = 0; j < f.length; j++) {
      s += _w[j] * ((f[j] - _mu[j]) / _sd[j]).clamp(-5.0, 5.0);
    }
    return 1 / (1 + math.exp(-s));
  }
}

/// مؤشر ST: إشارات Mp ذات الثقة العالية فقط.
StResult buildSt(List<Candle> c, AllResult mp) {
  if (c.length < 120) return StResult.empty;
  final sc = StScorer(c);
  final conf = <int, double>{};
  final sigs = <PastSignal>[], src = <String>[];
  for (final (q, s) in mp.signals.indexed) {
    final p = sc.score(s.i, s.dir, mp.sources[q]);
    if (p >= stThreshold) {
      sigs.add(s);
      src.add(mp.sources[q]);
      conf[s.i] = p;
    }
  }
  final pend = <PendingSetup>[], pSrc = <String>[];
  for (final (q, p) in mp.pending.indexed) {
    final pr = sc.score(p.i, p.dir, mp.pendingSrc[q]);
    if (p.i >= 0 && pr >= stThreshold) {
      pend.add(p);
      pSrc.add(mp.pendingSrc[q]);
      conf[p.i] = pr;
    }
  }
  final openDirs = {for (final x in sigs) if (x.exitI < 0) x.dir};
  return StResult(AllResult(sigs, src, [for (final p in pend) if (!openDirs.contains(p.dir)) p], [for (final (q, p) in pend.indexed) if (!openDirs.contains(p.dir)) pSrc[q]], 'ST'), conf);
}
