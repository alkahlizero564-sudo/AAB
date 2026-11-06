import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../analysis/indicators.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _lwHtml = r'''<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;height:100%;background:#0B1220;overflow:hidden}#c{position:absolute;inset:0}</style>
<script src="https://unpkg.com/lightweight-charts@4.1.3/dist/lightweight-charts.standalone.production.js"></script>
</head><body><div id="c"></div><script>
const chart = LightweightCharts.createChart(document.getElementById('c'), {
  width: innerWidth, height: innerHeight,
  layout: { background: { color: '#0B1220' }, textColor: '#9FB0C8' },
  grid: { vertLines: { color: '#162036' }, horzLines: { color: '#162036' } },
  timeScale: { timeVisible: true, secondsVisible: false, borderColor: '#223152' },
  rightPriceScale: { borderColor: '#223152' },
  crosshair: { mode: 0 }
});
const series = chart.addCandlestickSeries({
  upColor: '#16C784', downColor: '#EA3943', borderVisible: false,
  wickUpColor: '#16C784', wickDownColor: '#EA3943'
});
const e20 = chart.addLineSeries({ color: '#F5A623', lineWidth: 1, priceLineVisible: false, lastValueVisible: false });
const e50 = chart.addLineSeries({ color: '#4C8DFF', lineWidth: 1, priceLineVisible: false, lastValueVisible: false });
let lines = [], curKey = '', n = 0, firstTs = 0;
function resize(){ chart.applyOptions({ width: innerWidth, height: innerHeight }); }
window.addEventListener('resize', resize);
function clearAll(){
  series.setData([]); e20.setData([]); e50.setData([]);
  lines.forEach(l => series.removePriceLine(l)); lines = []; series.setMarkers([]);
  curKey = ''; n = 0; firstTs = 0;
}
function push(key, c, a, b, lv, mk){
  if (key !== curKey) {
    series.setData(c); e20.setData(a); e50.setData(b);
    chart.timeScale().fitContent();
    curKey = key; n = c.length; firstTs = c[0].time;
  } else if (n === c.length && firstTs === c[0].time) {
    series.update(c[c.length - 1]);
    if (a.length) e20.update(a[a.length - 1]);
    if (b.length) e50.update(b[b.length - 1]);
  } else {
    series.setData(c); e20.setData(a); e50.setData(b);
    n = c.length; firstTs = c[0].time;
  }
  lines.forEach(l => series.removePriceLine(l)); lines = [];
  lv.forEach(o => lines.push(series.createPriceLine({
    price: o.p, color: o.c, lineWidth: 2, lineStyle: 2, axisLabelVisible: true, title: o.t
  })));
  series.setMarkers(mk);
}
</script></body></html>''';

