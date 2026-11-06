import '../models.dart';

const Map<String, String> categoryAr = {
  'major': 'رئيسية',
  'minor': 'فرعية',
  'exotic': 'نادرة',
  'metal': 'معادن',
  'crypto': 'كريبتو',
  'stock': 'أسهم',
};

const Map<String, String> _cur = {
  'USD': 'دولار أمريكي', 'EUR': 'يورو', 'GBP': 'جنيه إسترليني',
  'JPY': 'ين ياباني', 'CHF': 'فرنك سويسري', 'AUD': 'دولار أسترالي',
  'CAD': 'دولار كندي', 'NZD': 'دولار نيوزيلندي', 'TRY': 'ليرة تركية',
  'ZAR': 'راند جنوب أفريقي', 'MXN': 'بيزو مكسيكي', 'SEK': 'كرونة سويدية',
  'NOK': 'كرونة نرويجية', 'DKK': 'كرونة دنماركية', 'PLN': 'زلوتي بولندي',
  'HUF': 'فورنت مجري', 'CZK': 'كورونا تشيكية', 'SGD': 'دولار سنغافوري',
  'HKD': 'دولار هونغ كونغ', 'CNH': 'يوان صيني', 'INR': 'روبية هندية',
  'THB': 'بات تايلندي', 'SAR': 'ريال سعودي', 'AED': 'درهم إماراتي',
  'EGP': 'جنيه مصري',
};

MarketSymbol _fx(String code, String cat) {
  final p = code.split('/');
  final quote = p[1];
  final dec = (quote == 'JPY' || quote == 'HUF' || quote == 'INR' ||
          quote == 'THB' || quote == 'CZK')
      ? 3
      : 5;
  return MarketSymbol(code, '${_cur[p[0]]} / ${_cur[p[1]]}', cat,
      'FX:${p[0]}${p[1]}', dec, true);
}

final List<MarketSymbol> allSymbols = [
  for (final s in ['EUR/USD', 'GBP/USD', 'USD/JPY', 'USD/CHF', 'AUD/USD', 'USD/CAD', 'NZD/USD'])
    _fx(s, 'major'),
  for (final s in [
    'EUR/GBP', 'EUR/JPY', 'EUR/CHF', 'EUR/AUD', 'EUR/CAD', 'EUR/NZD',
    'GBP/JPY', 'GBP/CHF', 'GBP/AUD', 'GBP/CAD', 'GBP/NZD',
    'AUD/JPY', 'AUD/CHF', 'AUD/CAD', 'AUD/NZD',
    'CAD/JPY', 'CAD/CHF', 'CHF/JPY', 'NZD/JPY', 'NZD/CHF', 'NZD/CAD',
  ])
    _fx(s, 'minor'),
  for (final s in [
    'USD/TRY', 'USD/ZAR', 'USD/MXN', 'USD/SEK', 'USD/NOK', 'USD/DKK',
    'USD/PLN', 'USD/HUF', 'USD/CZK', 'USD/SGD', 'USD/HKD', 'USD/CNH',
    'USD/INR', 'USD/THB', 'USD/SAR', 'USD/AED', 'USD/EGP',
    'EUR/TRY', 'EUR/PLN', 'EUR/SEK', 'EUR/NOK', 'EUR/HUF', 'GBP/ZAR',
  ])
    _fx(s, 'exotic'),
  const MarketSymbol('XAU/USD', 'الذهب / دولار', 'metal', 'OANDA:XAUUSD', 2, true),
  const MarketSymbol('XAG/USD', 'الفضة / دولار', 'metal', 'OANDA:XAGUSD', 3, true),
  const MarketSymbol('XPT/USD', 'البلاتين / دولار', 'metal', 'OANDA:XPTUSD', 2, false),
  const MarketSymbol('XPD/USD', 'البلاديوم / دولار', 'metal', 'OANDA:XPDUSD', 2, false),
  const MarketSymbol('BTC/USD', 'بيتكوين', 'crypto', 'COINBASE:BTCUSD', 2, false),
  const MarketSymbol('ETH/USD', 'إيثريوم', 'crypto', 'COINBASE:ETHUSD', 2, false),
  const MarketSymbol('XRP/USD', 'ريبل', 'crypto', 'COINBASE:XRPUSD', 4, false),
  const MarketSymbol('SOL/USD', 'سولانا', 'crypto', 'COINBASE:SOLUSD', 2, false),
  const MarketSymbol('LTC/USD', 'لايتكوين', 'crypto', 'COINBASE:LTCUSD', 2, false),
  const MarketSymbol('AAPL', 'أبل', 'stock', 'NASDAQ:AAPL', 2, false),
  const MarketSymbol('MSFT', 'مايكروسوفت', 'stock', 'NASDAQ:MSFT', 2, false),
  const MarketSymbol('GOOGL', 'ألفابت (جوجل)', 'stock', 'NASDAQ:GOOGL', 2, false),
  const MarketSymbol('AMZN', 'أمازون', 'stock', 'NASDAQ:AMZN', 2, false),
  const MarketSymbol('TSLA', 'تسلا', 'stock', 'NASDAQ:TSLA', 2, false),
  const MarketSymbol('NVDA', 'إنفيديا', 'stock', 'NASDAQ:NVDA', 2, false),
  const MarketSymbol('META', 'ميتا', 'stock', 'NASDAQ:META', 2, false),
  const MarketSymbol('NFLX', 'نتفليكس', 'stock', 'NASDAQ:NFLX', 2, false),
  const MarketSymbol('AMD', 'إيه إم دي', 'stock', 'NASDAQ:AMD', 2, false),
  const MarketSymbol('JPM', 'جي بي مورغان', 'stock', 'NYSE:JPM', 2, false),
  const MarketSymbol('KO', 'كوكاكولا', 'stock', 'NYSE:KO', 2, false),
  const MarketSymbol('DIS', 'ديزني', 'stock', 'NYSE:DIS', 2, false),
];

MarketSymbol symbolByCode(String code) =>
    allSymbols.firstWhere((s) => s.code == code, orElse: () => allSymbols.first);
