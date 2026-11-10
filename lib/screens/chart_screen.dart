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
  bool full = false; // وضع الشاشة الكاملة للشارت

  Widget _seg(List<(String, String)> items, String value, void Function(String) on) => Container(
        margin: const EdgeInsetsDirectional.only(end: 6),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (k, label) in items)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => on(k)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: value == k ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: value == k ? Colors.white : AppColors.muted,
                        fontWeight: value == k ? FontWeight.w700 : FontWeight.w400)),
              ),
            ),
        ]),
      );

  Widget _toolbar() => SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          children: [
            _seg(const [('candle', 'شموع'), ('ha', 'Heikin Ashi'), ('line', 'خطي')], layers.type,
                (v) => layers.type = v),
            _seg(const [('rsi', 'RSI'), ('macd', 'MACD'), ('none', 'بدون')], layers.sub,
                (v) => layers.sub = v),
            _seg(const [('on', 'الحجم')], layers.vol ? 'on' : '', (_) => layers.vol = !layers.vol),
            IconButton(
              tooltip: full ? 'إظهار الأدوات' : 'شاشة كاملة',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              color: AppColors.accent,
              icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: () => setState(() => full = !full),
            ),
          ],
        ),
      );

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: FilterChip(
          label: Text(label,
              style: TextStyle(fontSize: 11, color: on ? Colors.white : AppColors.muted)),
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
      if (!full) ...[
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
      ],
      _toolbar(),
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
      if (st.forecast != null) ...[
        if (!full) _forecastBar(st.forecast!, st.symbol),
        _decisionBar(st.forecast!.decision, st.symbol),
      ] else if (s != null)
        _bottomBar(s, st.symbol),
    ]);
  }

  Widget _forecastBar(Forecast f, MarketSymbol sym) {
    final nb = f.next;
    final lines = <Widget>[];
    if (layers.fc && nb != null && f.showNext) {
      final up = nb.pUp >= 0.5;
      final pct = ((up ? nb.pUp : 1 - nb.pUp) * 100).toStringAsFixed(0);
      lines.add(Text(
          'الشمعة القادمة تدعم القرار: ${up ? '▲ صعود' : '▼ هبوط'} $pct% (من ${nb.sample} حالة مشابهة)',
          style: TextStyle(color: up ? AppColors.up : AppColors.down, fontSize: 11)));
    }
    if (f.indicators.isNotEmpty) {
      final upN = f.indicators.where((e) => e.bias > 0).length;
      final dnN = f.indicators.where((e) => e.bias < 0).length;
      lines.add(InkWell(
        onTap: () => _showPanel(f),
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('📊 لوحة المؤشرات: $upN صاعد • $dnN هابط — اضغط لشرح كل مؤشر',
              style: const TextStyle(
                  color: AppColors.accent, fontSize: 11, decoration: TextDecoration.underline)),
        ),
      ));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  void _showPanel(Forecast f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctl) => ListView(
          controller: ctl,
          padding: const EdgeInsets.all(14),
          children: [
            const Text('لوحة المؤشرات الآن',
                style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
                'تُقبل التوصية فقط عندما يتوافق 60% إلى 90% من المؤشرات مع اتجاهها. '
                'التوافق الكامل 100% غالباً يعني أن الحركة انتهت والدخول متأخر.',
                style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 10),
            for (final e in f.indicators)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${e.fired ? '⚡ ' : ''}${e.name}',
                          style: const TextStyle(
                              color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    Text(
                        e.bias > 0
                            ? '▲ صاعد'
                            : e.bias < 0
                                ? '▼ هابط'
                                : '— محايد',
                        style: TextStyle(
                            color: e.bias > 0
                                ? AppColors.up
                                : e.bias < 0
                                    ? AppColors.down
                                    : AppColors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ]),
                  const SizedBox(height: 4),
                  Text(e.how, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              ),
            const Text('⚡ = أعطى المؤشر إشارة دخول في آخر 3 شموع',
                style: TextStyle(color: AppColors.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  /// القرار الوحيد في شاشة الشارت (من محرك التوصيات المقاس).
  Widget _decisionBar(Decision d, MarketSymbol sym) {
    final col = d.dir > 0
        ? AppColors.up
        : d.dir < 0
            ? AppColors.down
            : AppColors.muted;
    final label = d.state == 0
        ? 'انتظار'
        : d.state == 1
            ? (d.dir > 0 ? 'شراء' : 'بيع')
            : d.state == 2
                ? '⏳ ${d.dir > 0 ? 'شراء' : 'بيع'}'
                : '⚡ يتكوّن';
    Widget item(String t, double v, Color c) => Expanded(
          child: Column(children: [
            Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(v.isNaN ? '-' : sym.fmt(v),
                  style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: col.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 6),
          if (d.state == 1 || d.state == 2) ...[
            item(d.state == 2 ? 'دخول عند' : 'دخول', d.entry, AppColors.accent),
            item('وقف', d.sl, AppColors.down),
            item('TP1', d.tp1, AppColors.up),
            item('TP2', d.tp2, AppColors.up),
          ] else
            Expanded(
                child: Text(d.title,
                    style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
        Text(d.state == 1 || d.state == 2 ? '${d.title} • ${d.why}' : d.why,
            style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      ]),
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
              child: Text(v, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
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
              style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 12)),
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
