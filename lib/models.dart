class Candle {
  final DateTime time; // UTC
  final double open, high, low, close, volume;
  const Candle(this.time, this.open, this.high, this.low, this.close,
      [this.volume = 0]);
  int get ts => time.millisecondsSinceEpoch ~/ 1000;
}

enum Direction { buy, sell, neutral }

class IndicatorVote {
  final String name;
  final String value;
  final int vote; // +1 / 0 / -1
  const IndicatorVote(this.name, this.value, this.vote);
}

class PatternHit {
  final String en, ar;
  final int bias; // +1 bullish, -1 bearish, 0 neutral
  final double weight;
  const PatternHit(this.en, this.ar, this.bias, this.weight);
}

/// A price zone drawn on the chart (Order Block, FVG, S/R, EQH/EQL).
class Zone {
  final String kind; // OB, FVG, SR, EQH, EQL
  final int bias; // +1 bullish/demand, -1 bearish/supply
  final double top, bottom;
  final int t1; // start time (unix seconds)
  final String label;
  const Zone(this.kind, this.bias, this.top, this.bottom, this.t1, this.label);
}

class ChartMark {
  final int ts;
  final int bias; // +1 / -1
  final String text;
  const ChartMark(this.ts, this.bias, this.text);
}

class Tick {
  final String symbol;
  final double price;
  final DateTime time;
  const Tick(this.symbol, this.price, this.time);
}

class TradeSignal {
  final Direction direction;
  final double score; // -100..100
  final double price, entry, stopLoss, tp1, tp2, tp3, atr;
  final List<IndicatorVote> votes;
  final List<PatternHit> patterns;
  final List<String> reasons;
  final int htfTrend; // +1 / 0 / -1
  final DateTime time;
  final String grade; // A / B / C
  final int aligned; // number of aligned core confluences
  final String killzone;
  final List<Zone> zones;
  final List<ChartMark> marks;
  final List<double> ceLong, ceShort; // NaN where hidden (aligned to candles)
  final double equilibrium; // NaN when unknown
  final double poc; // NaN when unknown
  String? aiVerdict; // BUY / SELL / WAIT
  String? aiComment;

  TradeSignal({
    required this.direction,
    required this.score,
    required this.price,
    required this.entry,
    required this.stopLoss,
    required this.tp1,
    required this.tp2,
    this.tp3 = 0,
    required this.atr,
    required this.votes,
    required this.patterns,
    required this.reasons,
    required this.htfTrend,
    required this.time,
    this.grade = 'C',
    this.aligned = 0,
    this.killzone = '',
    this.zones = const [],
    this.marks = const [],
    this.ceLong = const [],
    this.ceShort = const [],
    this.equilibrium = double.nan,
    this.poc = double.nan,
  });

  double get strength => score.abs().clamp(0, 100).toDouble();

  int get agree {
    final d = direction == Direction.buy ? 1 : (direction == Direction.sell ? -1 : 0);
    if (d == 0) return 0;
    return votes.where((v) => v.vote == d).length;
  }

  int get total => votes.where((v) => v.vote != 0).length;
}

class NewsItem {
  final String title, source, url, summary;
  final DateTime time;
  const NewsItem(this.title, this.source, this.url, this.summary, this.time);
}

class MarketSymbol {
  final String code; // Twelve Data symbol, e.g. EUR/USD
  final String name; // Arabic display name
  final String category; // major, minor, exotic, metal, crypto, stock
  final String tv; // TradingView symbol
  final int decimals;
  final bool tiingo; // supported by Tiingo FX endpoint
  const MarketSymbol(
      this.code, this.name, this.category, this.tv, this.decimals, this.tiingo);

  String get tiingoTicker => code.replaceAll('/', '').toLowerCase();
  bool get isFx =>
      category == 'major' ||
      category == 'minor' ||
      category == 'exotic' ||
      category == 'metal';
  String fmt(double v) => v.toStringAsFixed(decimals);
} 
