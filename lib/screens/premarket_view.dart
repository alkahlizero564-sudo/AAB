import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/premarket_service.dart';
import '../state/app_state.dart';
import '../state/premarket_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "تحليل ما قبل الافتتاح": bias, key levels, opening range, live-checked
/// entry conditions and an AI news summary — modelled on the video.
class PreMarketView extends StatefulWidget {
  const PreMarketView({super.key});
  @override
  State<PreMarketView> createState() => _PreMarketViewState();
}

class _PreMarketViewState extends State<PreMarketView> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRun());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _autoRun() {
    if (!mounted) return;
    final pm = context.read<PreMarketState>();
    final app = context.read<AppState>();
    if (pm.plan == null && !pm.loading && pm.error == null) pm.run(app);
  }

  String _countdown(PreMarketPlan p) {
    final now = DateTime.now().toUtc();
    final d = p.openUtc.difference(now);
    if (d.isNegative) {
      final m = now.difference(p.openUtc).inMinutes;
      return m > 420 ? 'الجلسة انتهت' : 'مفتوح منذ $m دقيقة';
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return 'يفتح بعد ${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Color _kindColor(String k) {
    switch (k) {
      case 'session':
        return const Color(0xFF4FC3F7);
      case 'vp':
        return const Color(0xFFA06BFF);
      case 'vwap':
        return const Color(0xFFFFD54F);
      case 'fib':
        return AppColors.gold;
      case 'or':
        return AppColors.up;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.watch<PreMarketState>();
    final app = context.watch<AppState>();
    final p = pm.plan;

    // symbol changed after the plan was built → rebuild it
    if (p != null && p.sym.code != app.symbol.code && !pm.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<PreMarketState>().run(app);
      });
    }

    final price = (app.signal != null && p != null && p.sym.code == app.symbol.code)
        ? app.signal!.price
        : p?.price ?? 0.0;

    return RefreshIndicator(
      onRefresh: () => pm.run(app),
      child: ListView(
        padding: const EdgeInsets.all(14),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            const SymbolButton(),
            const Spacer(),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'NY', label: Text('نيويورك')),
                ButtonSegment(value: 'LDN', label: Text('لندن')),
              ],
              selected: {pm.session},
              onSelectionChanged: (v) => pm.setSession(v.first, app),
            ),
            IconButton(
              tooltip: 'تحديث التحليل',
              onPressed: pm.loading ? null : () => pm.run(app),
              icon: pm.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ]),
          const SizedBox(height: 12),
          if (pm.error != null) ErrorBanner(pm.error!),
          if (p == null && pm.loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (p != null) ...[
            _header(p),
            _biasCard(p, price),
            _scenario(p, p.bull, price),
            _scenario(p, p.bear, price),
            if (p.opening != null) _orCard(p, price),
            _ladder(p, price),
            _newsCard(p, pm),
            if (p.notes.isNotEmpty) _notes(p),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'تحليل احتمالي للتحضير فقط وليس نصيحة مالية. لا تدخل إلا بعد اكتمال الشروط.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(PreMarketPlan p) => Panel(
        child: Row(children: [
          const Icon(Icons.schedule, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  p.session == 'NY' ? 'افتتاح نيويورك 09:30' : 'افتتاح لندن 03:00 (توقيت نيويورك)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(_countdown(p),
                  style: const TextStyle(color: AppColors.gold, fontSize: 13)),
            ]),
          ),
          Text(p.sym.code,
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );

  Widget _biasCard(PreMarketPlan p, double price) {
    final col = p.bias > 0 ? AppColors.up : (p.bias < 0 ? AppColors.down : AppColors.gold);
    final label = p.bias > 0 ? 'الانحياز: صاعد ▲' : (p.bias < 0 ? 'الانحياز: هابط ▼' : 'الانحياز: محايد ↔');
    return Panel(
      borderColor: col.withOpacity(0.6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style: TextStyle(color: col, fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(p.sym.fmt(price),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Text('قوة الانحياز',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const Spacer(),
          Text('${p.confidence.toStringAsFixed(0)}%',
              style: TextStyle(color: col, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: p.confidence / 100,
            minHeight: 8,
            color: col,
            backgroundColor: AppColors.surface,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _tag('المحرك الفني ${p.techScore.toStringAsFixed(0)}'),
          _tag(p.htfTrend == 0
              ? 'الإطار الأعلى: محايد'
              : p.htfTrend > 0
                  ? 'الإطار الأعلى: صاعد'
                  : 'الإطار الأعلى: هابط'),
        ]),
      ]),
    );
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      );

  Widget _scenario(PreMarketPlan p, Scenario sc, double price) {
    final col = sc.bull ? AppColors.up : AppColors.down;
    final allOk = sc.conds.every((c) => c.eval(price));
    final done = sc.conds.where((c) => c.eval(price)).length;
    final f = p.sym.fmt;
    Widget lv(String t, double v, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withOpacity(0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(f(v),
                    style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        );
    return Panel(
      borderColor: col.withOpacity(allOk ? 0.9 : 0.35),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(sc.bull ? 'سيناريو الصعود ▲' : 'سيناريو الهبوط ▼',
              style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (allOk ? AppColors.up : AppColors.gold).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(allOk ? 'جاهز للدخول' : 'الشروط $done/${sc.conds.length}',
                style: TextStyle(
                    color: allOk ? AppColors.up : AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('الزناد: ${sc.trigger}',
            style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.4)),
        const SizedBox(height: 10),
        Row(children: [
          lv('الدخول', sc.triggerPrice, AppColors.accent),
          const SizedBox(width: 6),
          lv('الوقف', sc.sl, AppColors.down),
          const SizedBox(width: 6),
          lv('TP1', sc.tp1, AppColors.up),
          const SizedBox(width: 6),
          lv('TP2', sc.tp2, AppColors.up),
          const SizedBox(width: 6),
          lv('TP3', sc.tp3, AppColors.up),
        ]),
        const SizedBox(height: 10),
        for (final c in sc.conds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(c.eval(price) ? Icons.check_circle : Icons.cancel,
                  size: 18, color: c.eval(price) ? AppColors.up : AppColors.down),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(c.text,
                      style: const TextStyle(fontSize: 12, color: AppColors.text))),
            ]),
          ),
      ]),
    );
  }

  Widget _orCard(PreMarketPlan p, double price) {
    final o = p.opening!;
    final pos = price > o.hi ? 'فوق النطاق' : (price < o.lo ? 'تحت النطاق' : 'داخل النطاق');
    final col = price > o.hi ? AppColors.up : (price < o.lo ? AppColors.down : AppColors.gold);
    return Panel(
      child: Row(children: [
        const Icon(Icons.stacked_bar_chart, color: AppColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('نطاق الافتتاح (30 د)${o.complete ? '' : ' — لم يكتمل'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('أعلى ${p.sym.fmt(o.hi)}   أدنى ${p.sym.fmt(o.lo)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        Text(pos, style: TextStyle(color: col, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _ladder(PreMarketPlan p, double price) {
    final rows = p.levels.toList()..sort((a, b) => b.price.compareTo(a.price));
    final out = <Widget>[];
    var placed = false;
    Widget priceRow() => Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent),
          ),
          child: Row(children: [
            const Icon(Icons.arrow_right, color: AppColors.accent),
            const Text('السعر الآن',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Spacer(),
            Text(p.sym.fmt(price),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        );
    for (final l in rows) {
      if (!placed && price >= l.price) {
        out.add(priceRow());
        placed = true;
      }
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Row(children: [
          Icon(Icons.circle, size: 8, color: _kindColor(l.kind)),
          const SizedBox(width: 8),
          Text(l.name, style: TextStyle(color: _kindColor(l.kind), fontSize: 12)),
          const Spacer(),
          Text(p.sym.fmt(l.price), style: const TextStyle(fontSize: 12)),
        ]),
      ));
    }
    if (!placed) out.add(priceRow());
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('المستويات المهمة قبل ما تبدأ الحركة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('PDH/PDL • جلسات آسيا ولندن • Volume Profile • VWAP • فيبوناتشي',
            style: TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 8),
        ...out,
      ]),
    );
  }

  Widget _newsCard(PreMarketPlan p, PreMarketState pm) {
    final s = p.newsSentiment;
    final col = s == 'bullish'
        ? AppColors.up
        : s == 'bearish'
            ? AppColors.down
            : AppColors.gold;
    final label = s == 'bullish'
        ? 'الأخبار: إيجابية'
        : s == 'bearish'
            ? 'الأخبار: سلبية'
            : 'الأخبار: محايدة';
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s == null ? 'مراجعة الأخبار بالذكاء الاصطناعي' : label,
                style: TextStyle(
                    color: s == null ? AppColors.text : col,
                    fontWeight: FontWeight.bold)),
          ),
          if (pm.aiLoading)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (p.newsSummary != null) ...[
          const SizedBox(height: 8),
          Text(p.newsSummary!,
              style: const TextStyle(height: 1.5, color: AppColors.text, fontSize: 13)),
        ],
        for (final r in p.newsRisks)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber, size: 15, color: AppColors.gold),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(r,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted))),
            ]),
          ),
        if (p.headlines.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('أهم العناوين',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          for (final h in p.headlines.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $h',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.muted, height: 1.4)),
            ),
        ],
        if (p.newsSummary == null && !pm.aiLoading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('أضف مفاتيح Gemini لتحليل الأخبار تلقائياً.',
                style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _notes(PreMarketPlan p) => Panel(
        color: AppColors.gold.withOpacity(0.08),
        borderColor: AppColors.gold.withOpacity(0.4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in p.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $n',
                  style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.text)),
            ),
        ]),
      );
}
