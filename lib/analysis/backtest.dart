import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import '../models.dart';
import '../services/market_data_service.dart';
import '../services/settings_service.dart';
import 'signal_engine.dart';

class BtRequest {
  final List<Candle> candles;
  final List<Candle> htf;
  final MarketSymbol sym;
  final AppSettings settings;
  final EngineConfig cfg;
  final String tf;
  final int maxHold; // max candles a trade can stay open
  final double costR; // spread/commission per trade, in R
  const BtRequest(this.candles, this.htf, this.sym, this.settings, this.cfg, this.tf,
      {this.maxHold = 100, this.costR = 0.05});
}

class ModelStats {
  final String name;
  final int trades, wins;
  final double winRate, avgR, profitFactor, totalR, maxDD;
  final int maxLossStreak;
  const ModelStats(this.name, this.trades, this.wins, this.winRate, this.avgR,
      this.profitFactor, this.totalR, this.maxDD, this.maxLossStreak);
}

class IndStat {
  final String name;
  final int nAgree, nOther;
  final double rAgree, rOther;
  const IndStat(this.name, this.nAgree, this.nOther, this.rAgree, this.rOther);
  double get edge => rAgree - rOther;
}

class BtResult {
  final int bars, trades;
  final DateTime from, to;
  final List<ModelStats> models; // TP1 / TP2 / TP3 exits
  final List<ModelStats> byGrade; // TP2 model
  final List<ModelStats> byDir; // TP2 model
  final List<IndStat> inds;
  const BtResult(this.bars, this.trades, this.from, this.to, this.models,
      this.byGrade, this.byDir, this.inds);
}

class _Trade {
  final bool buy;
  final String grade;
  final List<double> rs; // R result for TP1 / TP2 / TP3 exit models
  final Map<String, int> votes; // +1 = indicator agreed with the trade
  _Trade(this.buy, this.grade, this.rs, this.votes);
}

ModelStats _stats(String name, List<double> rs) {
  final n = rs.length;
  var wins = 0, streak = 0, maxStreak = 0;
  double sw = 0, sl = 0, tot = 0, eq = 0, peak = 0, dd = 0;
  for (final r in rs) {
    tot += r;
    if (r > 0) {
      wins++;
      sw += r;
      streak = 0;
    } else {
      sl += -r;
      streak++;
      maxStreak = math.max(maxStreak, streak);
    }
    eq += r;
    peak = math.max(peak, eq);
    dd = math.max(dd, peak - eq);
  }
  final pf = sl == 0 ? (sw > 0 ? 99.0 : 0.0) : sw / sl;
  return ModelStats(name, n, wins, n == 0 ? 0 : wins / n, n == 0 ? 0 : tot / n, pf,
      tot, dd, maxStreak);
}

