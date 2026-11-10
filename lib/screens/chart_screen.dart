import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../analysis/forecast.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/native_chart.dart';
import '../widgets/signal_card.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});
  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final layers = ChartLayers();

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: FilterChip(
          label: Text(label, style: TextStyle(fontSize: 11, color: on ? Colors.white : AppColors.muted)),
          selected: on,
          onSelected: (_) => setState(tap),
          selectedColor: AppColors.accent,
          backgroundColor: AppColors.card,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: AppColors.border),
        ),
      );

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
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: TfChips(),
      ),
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          children: [
            _chip('توصيات', layers.sigs, () => layers.sigs = !layers.sigs),
            _chip('توقع', layers.fc, () => layers.fc = !layers.fc),
            _chip('أنماط الشموع', layers.pats, () => layers.pats = !layers.pats),
            _chip('EMA 20/50/200', layers.ema, () => layers.ema = !layers.ema),
            _chip('Fib', layers.fib, () => layers.fib = !layers.fib),
            _chip('Volume Profile', layers.vp, () => layers.vp = !layers.vp),
            _chip('مناطق OB/FVG', layers.zones, () => layers.zones = !layers.zones),
            _chip('VWAP', layers.vwap, () => layers.vwap = !layers.vwap),
            _chip('Chandelier', layers.ce, () => layers.ce = !layers.ce),
            _chip('مستويات', layers.levels, () => layers.levels = !layers.levels),
          ],
        ),
      ),
      Expanded(
        child: NativeChart(
          candles: st.candles,
          signal: s,
          forecast: st.forecast,
          sym: st.symbol,
          tf: st.tf,
          layers: layers,
        ),
      ),
      if (st.forecast != null && layers.fc) _forecastBar(st.forecast!, st.symbol),
      if (s != null) _bottomBar(s, st.symbol),
    ]);
  }

  Widget _forecastBar(Forecast f, MarketSymbol sym) {
    final nb = f.next;
    final lines = <Widget>[];
    if (f.liveSignal.isNotEmpty) {
      lines.add(Text('⚡ ${f.liveSignal}',
          style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700)));
    }
    if (nb != null) {
      final up = nb.pUp >= 0.5;
      final pct = ((up ? nb.pUp : 1 - nb.pUp) * 100).toStringAsFixed(0);
      lines.add(Text(
          nb.clear
              ? 'الشمعة القادمة: ${up ? '▲ صعود' : '▼ هبوط'} $pct% (من ${nb.sample} حالة مشابهة) — ${nb.why}'
              : 'الشمعة القادمة: غير واضحة (لا ميزة إحصائية) — ${nb.why}',
          style: TextStyle(
              color: !nb.clear ? AppColors.muted : (up ? AppColors.up : AppColors.down),
              fontSize: 11)));
    }
    for (final p in f.pending) {
      lines.add(Text(
          '⏳ ${p.cond} ${sym.fmt(p.trigger)} • وقف ${sym.fmt(p.sl)} • هدف ${sym.fmt(p.tp1)} / ${sym.fmt(p.tp2)}',
          style: TextStyle(color: p.dir > 0 ? AppColors.up : AppColors.down, fontSize: 11)));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
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
