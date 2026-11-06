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

class TradeSignal {
  final Direction direction;
  final double score; // -100..100
  final double price, entry, stopLoss, tp1, tp2, atr;
  final List<IndicatorVote> votes;
  final List<PatternHit> patterns;
  final List<String> reasons;
  final int htfTrend; // +1 / 0 / -1
  final DateTime time;
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
    required this.atr,
    required this.votes,
    required this.patterns,
    required this.reasons,
    required this.htfTrend,
    required this.time,
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
  String fmt(double v) => v.toStringAsFixed(decimals);
}