/// Replays the live engine candle by candle (no look-ahead): the signal is
/// computed on closed candles up to i, the entry is the NEXT candle's open.
/// If SL and a TP are touched inside the same candle, SL is assumed first.
BtResult runBacktest(BtRequest r, void Function(double) progress) {
  const win = 260;
  final c = r.candles;
  final n = c.length;
  final rr = [r.settings.rr1, r.settings.rr2, r.settings.rr3];
  final htfSecs = MarketDataService.tfMinutes[MarketDataService.higherTf[r.tf]!]! * 60;
  final trades = <_Trade>[];
  var i = win - 1, hp = 0;
  while (i < n - 2) {
    if (i % 25 == 0) progress(i / n);
    while (hp < r.htf.length && r.htf[hp].ts + htfSecs <= c[i].ts) {
      hp++;
    }
    final htfSlice = hp >= 55 ? r.htf.sublist(math.max(0, hp - 120), hp) : null;
    final sig = SignalEngine.analyze(c.sublist(i - win + 1, i + 1),
        htf: htfSlice, s: r.settings, sym: r.sym, cfg: r.cfg);
    if (sig.direction == Direction.neutral) {
      i++;
      continue;
    }
    final buy = sig.direction == Direction.buy;
    final sg = buy ? 1 : -1;
    final entry = c[i + 1].open;
    final sl = sig.stopLoss + (entry - sig.entry);
    final risk = (entry - sl).abs();
    if (risk <= 0 || (buy ? sl >= entry : sl <= entry)) {
      i++;
      continue;
    }
    final tps = [for (final m in rr) entry + sg * risk * m];
    int? slHit;
    final tpHit = <int?>[null, null, null];
    var last = i + 1;
    for (var j = i + 1; j < n && j <= i + r.maxHold; j++) {
      last = j;
      final hi = c[j].high, lo = c[j].low;
      if (buy ? lo <= sl : hi >= sl) {
        slHit = j;
        break;
      }
      for (var k = 0; k < 3; k++) {
        if (tpHit[k] == null && (buy ? hi >= tps[k] : lo <= tps[k])) tpHit[k] = j;
      }
      if (tpHit[2] != null) break;
    }
    final rs = List<double>.filled(3, 0);
    for (var k = 0; k < 3; k++) {
      if (tpHit[k] != null) {
        rs[k] = rr[k];
      } else if (slHit != null) {
        rs[k] = -1;
      } else {
        final mtm = (c[last].close - entry) * sg / risk;
        rs[k] = mtm.clamp(-1.0, rr[k]).toDouble();
      }
      rs[k] -= r.costR;
    }
    trades.add(_Trade(buy, sig.grade, rs,
        {for (final v in sig.votes) v.name: v.vote * sg}));
    i = last + 1;
  }
  progress(1);

  final models = [
    _stats('خروج عند TP1', [for (final t in trades) t.rs[0]]),
    _stats('خروج عند TP2', [for (final t in trades) t.rs[1]]),
    _stats('خروج عند TP3', [for (final t in trades) t.rs[2]]),
  ];
  final byGrade = <ModelStats>[];
  for (final g in ['A', 'B', 'C']) {
    final list = [for (final t in trades) if (t.grade == g) t.rs[1]];
    if (list.isNotEmpty) byGrade.add(_stats('درجة $g', list));
  }
  final byDir = <ModelStats>[];
  final buys = [for (final t in trades) if (t.buy) t.rs[1]];
  final sells = [for (final t in trades) if (!t.buy) t.rs[1]];
  if (buys.isNotEmpty) byDir.add(_stats('شراء', buys));
  if (sells.isNotEmpty) byDir.add(_stats('بيع', sells));

  final names = <String>{};
  for (final t in trades) {
    names.addAll(t.votes.keys);
  }
  final inds = <IndStat>[];
  for (final name in names) {
    double sa = 0, so = 0;
    var na = 0, no = 0;
    for (final t in trades) {
      if (t.votes[name] == 1) {
        na++;
        sa += t.rs[1];
      } else {
        no++;
        so += t.rs[1];
      }
    }
    if (na >= 10 && no >= 10) {
      inds.add(IndStat(name, na, no, sa / na, so / no));
    }
  }
  inds.sort((a, b) => b.edge.compareTo(a.edge));

  return BtResult(n, trades.length, c.first.time, c.last.time, models, byGrade,
      byDir, inds);
}

class BtRunner {
  static Future<BtResult> run(BtRequest req, void Function(double) onProgress) async {
    final rp = ReceivePort();
    final iso = await Isolate.spawn(_entry, [rp.sendPort, req]);
    final done = Completer<BtResult>();
    rp.listen((m) {
      if (m is double) {
        onProgress(m);
      } else if (m is BtResult) {
        if (!done.isCompleted) done.complete(m);
        rp.close();
        iso.kill();
      } else if (m is String) {
        if (!done.isCompleted) done.completeError(Exception(m));
        rp.close();
        iso.kill();
      }
    });
    return done.future;
  }
}

void _entry(List args) {
  final sp = args[0] as SendPort;
  final req = args[1] as BtRequest;
  try {
    sp.send(runBacktest(req, (p) => sp.send(p)));
  } catch (e) {
    sp.send('$e');
  }
}
