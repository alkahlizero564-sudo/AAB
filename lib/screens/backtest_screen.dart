import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../analysis/backtest.dart';
import '../models.dart';
import '../services/market_data_service.dart';
import '../services/settings_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sweep_screen.dart';

/// Replays the engine on past candles and reports real statistics.
class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});
  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  String tf = '1h';
  int bars = 3000;
  bool lean = true;
  int minAligned = 4;
  bool htfGate = false;
  bool prune = false;
  String mode = 'vote';
  int minLoc = 2;
  bool sessionOnly = false;
  bool running = false;
  double progress = 0;
  String phase = '';
  String? error;
  BtResult? result;
  MarketSymbol? sym;

  @override
  void initState() {
    super.initState();
    final cfg = EngineConfig.current;
    lean = cfg.lean;
    minAligned = cfg.minAligned;
    htfGate = cfg.htfGate;
    prune = cfg.prune;
    mode = cfg.mode;
    minLoc = cfg.minLoc;
    sessionOnly = cfg.sessionOnly;
  }

  Future<void> _run(AppState app) async {
    final s = app.settings;
    if (!s.hasTwelve && !s.hasTiingo) {
      setState(() => error = 'أضف مفاتيح البيانات من الإعدادات أولاً');
      return;
    }
    final symbol = sym ?? app.symbol;
    setState(() {
      running = true;
      error = null;
      result = null;
      progress = 0;
      phase = 'جلب البيانات التاريخية…';
    });
    try {
      final md = MarketDataService();
      final c = await md.fetch(symbol, tf, s, count: bars);
      var h = <Candle>[];
      try {
        h = await md.fetch(symbol, MarketDataService.higherTf[tf]!, s, count: 700);
      } catch (_) {}
      if (c.length < 400) throw Exception('البيانات غير كافية (${c.length} شمعة فقط)');
      if (mounted) setState(() => phase = 'جاري الاختبار على ${c.length} شمعة…');
      final cfg = EngineConfig(
          mode: mode,
          lean: lean,
          minAligned: minAligned,
          minScore: 30,
          htfGate: htfGate,
          prune: prune,
          minLoc: minLoc,
          sessionOnly: sessionOnly);
      final res = await BtRunner.run(BtRequest(c, h, symbol, s, cfg, tf), (p) {
        if (mounted && (p - progress).abs() > 0.01) setState(() => progress = p);
      });
      if (mounted) setState(() => result = res);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _openSweep(AppState app) async {
    final s = app.settings;
    if (!s.hasTwelve && !s.hasTiingo) {
      setState(() => error = 'أضف مفاتيح البيانات من الإعدادات أولاً');
      return;
    }
    final symbol = sym ?? app.symbol;
    setState(() {
      running = true;
      error = null;
      progress = 0;
      phase = 'جلب البيانات للضبط…';
    });
    try {
      final md = MarketDataService();
      final c = await md.fetch(symbol, tf, s, count: bars);
      // الإطار الأعلى يغطي نفس فترة الشموع
      final hf = MarketDataService.higherTf[tf]!;
      final hCount = (bars *
                  MarketDataService.tfMinutes[tf]! /
                  MarketDataService.tfMinutes[hf]!)
              .ceil() +
          150;
      var h = <Candle>[];
      try {
        h = await md.fetch(symbol, hf, s, count: hCount);
      } catch (_) {}
      if (c.length < 800) {
        throw Exception('البيانات غير كافية للضبط (${c.length} شمعة). اختر 3000 أو أكثر.');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SweepScreen(
              candles: c, htf: h, sym: symbol, settings: s, tf: tf),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Widget _chips<T>(String title, List<T> values, T current, String Function(T) label,
      void Function(T) on) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == current,
            onSelected: running ? null : (_) => setState(() => on(v)),
            selectedColor: AppColors.accent,
            backgroundColor: AppColors.card,
            labelStyle: TextStyle(color: v == current ? Colors.white : AppColors.muted),
            side: const BorderSide(color: AppColors.border),
          ),
      ]),
    ]);
  }

  Color _rc(double v) => v > 0.05 ? AppColors.up : (v < -0.05 ? AppColors.down : AppColors.gold);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final symbol = sym ?? app.symbol;
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار المحرك (Backtest)')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('الرمز: ', style: TextStyle(color: AppColors.muted)),
              Text(symbol.code, style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: running
                    ? null
                    : () async {
                        showSymbolSheet(context);
                      },
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('تغيير'),
              ),
            ]),
            const Text('الاختبار يستخدم الرمز المختار حالياً في التطبيق.',
                style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 12),
            _chips<String>('الإطار الزمني', const ['5m', '15m', '1h', '4h'], tf,
                (v) => v, (v) => tf = v),
            const SizedBox(height: 12),
            _chips<int>('عدد الشموع', const [1000, 2000, 3000, 5000], bars,
                (v) => '$v', (v) => bars = v),
            const SizedBox(height: 12),
            _chips<String>('نمط القرار', const ['vote', 'pro'], mode,
                (v) => v == 'pro' ? 'احترافي (اتجاه + موقع + تريغر)' : 'تصويت المؤشرات',
                (v) => mode = v),
            if (mode == 'pro') ...[
              const SizedBox(height: 12),
              _chips<int>('أقل عوامل توافق عند المنطقة', const [1, 2, 3, 4], minLoc,
                  (v) => '$v', (v) => minLoc = v),
              const SizedBox(height: 12),
              _chips<bool>('جلسات لندن/نيويورك فقط (فوركس)', const [false, true],
                  sessionOnly, (v) => v ? 'مفعّل' : 'متوقف', (v) => sessionOnly = v),
            ] else ...[
              const SizedBox(height: 12),
              _chips<bool>('وضع المؤشرات', const [true, false], lean,
                  (v) => v ? 'مبسّط (موصى به)' : 'كامل', (v) => lean = v),
              const SizedBox(height: 12),
              _chips<int>('أقل عدد مؤشرات متوافقة', const [3, 4, 5, 6], minAligned,
                  (v) => '$v', (v) => minAligned = v),
              const SizedBox(height: 12),
              _chips<bool>('فلتر الإطار الأعلى (تداول مع اتجاهه فقط)', const [false, true],
                  htfGate, (v) => v ? 'مفعّل' : 'متوقف', (v) => htfGate = v),
              const SizedBox(height: 12),
              _chips<bool>('حذف المؤشرات الضعيفة (SR Breaks وغيرها)', const [false, true],
                  prune, (v) => v ? 'مفعّل' : 'متوقف', (v) => prune = v),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: running ? null : () => _run(app),
                icon: const Icon(Icons.play_arrow),
                label: Text(running ? 'جاري التشغيل…' : 'شغّل الاختبار',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: running ? null : () => _openSweep(app),
                icon: const Icon(Icons.tune),
                label: const Text('ضبط تلقائي (تدريب + اختبار)'),
              ),
            ),
            if (running) ...[
              const SizedBox(height: 12),
              Text(phase, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress > 0 ? progress : null),
            ],
          ]),
        ),
        if (error != null) ErrorBanner(error!),
        if (result != null) ..._results(result!, app),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'النتائج تاريخية ولا تضمن المستقبل. الحساب يفترض تكلفة 0.05R لكل صفقة، وإذا لمست الشمعة الوقف والهدف معاً يُحسب الوقف أولاً. جرّب أكثر من رمز وفترة قبل ما تثق في الأرقام.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
          ),
        ),
      ]),
    );
  }

  List<Widget> _results(BtResult r, AppState app) {
    final best = r.models.reduce((a, b) => a.avgR >= b.avgR ? a : b);
    String verdict;
    Color vc;
    if (r.trades < 30) {
      verdict = 'عدد الصفقات قليل (${r.trades}) — الأرقام غير موثوقة. زد عدد الشموع أو خفف الفلاتر.';
      vc = AppColors.gold;
    } else if (best.avgR > 0.1 && best.profitFactor > 1.2) {
      verdict = 'المحرك أعطى نتيجة موجبة تاريخياً على هذه الفترة. هذا لا يضمن الاستمرار؛ اختبره على رموز وفترات أخرى.';
      vc = AppColors.up;
    } else if (best.avgR > 0) {
      verdict = 'نتيجة موجبة ضعيفة — الميزة صغيرة وقد تختفي بعد التكاليف الحقيقية.';
      vc = AppColors.gold;
    } else {
      verdict = 'المحرك خسران تاريخياً بهذه الإعدادات — لا تعتمد عليه. جرّب وضعاً آخر أو فلتراً أشد.';
      vc = AppColors.down;
    }
    final p = (DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return [
      Panel(
        borderColor: vc.withOpacity(0.6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r.trades} صفقة • ${r.bars} شمعة',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 2),
          Text('${p(r.from)}  ←  ${p(r.to)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 10),
          Text(verdict, style: TextStyle(color: vc, fontSize: 13, height: 1.5)),
        ]),
      ),
      _table('نموذج الخروج', r.models),
      if (r.byGrade.isNotEmpty) _table('حسب درجة الإشارة (خروج TP2)', r.byGrade),
      if (r.byDir.isNotEmpty) _table('حسب الاتجاه (خروج TP2)', r.byDir),
      if (r.inds.isNotEmpty) _indTable(r),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: () async {
            final cfg = EngineConfig(
                mode: mode,
                lean: lean,
                minAligned: minAligned,
                minScore: 30,
                htfGate: htfGate,
                prune: prune,
                minLoc: minLoc,
                sessionOnly: sessionOnly);
            await cfg.save();
            await app.refresh();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم اعتماد هذه الإعدادات في التطبيق')),
            );
          },
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('اعتمد هذه الإعدادات في التطبيق'),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _table(String title, List<ModelStats> rows) {
    Widget cell(String t, {Color? c, bool bold = false, int flex = 2}) => Expanded(
          flex: flex,
          child: Text(t,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: c ?? AppColors.text,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        );
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [
          cell('', flex: 3),
          cell('صفقات', c: AppColors.muted),
          cell('نجاح', c: AppColors.muted),
          cell('متوسط R', c: AppColors.muted),
          cell('PF', c: AppColors.muted),
          cell('أقصى تراجع', c: AppColors.muted),
        ]),
        const Divider(color: AppColors.border, height: 14),
        for (final m in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              cell(m.name, flex: 3, bold: true),
              cell('${m.trades}'),
              cell('${(m.winRate * 100).toStringAsFixed(0)}%'),
              cell(m.avgR.toStringAsFixed(2), c: _rc(m.avgR), bold: true),
              cell(m.profitFactor >= 99 ? '∞' : m.profitFactor.toStringAsFixed(2)),
              cell('${m.maxDD.toStringAsFixed(1)}R', c: AppColors.down),
            ]),
          ),
        const SizedBox(height: 4),
        const Text('R = وحدة المخاطرة (المسافة إلى وقف الخسارة). PF = إجمالي الأرباح ÷ إجمالي الخسائر.',
            style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4)),
      ]),
    );
  }

  Widget _indTable(BtResult r) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('أي مؤشر يفيد؟',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        const Text(
            'متوسط R للصفقات التي وافق فيها المؤشر الاتجاه مقابل الباقي. الفرق الموجب الكبير = مؤشر مفيد. (يظهر فقط لو فيه 30 صفقة على الأقل من كل نوع)',
            style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4)),
        const SizedBox(height: 8),
        for (final s in r.inds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  flex: 4,
                  child: Text(s.name,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              Expanded(
                  flex: 3,
                  child: Text('${s.nAgree} / ${s.nOther}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted))),
              Expanded(
                  flex: 2,
                  child: Text('${s.edge >= 0 ? '+' : ''}${s.edge.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _rc(s.edge)))),
            ]),
          ),
      ]),
    );
  }
} 