String _tvHtml(String symbol, String tf) {
  const map = {
    '1m': '1', '5m': '5', '15m': '15', '30m': '30',
    '1h': '60', '4h': '240', '1d': 'D',
  };
  return '''<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;height:100%;background:#0B1220}</style></head><body>
<div id="tv" style="height:100%;width:100%"></div>
<script src="https://s3.tradingview.com/tv.js"></script>
<script>
new TradingView.widget({
  autosize: true, symbol: "$symbol", interval: "${map[tf]}",
  timezone: "Etc/UTC", theme: "dark", style: "1", locale: "ar_AE",
  toolbar_bg: "#0B1220", enable_publishing: false, allow_symbol_change: true,
  studies: ["RSI@tv-basicstudies", "MACD@tv-basicstudies"],
  container_id: "tv"
});
</script></body></html>''';
}

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});
  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late final WebViewController _wc;
  late final AppState _st;
  int mode = 0; // 0 = analysis chart (levels), 1 = TradingView widget
  bool _ready = false;
  String _loadedKey = '';
  int _pushedTick = -1;

  @override
  void initState() {
    super.initState();
    _st = context.read<AppState>();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        _ready = mode == 0;
        if (_ready) _push();
      }));
    _load();
    _st.addListener(_onState);
  }

  @override
  void dispose() {
    _st.removeListener(_onState);
    super.dispose();
  }

  String get _key => '${_st.symbol.code}|${_st.tf}';

  void _load() {
    _ready = false;
    _pushedTick = -1;
    _loadedKey = _key;
    _wc.loadHtmlString(
      mode == 0 ? _lwHtml : _tvHtml(_st.symbol.tv, _st.tf),
      baseUrl: 'https://www.tradingview.com',
    );
  }

  void _onState() {
    if (!mounted) return;
    if (mode == 1 && _key != _loadedKey) {
      _load();
      return;
    }
    if (mode == 0 && _ready) {
      if (_st.candles.isEmpty) {
        _wc.runJavaScript('clearAll()');
        _pushedTick = -1;
      } else if (_st.tick != _pushedTick) {
        _push();
      }
    }
  }

  void _push() {
    if (!_ready || _st.candles.isEmpty) return;
    final c = <Candle>[];
    for (final x in _st.candles) {
      if (c.isNotEmpty && c.last.ts >= x.ts) continue;
      c.add(x);
    }
    final cl = c.map((e) => e.close).toList();
    final a = ema(cl, 20), b = ema(cl, 50);
    final cj = [
      for (final x in c)
        {'time': x.ts, 'open': x.open, 'high': x.high, 'low': x.low, 'close': x.close}
    ];
    List<Map<String, dynamic>> line(List<double> v) => [
          for (var i = 0; i < c.length; i++)
            if (!v[i].isNaN) {'time': c[i].ts, 'value': v[i]}
        ];
    final levels = <Map<String, dynamic>>[];
    final markers = <Map<String, dynamic>>[];
    final s = _st.signal;
    if (s != null && s.direction != Direction.neutral) {
      final buy = s.direction == Direction.buy;
      levels.addAll([
        {'p': s.entry, 'c': '#4C8DFF', 't': 'ENTRY'},
        {'p': s.stopLoss, 'c': '#EA3943', 't': 'SL'},
        {'p': s.tp1, 'c': '#16C784', 't': 'TP1'},
        {'p': s.tp2, 'c': '#16C784', 't': 'TP2'},
      ]);
      markers.add({
        'time': c.last.ts,
        'position': buy ? 'belowBar' : 'aboveBar',
        'color': buy ? '#16C784' : '#EA3943',
        'shape': buy ? 'arrowUp' : 'arrowDown',
        'text': buy ? 'BUY' : 'SELL',
      });
    }
    _pushedTick = _st.tick;
    _wc.runJavaScript(
        'push(${jsonEncode(_key)},${jsonEncode(cj)},${jsonEncode(line(a))},${jsonEncode(line(b))},${jsonEncode(levels)},${jsonEncode(markers)})');
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.signal;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Row(children: [
          const SymbolButton(),
          const Spacer(),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('تحليل')),
              ButtonSegment(value: 1, label: Text('TradingView')),
            ],
            selected: {mode},
            onSelectionChanged: (v) {
              setState(() => mode = v.first);
              _load();
            },
          ),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: TfChips(),
      ),
      const SizedBox(height: 6),
      Expanded(child: WebViewWidget(controller: _wc)),
      if (s != null) _bottomBar(s, st.symbol),
    ]);
  }

  Widget _bottomBar(TradeSignal s, MarketSymbol sym) {
    final col = dirColor(s.direction);
    final active = s.direction != Direction.neutral;
    Widget item(String t, String v, Color c) => Expanded(
          child: Column(children: [
            Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            const SizedBox(height: 2),
            Text(v,
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: col.withOpacity(0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(dirLabel(s.direction),
              style: TextStyle(
                  color: col, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        if (active) ...[
          item('دخول', sym.fmt(s.entry), AppColors.accent),
          item('وقف', sym.fmt(s.stopLoss), AppColors.down),
          item('هدف 1', sym.fmt(s.tp1), AppColors.up),
          item('هدف 2', sym.fmt(s.tp2), AppColors.up),
        ] else
          const Expanded(
              child: Text('لا توجد صفقة — انتظر',
                  style: TextStyle(color: AppColors.muted, fontSize: 12))),
      ]),
    );
  }
}
