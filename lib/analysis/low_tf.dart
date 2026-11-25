import 'alka.dart';
import 'forecast.dart';
import 'zero_one.dart';

/// الفريمات الصغيرة (1m و5m): أقل مسافة وقف مسموحة حتى لا يأكل السبريد الصفقة.
/// اختبار ذهب 2021-2026 (سبريد 0.25$): بدون هذا الحد كل المؤشرات خاسرة بعد السبريد (−0.04 إلى −0.36R)،
/// ومعه (وقف ≥ 1$ في 1m و≥ 2$ في 5m، أي 0.03% و0.06% من السعر) تصبح رابحة.
double minStopFor(String tf, double price) => switch (tf) { '1m' => price * 0.0003, '5m' => price * 0.0006, _ => 0 };

List<PastSignal> _ks(List<PastSignal> l, double m) => [for (final s in l) if ((s.entry - s.sl).abs() >= m) s];
List<PendingSetup> _kp(List<PendingSetup> l, double m) => [for (final p in l) if ((p.trigger - p.sl).abs() >= m) p];

Forecast wideForecast(Forecast f, double m) => m <= 0
    ? f
    : Forecast(
        patterns: f.patterns,
        signals: _ks(f.signals, m),
        predHits: f.predHits,
        predN: f.predN,
        predOk: f.predOk,
        next: f.next,
        pending: _kp(f.pending, m),
        ema20: f.ema20,
        ema50: f.ema50,
        ema200: f.ema200,
        liveSignal: f.liveSignal,
        indicators: f.indicators,
        liveDir: f.liveDir,
      );
AlkaResult wideAlka(AlkaResult r, double m) => m <= 0 ? r : AlkaResult(_ks(r.signals, m), _kp(r.pending, m));
ZeroResult wideZero(ZeroResult r, double m) => m <= 0 ? r : ZeroResult(_ks(r.signals, m), _kp(r.pending, m));
