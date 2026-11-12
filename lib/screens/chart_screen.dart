import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../analysis/benchmark.dart';
import '../analysis/chart_reader.dart';
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
  int? sel; // الشمعة المختارة بالضغط المطوّل

  void _showReading(AppState st, {int? upto}) {
    final r = readChart(st.candles, st.symbol, upto: upto, htf: upto == null ? st.htf : null);
    final when = upto == null ? 'الآن' : 'كما كان عند شمعة ${_hm(st.candles[upto].time)}';
    Color bc(int b) => b > 0 ? AppColors.up : (b < 0 ? AppColors.down : AppColors.muted);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, ctl) => ListView(
          controller: ctl,
          padding: const EdgeInsets.all(14),
          children: [
            Text('🧠 قراءة الشارت ($when)',
                style: const TextStyle(
                    color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bc(r.bias).withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: bc(r.bias).withOpacity(0.5)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.verdict,
                    style: TextStyle(color: bc(r.bias), fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 6),
                for (final sc in r.scenarios)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(sc,
                        style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.4)),
                  ),
              ]),
            ),
            if (upto == null && st.forecast != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withOpacity(0.6)),
                ),
                child: Text(
                    '🎯 قرار التوصيات (المحرك المُقاس): ${st.forecast!.decision.title}\n'
                    'القراءة أعلاه تشرح من يسيطر الآن، أما الدخول فيكون فقط عند اكتمال شروط التوصية.',
                    style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.4)),
              ),
            ],
            const SizedBox(height: 10),
            for (final sec in r.sections)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(right: BorderSide(color: bc(sec.bias), width: 3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${sec.icon} ${sec.title}',
                        style: const TextStyle(
                            color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
                    const Spacer(),
                    Text(
                        sec.bias > 0
                            ? '▲ للمشترين'
                            : sec.bias < 0
                                ? '▼ للبائعين'
                                : '— محايد',
                        style: TextStyle(
                            color: bc(sec.bias), fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  for (final l in sec.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $l',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
                    ),
                ]),
              ),
            const Text(
                'القراءة تستخدم فقط الشموع حتى اللحظة المختارة — لا تنظر للمستقبل. '
                'هي فهم للوضع الحالي واحتمالاته، وليست ضماناً لما سيحدث.',
                style: TextStyle(color: AppColors.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void _showBench(AppState st) {
    final rows = benchmark(st.candles, sym: st.symbol);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, ctl) => ListView(
          controller: ctl,
          padding: const EdgeInsets.all(14),
          children: [
            Text('🏆 مقارنة مع 22 مؤشراً من TradingView — ${st.symbol.code} ${st.tf}',
                style: const TextStyle(
                    color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'على آخر ${st.candles.length} شمعة من هذا الشارت. كل المؤشرات بإعداداتها الافتراضية '
                'وبنفس الدخول والوقف والهدف (1R ثم 2R) — مقارنة عادلة. '
                'الدقة = وصول الهدف الأول قبل الوقف.',
                style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Text('شموع غير كافية للمقارنة (أقل من 120).',
                  style: TextStyle(color: AppColors.muted)),
            for (var k = 0; k < rows.length; k++)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: rows[k].ours ? AppColors.accent.withOpacity(0.18) : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: rows[k].ours ? AppColors.accent : AppColors.border),
                ),
                child: Row(children: [
                  SizedBox(
                      width: 26,
                      child: Text('${k + 1}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                  Expanded(
                      child: Text(rows[k].name,
                          style: TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: rows[k].ours ? FontWeight.w800 : FontWeight.w500))),
                  Text(
                      rows[k].trades == 0
                          ? 'لا صفقات'
                          : '${(rows[k].winRate * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: rows[k].winRate >= 0.5 ? AppColors.up : AppColors.down,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 92,
                    child: Text(
                        '${rows[k].trades} صفقة • ${rows[k].avgR >= 0 ? '+' : ''}${rows[k].avgR.toStringAsFixed(2)}R',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            color: rows[k].avgR > 0 ? AppColors.up : AppColors.muted,
                            fontSize: 10)),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            const Text(
                'على 20 سوقاً حقيقياً (فوركس، ذهب، فضة، أسهم، مؤشرات، نفط) جاء مؤشر AAB الأول بين 23 مؤشراً: '
                '53.8% وربح في 18 من 20 سوقاً، مقابل 51.2% لـ UT Bot و50.6% لـ Volume Profile و48–50% للباقي. '
                'Alka بنفس الهدف: نفس دقة AAB (54.6% على 22 سوقاً مع البيتكوين) لكن بفرص أكثر بـ2.4 مرة '
                'وربح إجمالي أعلى بـ2.3 مرة. AAB أفضل على الأسهم، و Alka أفضل على الذهب والبيتكوين والنفط والعملات. '
                'على شارت واحد قصير قد يختلف الترتيب — العينة الصغيرة تتأثر بالصدفة.',
                style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4)),
          ],
        ),
      ),
    );
  }

  static String _hm(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _candlePanel(AppState st, int i) {
    final lines = explainCandle(st.candles, i, st.symbol);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 170),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: AppColors.card,
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('🕯️ شرح شمعة ${_hm(st.candles[i].time)}',
                style: const TextStyle(
                    color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            InkWell(
              onTap: () => _showReading(st, upto: i),
              child: const Text('🧠 اقرأ الشارت عندها',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      decoration: TextDecoration.underline)),
            ),
          ]),
          const SizedBox(height: 4),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(l,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
            ),
        ]),
      ),
    );
  }

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

  Widget _tool(String icon, String label, VoidCallback onTap, {bool primary = false}) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: Material(
          color: primary ? AppColors.accent : AppColors.card,
          shape: StadiumBorder(side: BorderSide(color: primary ? AppColors.accent : AppColors.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(icon, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: primary ? Colors.white : AppColors.text,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );

  Widget _toolbar() => SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
          children: [
            _tool('🧠', 'قراءة الشارت', () => _showReading(context.read<AppState>()), primary: true),
            _tool('🏆', 'مقارنة', () => _showBench(context.read<AppState>())),
            _tool('🎛️', 'طبقات', _showLayers),
            _tool(layers.alka ? '🟢' : '⚪', 'Alka', () => setState(() => layers.alka = !layers.alka)),
            _tool(layers.sigs ? '🟢' : '⚪', 'AAB', () => setState(() => layers.sigs = !layers.sigs)),
          ],
        ),
      );

  /// كل طبقات الشارت وإعداداته في قائمة واحدة مرتبة.
  void _showLayers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        void upd(VoidCallback f) {
          setState(f);
          setSheet(() {});
        }

        Widget sw(String t, String sub, bool v, void Function(bool) on) => SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(t, style: const TextStyle(color: AppColors.text, fontSize: 13)),
              subtitle: sub.isEmpty
                  ? null
                  : Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              value: v,
              onChanged: (x) => upd(() => on(x)),
            );
        Widget head(String t) => Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(t,
                  style: const TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13)),
            );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, ctl) => ListView(
            controller: ctl,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text('🎛️ طبقات الشارت',
                  style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
              head('شكل الشارت'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _seg(const [('candle', 'شموع'), ('ha', 'Heikin Ashi'), ('line', 'خطي')], layers.type,
                    (v) => upd(() => layers.type = v)),
                _seg(const [('rsi', 'RSI'), ('macd', 'MACD'), ('none', 'بدون')], layers.sub,
                    (v) => upd(() => layers.sub = v)),
              ]),
              sw('الحجم', 'أعمدة حجم التداول أسفل الشموع', layers.vol, (x) => layers.vol = x),
              head('التوصيات والمؤشرات'),
              sw('Alka', 'شموع الانعكاس عند الدعم/المقاومة و Volume Profile', layers.alka, (x) => layers.alka = x),
              sw('توصيات AAB', 'أسهم الشراء/البيع ونتيجتها', layers.sigs, (x) => layers.sigs = x),
              sw('AAB Algo', 'تلوين الشموع حسب قوة الاتجاه + خط الاتجاه', layers.algo, (x) => layers.algo = x),
              sw('توقع الشمعة القادمة', 'يظهر فقط عندما يدعم القرار', layers.fc, (x) => layers.fc = x),
              sw('أنماط الشموع', 'أسماء نماذج الشموع على الشارت', layers.pats, (x) => layers.pats = x),
              head('خطوط ومستويات'),
              sw('EMA 20/50/200', '', layers.ema, (x) => layers.ema = x),
              sw('مناطق OB/FVG', 'Order Blocks والفجوات السعرية', layers.zones, (x) => layers.zones = x),
              sw('مستويات اليوم والجلسات', 'PDH/PDL، آسيا، لندن...', layers.levels, (x) => layers.levels = x),
              sw('Volume Profile', '', layers.vp, (x) => layers.vp = x),
              sw('VWAP', '', layers.vwap, (x) => layers.vwap = x),
              sw('Fibonacci', '', layers.fib, (x) => layers.fib = x),
              sw('Chandelier Exit', '', layers.ce, (x) => layers.ce = x),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.signal;
    return Column(children: [
      // صف 1: الرمز + حالة البث + شاشة كاملة
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 2),
        child: Row(children: [
          const _CompactSymbol(),
          const SizedBox(width: 8),
          const Expanded(
              child: Align(alignment: AlignmentDirectional.centerStart, child: LiveBadge())),
          IconButton(
            tooltip: full ? 'إظهار الأدوات' : 'شاشة كاملة',
            visualDensity: VisualDensity.compact,
            iconSize: 22,
            color: AppColors.accent,
            icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: () => setState(() => full = !full),
          ),
        ]),
      ),
      if (!full) ...[
        // صف 2: الأُطر الزمنية (مضغوطة)
        const _CompactTf(),
        // صف 3: الأدوات
        _toolbar(),
      ],
      Expanded(
        child: NativeChart(
          candles: st.candles,
          signal: s,
          forecast: st.forecast,
          algo: st.algo,
          alka: st.alka,
          repaint: st.liveTick,
          sym: st.symbol,
          tf: st.tf,
          layers: layers,
          onSelect: (i) => setState(() => sel = i),
        ),
      ),
      if (st.forecast != null) ...[
        if (sel != null && sel! < st.candles.length)
          _candlePanel(st, sel!)
        else if (!full)
          _forecastBar(st.forecast!, st.symbol),
        if (layers.alka && st.alka != null && st.alka!.decision.state != 0)
          _decisionBar(st.alka!.decision, st.symbol, tag: 'Alka'),
        _decisionBar(st.forecast!.decision, st.symbol, tag: 'AAB'),
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
  Widget _decisionBar(Decision d, MarketSymbol sym, {String tag = ''}) {
    if (d.state == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Text('${tag.isEmpty ? '' : '$tag: '}انتظار — لا توجد إشارة مكتملة الشروط',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      );
    }
    final col = d.dir > 0
        ? AppColors.up
        : d.dir < 0
            ? AppColors.down
            : AppColors.muted;
    final label = '${tag.isEmpty ? '' : '$tag '}${d.state == 0 ? 'انتظار' : d.state == 1 ? (d.dir > 0 ? 'شراء' : 'بيع') : d.state == 2 ? '⏳ ${d.dir > 0 ? 'شراء' : 'بيع'}' : '⚡ يتكوّن'}';
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

/// زر الرمز المضغوط (يفتح قائمة الأسواق).
class _CompactSymbol extends StatelessWidget {
  const _CompactSymbol();
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showSymbolSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(st.symbol.code,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text)),
          const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.muted),
        ]),
      ),
    );
  }
}

/// الأُطر الزمنية في صف واحد مضغوط.
class _CompactTf extends StatelessWidget {
  const _CompactTf();
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          for (final t in AppState.timeframes)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => st.setTf(t),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: st.tf == t ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(t,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: st.tf == t ? FontWeight.w800 : FontWeight.w500,
                          color: st.tf == t ? Colors.white : AppColors.muted)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
