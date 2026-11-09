import '../models.dart';
import '../services/settings_service.dart';
import 'backtest.dart';

class SweepRow {
  final EngineConfig cfg;
  final ModelStats train, test;
  const SweepRow(this.cfg, this.train, this.test);

  String get label {
    if (cfg.mode == 'pro') {
      return 'pro • عوامل الموقع ≥ ${cfg.minLoc}'
          '${cfg.sessionOnly ? ' • جلسات فقط' : ''}';
    }
    return 'vote • سكور ≥ ${cfg.minScore.toStringAsFixed(0)}'
        ' • توافق ≥ ${cfg.minAligned}'
        '${cfg.htfGate ? ' • بوابة الإطار الأعلى' : ''}';
  }

  bool get holdsUp =>
      train.trades >= 30 &&
      test.trades >= 15 &&
      train.avgR > 0 &&
      test.avgR > 0 &&
      test.profitFactor >= 1.1;

  String describe() {
    String f(ModelStats m) =>
        '${m.trades} صفقة • نجاح ${(m.winRate * 100).toStringAsFixed(0)}%'
        ' • PF ${m.profitFactor.toStringAsFixed(2)}'
        ' • متوسط ${m.avgR.toStringAsFixed(2)}R';
    return '$label\nتدريب: ${f(train)}\nاختبار: ${f(test)}'
        '${holdsUp ? '\n✓ مربحة في الفترتين' : ''}';
  }
}

List<EngineConfig> sweepGrid(String mode, EngineConfig base) {
  final out = <EngineConfig>[];
  if (mode == 'pro') {
    for (final ml in [1, 2, 3]) {
      for (final so in [false, true]) {
        out.add(base.copy(mode: 'pro', minLoc: ml, sessionOnly: so));
      }
    }
  } else {
    for (final sc in [25.0, 35.0, 45.0]) {
      for (final al in [3, 4, 6]) {
        for (final g in [false, true]) {
          out.add(base.copy(
              mode: 'vote', minScore: sc, minAligned: al, htfGate: g));
        }
      }
    }
  }
  return out;
}

class Sweep {
  static Future<List<SweepRow>> run({
    required List<Candle> candles,
    required List<Candle> htf,
    required MarketSymbol sym,
    required AppSettings settings,
    required String tf,
    required String mode,
    double trainFrac = 0.7,
    void Function(int done, int total)? onProgress,
  }) async {
    const win = 260;
    final split = (candles.length * trainFrac).floor();
    if (split < win + 100 || candles.length - split < 100) {
      throw Exception('البيانات قليلة لتقسيمها (تدريب/اختبار). زِد عدد الشموع.');
    }
    final train = candles.sublist(0, split);
    final test = candles.sublist(split - win);
    final grid = sweepGrid(mode, EngineConfig.current);
    final rows = <SweepRow>[];
    for (var k = 0; k < grid.length; k++) {
      final a = await BtRunner.run(
          BtRequest(train, htf, sym, settings, grid[k], tf), (_) {});
      final b = await BtRunner.run(
          BtRequest(test, htf, sym, settings, grid[k], tf), (_) {});
      rows.add(SweepRow(grid[k], a.models[1], b.models[1]));
      onProgress?.call(k + 1, grid.length);
    }
    rows.sort((x, y) {
      final vx = x.train.trades >= 30, vy = y.train.trades >= 30;
      if (vx != vy) return vx ? -1 : 1;
      return y.train.avgR.compareTo(x.train.avgR);
    });
    return rows;
  }
}
