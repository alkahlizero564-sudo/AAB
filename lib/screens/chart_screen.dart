import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../analysis/indicators.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/signal_card.dart';

const _lwHtml = r'''<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html,body{margin:0;height:100%;background:#0B1220;overflow:hidden}
#c{position:absolute;inset:0}
#o{position:absolute;left:0;top:0;pointer-events:none}
</style>
<script src="https://unpkg.com/lightweight-charts@4.1.3/dist/lightweight-charts.standalone.production.js"></script>
</head><body><div id="c"></div><canvas id="o"></canvas><script>
const dpr = window.devicePixelRatio || 1;
const chart = LightweightCharts.createChart(document.getElementById('c'), {
  width: innerWidth, height: innerHeight,
  layout: { background: { color: '#0B1220' }, textColor: '#9FB0C8' },
  grid: { vertLines: { color: '#162036' }, horzLines: { color: '#162036' } },
  timeScale: { timeVisible: true, secondsVisible: false, borderColor: '#223152', rightOffset: 6 },
  rightPriceScale: { borderColor: '#223152' },
  crosshair: { mode: 0 }
});
const series = chart.addCandlestickSeries({
  upColor: '#16C784', downColor: '#EA3943', borderVisible: false,
  wickUpColor: '#16C784', wickDownColor: '#EA3943'
});
const ceL = chart.addLineSeries({ color: '#16C784', lineWidth: 2, priceLineVisible: false, lastValueVisible: false });
const ceS = chart.addLineSeries({ color: '#EA3943', lineWidth: 2, priceLineVisible: false, lastValueVisible: false });
const e50 = chart.addLineSeries({ color: '#4C8DFF', lineWidth: 1, priceLineVisible: false, lastValueVisible: false });
const cv = document.getElementById('o');
const ctx = cv.getContext('2d');
let lines = [], zones = [], curKey = '', n = 0, firstTs = 0;

function sizeAll() {
  chart.applyOptions({ width: innerWidth, height: innerHeight });
  cv.width = innerWidth * dpr; cv.height = innerHeight * dpr;
  cv.style.width = innerWidth + 'px'; cv.style.height = innerHeight + 'px';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  draw();
}
function draw() {
  ctx.clearRect(0, 0, innerWidth, innerHeight);
  let pw = 60;
  try { pw = chart.priceScale('right').width(); } catch (e) {}
  const right = innerWidth - pw;
  const ts = chart.timeScale();
  zones.forEach(z => {
    const y1 = series.priceToCoordinate(z.top), y2 = series.priceToCoordinate(z.bottom);
    if (y1 === null || y2 === null) return;
    let x1 = ts.timeToCoordinate(z.t1);
    if (x1 === null) x1 = 0;
    if (x1 > right) return;
    const h = Math.max(Math.abs(y2 - y1), 2), y = Math.min(y1, y2);
    ctx.fillStyle = z.fill; ctx.fillRect(x1, y, right - x1, h);
    ctx.strokeStyle = z.line; ctx.lineWidth = 1;
    ctx.strokeRect(x1 + 0.5, y + 0.5, right - x1 - 1, h - 1);
    ctx.fillStyle = z.line; ctx.font = '10px sans-serif';
    ctx.fillText(z.label, Math.max(x1, 0) + 4, y + 10);
  });
}
setInterval(draw, 250);
chart.timeScale().subscribeVisibleLogicalRangeChange(draw);
window.addEventListener('resize', sizeAll);
sizeAll();

function clearAll() {
  series.setData([]); ceL.setData([]); ceS.setData([]); e50.setData([]);
  lines.forEach(l => series.removePriceLine(l)); lines = [];
  series.setMarkers([]); zones = []; curKey = ''; n = 0; firstTs = 0; draw();
}
function push(key, c, l, s, e, lv, zs, mk) {
  if (key !== curKey) {
    series.setData(c);
    chart.timeScale().fitContent();
    curKey = key; n = c.length; firstTs = c[0].time;
  } else if (n === c.length && firstTs === c[0].time) {
    series.update(c[c.length - 1]);
  } else {
    series.setData(c); n = c.length; firstTs = c[0].time;
  }
  ceL.setData(l); ceS.setData(s); e50.setData(e);
  lines.forEach(x => series.removePriceLine(x)); lines = [];
  lv.forEach(o => lines.push(series.createPriceLine({
    price: o.p, color: o.c, lineWidth: o.w || 2, lineStyle: o.s || 2,
    axisLabelVisible: true, title: o.t
  })));
  mk.sort((a, b) => a.time - b.time);
  try { series.setMarkers(mk); } catch (err) {}
  zones = zs; draw();
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
  int mode = 0; // 0 = analysis chart (zones + levels), 1 = TradingView widget
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

  num? _n(double v) => v.isNaN || v.isInfinite ? null : v;

  void _push() {
    if (!_ready || _st.candles.isEmpty) return;
    final src = _st.candles;
    final s = _st.signal;
    final cl = src.map((e) => e.close).toList();
    final e50 = ema(cl, 50);

    final cj = <Map<String, dynamic>>[];
    final lj = <Map<String, dynamic>>[];
    final sj = <Map<String, dynamic>>[];
    final ej = <Map<String, dynamic>>[];
    var lastTs = -1;
    for (var i = 0; i < src.length; i++) {
      final x = src[i];
      if (x.ts <= lastTs) continue;
      lastTs = x.ts;
      cj.add({'time': x.ts, 'open': x.open, 'high': x.high, 'low': x.low, 'close': x.close});
      final l = (s != null && i < s.ceLong.length) ? _n(s.ceLong[i]) : null;
      final sh = (s != null && i < s.ceShort.length) ? _n(s.ceShort[i]) : null;
      lj.add(l == null ? {'time': x.ts} : {'time': x.ts, 'value': l});
      sj.add(sh == null ? {'time': x.ts} : {'time': x.ts, 'value': sh});
      final e = _n(e50[i]);
      ej.add(e == null ? {'time': x.ts} : {'time': x.ts, 'value': e});
    }

    final levels = <Map<String, dynamic>>[];
    final zones = <Map<String, dynamic>>[];
    final markers = <Map<String, dynamic>>[];
    if (s != null) {
      if (s.direction != Direction.neutral) {
        final buy = s.direction == Direction.buy;
        levels.addAll([
          {'p': s.entry, 'c': '#B0B8C8', 't': 'ENTRY'},
          {'p': s.stopLoss, 'c': '#EA3943', 't': 'SL'},
          {'p': s.tp1, 'c': '#16C784', 't': 'TP1'},
          {'p': s.tp2, 'c': '#16C784', 't': 'TP2'},
          {'p': s.tp3, 'c': '#16C784', 't': 'TP3'},
        ]);
        markers.add({
          'time': src.last.ts,
          'position': buy ? 'belowBar' : 'aboveBar',
          'color': buy ? '#16C784' : '#EA3943',
          'shape': buy ? 'arrowUp' : 'arrowDown',
          'text': buy ? 'BUY' : 'SELL',
        });
      }
      if (!s.equilibrium.isNaN) {
        levels.add({'p': s.equilibrium, 'c': '#7B8BA8', 't': '50%', 'w': 1, 's': 3});
      }
      if (!s.poc.isNaN) {
        levels.add({'p': s.poc, 'c': '#A06BFF', 't': 'POC', 'w': 1, 's': 3});
      }
      final first = src.first.ts;
      for (final z in s.zones) {
        String fill, line;
        if (z.kind == 'FVG') {
          fill = 'rgba(245,166,35,0.16)';
          line = '#F5A623';
        } else if (z.kind == 'SR') {
          fill = z.bias > 0 ? 'rgba(76,141,255,0.20)' : 'rgba(255,120,80,0.20)';
          line = z.bias > 0 ? '#4C8DFF' : '#FF7850';
        } else if (z.kind == 'EQH' || z.kind == 'EQL') {
          fill = 'rgba(200,200,220,0.18)';
          line = '#C8C8DC';
        } else {
          fill = z.bias > 0 ? 'rgba(22,199,132,0.18)' : 'rgba(234,57,67,0.18)';
          line = z.bias > 0 ? '#16C784' : '#EA3943';
        }
        zones.add({
          't1': math.max(z.t1, first),
          'top': z.top,
          'bottom': z.bottom,
          'fill': fill,
          'line': line,
          'label': z.label,
        });
      }
      final times = cj.map((e) => e['time'] as int).toSet();
      for (final m in s.marks) {
        if (!times.contains(m.ts)) continue;
        markers.add({
          'time': m.ts,
          'position': m.bias > 0 ? 'belowBar' : 'aboveBar',
          'color': m.bias > 0 ? '#16C784' : '#EA3943',
          'shape': m.bias > 0 ? 'arrowUp' : 'arrowDown',
          'text': m.text,
        });
      }
    }
    _pushedTick = _st.tick;
    _wc.runJavaScript('push(${jsonEncode(_key)},${jsonEncode(cj)},${jsonEncode(lj)},'
        '${jsonEncode(sj)},${jsonEncode(ej)},${jsonEncode(levels)},'
        '${jsonEncode(zones)},${jsonEncode(markers)})');
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
          const SizedBox(width: 8),
          const Flexible(child: LiveBadge()),
          const Spacer(),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('تحليل')),
              ButtonSegment(value: 1, label: Text('TV')),
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
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(v,
                  style: TextStyle(
                      color: c, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: col.withOpacity(0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(dirLabel(s.direction),
              style: TextStyle(
                  color: col, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        const SizedBox(width: 6),
        if (active) ...[
          item('دخول', sym.fmt(s.entry), AppColors.accent),
          item('وقف', sym.fmt(s.stopLoss), AppColors.down),
          item('TP1', sym.fmt(s.tp1), AppColors.up),
          item('TP2', sym.fmt(s.tp2), AppColors.up),
          item('TP3', sym.fmt(s.tp3), AppColors.up),
        ] else
          const Expanded(
              child: Text('لا توجد صفقة — انتظر',
                  style: TextStyle(color: AppColors.muted, fontSize: 12))),
      ]),
    );
  }
} 
