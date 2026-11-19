import 'dart:isolate';
import 'package:flutter/material.dart';
import '../analysis/all_indicator.dart';
import 'package:provider/provider.dart';
import '../analysis/benchmark.dart';
import '../analysis/chart_reader.dart';
import '../analysis/forecast.dart';
import '../analysis/health.dart';
import '../analysis/trade_check.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/native_chart.dart';

/// طبقات البداية في اختبارات لقطات الشاشة فقط.
ChartLayers? debugChartLayers;

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});
  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final layers = debugChartLayers ?? ChartLayers();
  bool full = false; // وضع الشاشة الكاملة للشارت
  int? sel; // الشمعة المختارة بالضغط المطوّل
  bool why = false; // إظهار سبب القرار في الشريط السفلي
  final forceShow = <String>{}; // مؤشرات طلب المستخدم إظهارها رغم أنها 🔴

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
                style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bc(r.bias).withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: bc(r.bias).withOpacity(0.5)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.verdict, style: TextStyle(color: bc(r.bias), fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 6),
                for (final sc in r.scenarios)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(sc, style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.4)),
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
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
                    const Spacer(),
                    Text(
                        sec.bias > 0
                            ? '▲ للمشترين'
                            : sec.bias < 0
                                ? '▼ للبائعين'
                                : '— محايد',
                        style: TextStyle(color: bc(sec.bias), fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  for (final l in sec.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $l', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
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

  /// المقارنة على تاريخ طويل (3000 شمعة) في خيط منفصل.
  Future<(List<Candle>, List<BenchRow>, bool)> _benchData(AppState st) async {
    var c = st.candles;
    var long = false;
    try {
      final h = await st.fetchLong();
      if (h.length > c.length) {
        c = h;
        long = true;
      }
    } catch (_) {
      // نكمل بالشموع الموجودة
    }
    final sym = st.symbol;
    final data = c;
    List<BenchRow> rows;
    try {
      final dd = st.daily == null ? null : List<Candle>.of(st.daily!);
      rows = await Isolate.run(() => benchmark(data, sym: sym, daily: dd));
    } catch (_) {
      rows = benchmark(data, sym: sym, daily: st.daily);
    }
    // الموثوق أولاً (20 صفقة فأكثر) حسب الدقة، ثم العينات الصغيرة
    const minTrades = 20;
    rows.sort((a, b) {
      final ra = a.trades >= minTrades, rb = b.trades >= minTrades;
      if (ra != rb) return ra ? -1 : 1;
      if (!ra) return b.trades.compareTo(a.trades);
      final c1 = b.winRate.compareTo(a.winRate);
      return c1 != 0 ? c1 : b.avgR.compareTo(a.avgR);
    });
    return (data, rows, long);
  }

  void _showBench(AppState st) {
    final future = _benchData(st);
    final title = '🏆 مقارنة مع 22 مؤشراً من TradingView — ${st.symbol.code} ${st.tf}';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, ctl) => FutureBuilder<(List<Candle>, List<BenchRow>, bool)>(
          future: future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return ListView(controller: ctl, padding: const EdgeInsets.all(14), children: [
                Text(title, style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 40),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 14),
                const Center(
                    child: Text('جاري جلب تاريخ أطول (3000 شمعة) وحساب 24 مؤشراً…',
                        style: TextStyle(color: AppColors.muted, fontSize: 12))),
              ]);
            }
            final (c, rows, long) = snap.data!;
            final days = c.isEmpty ? 0 : c.last.time.difference(c.first.time).inDays;
            final reliable = rows.where((r) => r.trades >= 20).length;
            return ListView(
              controller: ctl,
              padding: const EdgeInsets.all(14),
              children: [
                Text(title, style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                    'على آخر ${c.length} شمعة (حوالي $days يوم)${long ? '' : ' — تعذر جلب تاريخ أطول'}. '
                    'كل المؤشرات بإعداداتها الافتراضية وبنفس الدخول والوقف والهدف (1R ثم 2R) — مقارنة عادلة. '
                    'الدقة = وصول الهدف الأول قبل الوقف. الترتيب للمؤشرات التي لها 20 صفقة فأكثر. '
                    'تنبيه: مع أقل من 100 صفقة، فرق أقل من 8% بين مؤشرين غالباً صدفة، والترتيب يتغير من شهر لآخر.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                if (reliable < 3)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('⚠️ صفقات قليلة على هذا الشارت — جرّب فريماً أصغر للحصول على عينة أكبر.',
                        style: TextStyle(color: AppColors.gold, fontSize: 11)),
                  ),
                const SizedBox(height: 10),
                for (var k = 0; k < rows.length; k++) _benchRow(k, rows[k]),
                const SizedBox(height: 6),
                const Text(
                    'على 25 سوقاً حقيقياً (فوركس، ذهب، فضة، بيتكوين، أسهم، مؤشرات، نفط) وبنفس الإدارة: '
                    'AAB الأول (54.8%، رابح في 23 من 25) و Alka الثاني (54.3%، رابح في 25 من 25 وأعلى ربح إجمالي)، '
                    'وبقية المؤشرات بين 47.6% و50.6%. ALL (دمج الاثنين + الشمعة الصغيرة): 57.2% بنفس الهدف.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _benchRow(int k, BenchRow r) {
    final small = r.trades < 20;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: r.ours ? AppColors.accent.withOpacity(0.18) : AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: r.ours ? AppColors.accent : AppColors.border),
      ),
      child: Row(children: [
        SizedBox(
            width: 26,
            child: Text(small ? '–' : '${k + 1}', style: const TextStyle(color: AppColors.muted, fontSize: 12))),
        Expanded(
            child: Text(r.name,
                style: TextStyle(
                    color: small ? AppColors.muted : AppColors.text,
                    fontSize: 13,
                    fontWeight: r.ours ? FontWeight.w800 : FontWeight.w500))),
        if (small)
          Container(
            margin: const EdgeInsetsDirectional.only(end: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('عينة صغيرة', style: TextStyle(color: AppColors.gold, fontSize: 9)),
          ),
        Text(r.trades == 0 ? 'لا صفقات' : '${(r.winRate * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                color: small
                    ? AppColors.muted
                    : r.winRate >= 0.5
                        ? AppColors.up
                        : AppColors.down,
                fontWeight: FontWeight.w800,
                fontSize: 13)),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text('${r.trades} صفقة • ${r.avgR >= 0 ? '+' : ''}${r.avgR.toStringAsFixed(2)}R',
              textAlign: TextAlign.end,
              style: TextStyle(color: r.avgR > 0 && !small ? AppColors.up : AppColors.muted, fontSize: 10)),
        ),
      ]),
    );
  }

  static String _hm(DateTime t) => '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
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
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            InkWell(
              onTap: () => _showReading(st, upto: i),
              child: const Text('🧠 اقرأ الشارت عندها',
                  style: TextStyle(color: AppColors.accent, fontSize: 11, decoration: TextDecoration.underline)),
            ),
          ]),
          const SizedBox(height: 4),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(l, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
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
                        color: value == k ? AppColors.onAccent : AppColors.muted,
                        fontWeight: value == k ? FontWeight.w700 : FontWeight.w400)),
              ),
            ),
        ]),
      );

  Widget _iconTool(IconData i, String tip, VoidCallback onTap, {bool primary = false}) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 5),
        child: Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: primary ? AppColors.goldGrad : null,
                color: primary ? null : AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: primary ? null : Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Icon(i, size: 18, color: primary ? AppColors.onAccent : AppColors.gold),
            ),
          ),
        ),
      );

  Widget _tfItem(AppState st, String t) {
    final on = st.tf == t;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => st.setTf(t),
      child: Container(
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          color: on ? AppColors.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: on ? Border.all(color: AppColors.accent.withOpacity(0.7), width: 0.8) : null,
        ),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? AppColors.gold : AppColors.muted)),
      ),
    );
  }

  /// كل مؤشراتنا بترتيب واحد (من الأدق للأعم) — للشريط وللوحة المؤشرات.
  List<({String name, String emoji, String desc, IndHealth? health, bool on, VoidCallback toggle})> _indicators(
          AppState st) =>
      [
        (
          name: 'نجوم',
          emoji: '⭐',
          desc: 'كل إشارات Mp ونجوم الثقة: درجة ثقة ST + هدوء السوق (كل نجمة أدق)',
          health: null,
          on: layers.star,
          toggle: () => layers.star = !layers.star
        ),
        if (st.symbol.category == 'metal')
          (
            name: 'DM',
            emoji: '🥇',
            desc: 'خاص بالذهب: مع الترند اليومي في السوق الهادئ',
            health: st.dmHealth,
            on: layers.dm,
            toggle: () => layers.dm = !layers.dm
          ),
        (
          name: 'KM',
          emoji: '💎',
          desc: 'الأدق بهدف 1R — صفقات قليلة في السوق الهادئ',
          health: st.kmHealth,
          on: layers.km,
          toggle: () => layers.km = !layers.km
        ),
        (
          name: 'ST',
          emoji: '🧠',
          desc: 'نموذج متعلّم: أعلى 30% من إشارات Mp مع درجة الثقة',
          health: st.stHealth,
          on: layers.st,
          toggle: () => layers.st = !layers.st
        ),
        (
          name: 'SM',
          emoji: '〰️',
          desc: 'Mp مع شريط المتوسطات واتجاه الساعة',
          health: st.smHealth,
          on: layers.sm,
          toggle: () => layers.sm = !layers.sm
        ),
        (
          name: 'Mp',
          emoji: '👑',
          desc: 'دمج مؤشراتنا — أكثر صفقات وأكبر ربح',
          health: st.mpHealth,
          on: layers.mp,
          toggle: () => layers.mp = !layers.mp
        ),
        (
          name: 'ALL',
          emoji: '🔗',
          desc: 'دمج AAB و Alka',
          health: st.allHealth,
          on: layers.all,
          toggle: () => layers.all = !layers.all
        ),
        (
          name: '0.1',
          emoji: '🎯',
          desc: 'مصيدة سيولة + شمعة رفض',
          health: st.zeroHealth,
          on: layers.zero,
          toggle: () => layers.zero = !layers.zero
        ),
        (
          name: 'Alka',
          emoji: '🕯️',
          desc: 'شموع الانعكاس عند الدعم والمقاومة',
          health: st.alkaHealth,
          on: layers.alka,
          toggle: () => layers.alka = !layers.alka
        ),
        (
          name: 'AAB',
          emoji: '📈',
          desc: 'توصيات AAB الأساسية',
          health: st.aabHealth,
          on: layers.sigs,
          toggle: () => layers.sigs = !layers.sigs
        ),
      ];

  /// زر "المؤشرات": أسماء المشغّل منها (كل اسم بلون حالته على هذا السوق) — يفتح لوحة كل المؤشرات.
  Widget _indButton(
      List<({String name, String emoji, String desc, IndHealth? health, bool on, VoidCallback toggle})> on) {
    Color col(IndHealth? h) => switch (h?.light) {
          'green' => AppColors.up,
          'yellow' => AppColors.gold,
          'red' => AppColors.down,
          _ => AppColors.muted,
        };
    // كل اسم بلون حالته على هذا السوق (أخضر قوي، ذهبي متوسط، أحمر ضعيف)
    final spans = <InlineSpan>[
      for (final (q, x) in on.indexed) ...[
        if (q > 0) const TextSpan(text: ' · ', style: TextStyle(color: AppColors.muted)),
        TextSpan(text: x.name, style: TextStyle(color: x.health == null ? AppColors.text : col(x.health))),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9), side: const BorderSide(color: AppColors.gold, width: 0.9)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _showIndicators,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(children: [
              const Icon(Icons.tune_rounded, size: 16, color: AppColors.gold),
              const SizedBox(width: 7),
              Expanded(
                child: on.isEmpty
                    ? const Text('المؤشرات — اختر مؤشراً',
                        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700))
                    : Text.rich(TextSpan(children: spans),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: AppColors.gold),
            ]),
          ),
        ),
      ),
    );
  }

  /// لوحة المؤشرات: بطاقة لكل مؤشر (لمسة = تشغيل/إيقاف) مع حالته ودقته على هذا السوق.
  void _showIndicators() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        final st = context.watch<AppState>();
        final inds = _indicators(st);
        Widget card(({String name, String emoji, String desc, IndHealth? health, bool on, VoidCallback toggle}) x) {
          final h = x.health;
          final col = switch (h?.light) {
            'green' => AppColors.up,
            'yellow' => AppColors.gold,
            'red' => AppColors.down,
            _ => AppColors.muted,
          };
          return Material(
            color: x.on ? AppColors.gold.withOpacity(0.10) : AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: x.on ? AppColors.gold : AppColors.border, width: x.on ? 1.4 : 0.8),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(x.toggle);
                setSheet(() {});
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(x.emoji, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 6),
                    Text(x.name,
                        style: TextStyle(
                            color: x.on ? AppColors.gold : AppColors.text, fontSize: 15, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Icon(x.on ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 18, color: x.on ? AppColors.gold : AppColors.muted),
                  ]),
                  const SizedBox(height: 3),
                  Text(x.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.3)),
                  const Spacer(),
                  Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        x.name == 'نجوم'
                            ? (st.starMin == 0 ? 'يظهر: كل الإشارات' : 'يظهر: ${st.starMin} نجوم فما فوق')
                            : h == null
                            ? 'جاري الحساب…'
                            : h.trades < 20
                                ? 'عينة صغيرة (${h.trades} صفقة)'
                                : '${h.label} • ${(h.winRate * 100).toStringAsFixed(0)}% من ${h.trades}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: col, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                  if (x.name == 'نجوم')
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('المدى الطويل: 3 نجوم 64% • بلا 55%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.text, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  if (longTermAcc[x.name] case final lt?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('المدى الطويل ${lt.$1.toStringAsFixed(0)}% • إدارة ${lt.$2.toStringAsFixed(0)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.text, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 10),
              Row(children: [
                const Text('المؤشرات',
                    style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text('${st.symbol.code} • ${st.tf}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 2),
              const Text('شغّل أي عدد معاً. السطر الملوّن: أداؤه الآن على هذا السوق (آخر 5000 شمعة). السطر الأبيض: دقته على المدى الطويل (بهدف 1R، وبإدارة التطبيق).',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(height: 8),
              if (layers.star)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Text('أقل عدد نجوم:',
                        style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    _seg(const [('0', 'الكل'), ('1', '1'), ('2', '2'), ('3', '3')], '${st.starMin}', (v) {
                      st.setStarMin(int.parse(v));
                      setSheet(() {});
                    }),
                  ]),
                ),
              Flexible(
                  child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
                children: [for (final x in inds) card(x)],
              )),
            ]),
          ),
        );
      }),
    );
  }

  /// سطر يشرح لماذا أُخفي مؤشر ضعيف، مع زر "إظهار".
  Widget _hiddenNotice(String name, IndHealth h, String key) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(children: [
          Expanded(
            child: Text('🔴 $name ضعيف الآن على هذا السوق: ${h.summary} — إشاراته مخفية',
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
          TextButton(
            onPressed: () => setState(() => forceShow.add(key)),
            child: const Text('إظهار', style: TextStyle(fontSize: 12)),
          ),
        ]),
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
              subtitle: sub.isEmpty ? null : Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              value: v,
              onChanged: (x) => upd(() => on(x)),
            );
        Widget head(String t) => Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child:
                  Text(t, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13)),
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
              head('خيارات الصفقات (مطفأة افتراضياً)'),
              sw('إشارات إضافية بعد TP1',
                  'إشارة "+" في نفس اتجاه الصفقة المفتوحة بعد أن تحقق TP1 (الأولى بلا خطر) — صفقات أكثر ~17%',
                  context.read<AppState>().settings.extraSameDir, (x) {
                context.read<AppState>().setEngineOptions(extraSameDir: x);
              }),
              head('التوصيات والمؤشرات'),
              sw('DM 🥇', 'خاص بالذهب: إشارات Mp مع الترند اليومي في السوق الهادئ — 59% بهدف 1R على ذهب 2021-2026', layers.dm, (x) {
                layers.dm = x;
              }),
              sw('نجوم ⭐', 'كل إشارات Mp ومعها نجوم الثقة: درجة ثقة ST + هدوء السوق — 3 نجوم ≈ 64% بهدف 1R. «ضغط» = نجمتان أو 3 في سوق مضغوط ≈ 68-70%.',
                  layers.star, (x) {
                layers.star = x;
              }),
              sw(
                  'ST 🧠',
                  'نموذج تعلّم من 10 سنوات: إشارات Mp عالية الثقة فقط (أعلى 30%) مع درجة الثقة — بدقة KM وضعف صفقاته',
                  layers.st, (x) {
                layers.st = x;
              }),
              sw('KM 💎', 'إشارات SM في السوق الهادئ فقط — الأدق (62%) لكن صفقات قليلة', layers.km, (x) {
                layers.km = x;
              }),
              sw('SM', 'إشارات Mp التي يوافقها شريط المتوسطات (الأدق، صفقات أقل) + رسم الشريط', layers.sm, (x) {
                layers.sm = x;
              }),
              sw('Mp 👑', 'دمج مؤشراتنا الأربعة (ALL + 0.1) — الأقوى: أدق وأكثر صفقات', layers.mp, (x) {
                layers.mp = x;
              }),
              sw('ALL', 'دمج AAB و Alka + فلتر الشمعة الصغيرة — الأدق (≈81% بالهدف 0.35R)', layers.all,
                  (x) => layers.all = x),
              sw('0.1', 'مصيدة سيولة + شمعة رفض — أزرق شراء، أصفر بيع', layers.zero, (x) => layers.zero = x),
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
    final mk = '${st.symbol.code}|${st.tf}';
    final auto = st.settings.autoHideWeak;
    final hideAab = auto && st.aabHealth?.light == 'red' && !forceShow.contains('AAB|$mk');
    final hideAlka = auto && st.alkaHealth?.light == 'red' && !forceShow.contains('Alka|$mk');
    final hideDm = auto && st.dmHealth?.light == 'red' && !forceShow.contains('DM|$mk');
    final hideSt = auto && st.stHealth?.light == 'red' && !forceShow.contains('ST|$mk');
    final hideKm = auto && st.kmHealth?.light == 'red' && !forceShow.contains('KM|$mk');
    final hideSm = auto && st.smHealth?.light == 'red' && !forceShow.contains('SM|$mk');
    final hideMp = auto && st.mpHealth?.light == 'red' && !forceShow.contains('Mp|$mk');
    final hideZero = auto && st.zeroHealth?.light == 'red' && !forceShow.contains('0.1|$mk');
    final hideAll = auto && st.allHealth?.light == 'red' && !forceShow.contains('ALL|$mk');
    final eff = layers.copyWith(
        sigs: layers.sigs && !hideAab,
        alka: layers.alka && !hideAlka,
        all: layers.all && !hideAll,
        zero: layers.zero && !hideZero,
        mp: layers.mp && !hideMp,
        sm: layers.sm && !hideSm,
        km: layers.km && !hideKm,
        dm: layers.dm && !hideDm,
        st: layers.st && !hideSt);
    return Column(children: [
      // صف 1: الرمز والسعر + أدوات (قراءة، مقارنة، طبقات، شاشة كاملة)
      Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border, width: 0.6)),
        ),
        child: Row(children: [
          const _CompactSymbol(),
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: st.liveStatus == 'live' ? AppColors.up : AppColors.gold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: (st.liveStatus == 'live' ? AppColors.up : AppColors.gold).withOpacity(0.6), blurRadius: 6),
              ],
            ),
          ),
          const Spacer(),
          _iconTool(Icons.auto_graph_rounded, 'قراءة الشارت', () => _showReading(st), primary: true),
          _iconTool(Icons.leaderboard_outlined, 'مقارنة المؤشرات', () => _showBench(st)),
          _iconTool(Icons.align_vertical_center_rounded, 'الدعم والمقاومة', () => setState(() => layers.sr = !layers.sr),
              primary: layers.sr),
          _iconTool(Icons.layers_outlined, 'الطبقات', _showLayers),
          _iconTool(
              full ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded, full ? 'إظهار الأدوات' : 'شاشة كاملة',
              () {
            setState(() => full = !full);
            st.setChartFull(full);
          }),
        ]),
      ),
      if (!full)
        // صف 2: الأُطر الزمنية | المؤشرات (مع لون حالتها)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            height: 32,
            child: Row(children: [for (final t in AppState.timeframes) Expanded(child: _tfItem(st, t))]),
          ),
        ),
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: NativeChart(
              candles: st.candles,
              signal: s,
              forecast: st.forecast,
              algo: st.algo,
              alka: st.alka,
              zero: st.zero,
              mpR: st.mpR,
              smR: st.smR,
              kmR: st.kmR,
              dmR: st.dmR,
              stR: st.stR,
              starR: st.starR,
              allR: st.allR,
              repaint: st.liveTick,
              sym: st.symbol,
              tf: st.tf,
              layers: eff,
              onSelect: (i) => setState(() => sel = i),
            ),
          ),
          // لوحة الاتجاهات (مثل DTC) عند تشغيل SM
          if ((eff.sm || eff.km || eff.dm) && st.board.isNotEmpty)
            Positioned(
              top: 44,
              left: 6,
              child: IgnorePointer(child: _TrendBoard(board: st.board)),
            ),
        ]),
      ),
      // الشاشة الكاملة: الشارت وحده بدون أي أشرطة
      if (!full && st.forecast != null) ...[
        if (sel != null && sel! < st.candles.length)
          _candlePanel(st, sel!)
        else if (!full)
          _forecastBar(st.forecast!, st.symbol),
        if (hideAll && layers.all) _hiddenNotice('ALL', st.allHealth!, 'ALL|$mk'),
        if (eff.all && st.allR != null) _decisionBar(st.allR!.decision, st.symbol, tag: 'ALL'),
        if (eff.star && st.starR != null) _starBar(st),
        if (hideDm && layers.dm) _hiddenNotice('DM', st.dmHealth!, 'DM|$mk'),
        if (hideSt && layers.st) _hiddenNotice('ST', st.stHealth!, 'ST|$mk'),
        if (hideKm && layers.km) _hiddenNotice('KM', st.kmHealth!, 'KM|$mk'),
        if (hideSm && layers.sm) _hiddenNotice('SM', st.smHealth!, 'SM|$mk'),
        if (hideMp && layers.mp) _hiddenNotice('Mp', st.mpHealth!, 'Mp|$mk'),
        if (_familyBar(st, eff) case final w?) w,
        for (final ot in _openTrades(st, eff)) _checkButton(st, ot.$1, ot.$2),
        if (hideZero && layers.zero) _hiddenNotice('0.1', st.zeroHealth!, '0.1|$mk'),
        if (eff.zero && st.zero != null && st.zero!.decision.state != 0)
          _decisionBar(st.zero!.decision, st.symbol, tag: '0.1'),
        if (hideAlka && layers.alka) _hiddenNotice('Alka', st.alkaHealth!, 'Alka|$mk'),
        if (eff.alka && st.alka != null && st.alka!.decision.state != 0)
          _decisionBar(st.alka!.decision, st.symbol, tag: 'Alka'),
        if (hideAab && layers.sigs)
          _hiddenNotice('AAB', st.aabHealth!, 'AAB|$mk')
        else if (eff.sigs ||
            (!eff.all && !eff.alka && !eff.mp && !eff.zero && !eff.sm && !eff.km && !eff.dm && !eff.st && !eff.star))
          _decisionBar(st.forecast!.decision, st.symbol, tag: 'AAB'),
      ] else if (!full && st.forecast == null && s != null)
        _bottomBar(s, st.symbol),
    ]);
  }

  /// أول صفقة مفتوحة في المؤشرات المشغّلة (للزر "افحص صفقتي").
  /// كل الصفقات المفتوحة لأول مؤشر مشغّل عنده صفقة (مع محركين: قد تكون شراء + بيع).
  List<(String, PastSignal)> _openTrades(AppState st, ChartLayers eff) {
    final l = <(String, List<PastSignal>?)>[
      if (eff.star) ('نجوم', st.starR?.res.signals),
      if (eff.km) ('KM', st.kmR?.signals),
      if (eff.dm) ('DM', st.dmR?.signals),
      if (eff.st) ('ST', st.stR?.res.signals),
      if (eff.sm) ('SM', st.smR?.signals),
      if (eff.mp) ('Mp', st.mpR?.signals),
      if (eff.all) ('ALL', st.allR?.signals),
      if (eff.zero) ('0.1', st.zero?.signals),
      if (eff.alka) ('Alka', st.alka?.signals),
    ];
    for (final (t, sg) in l) {
      final open = [for (final x in sg ?? const <PastSignal>[]) if (x.exitI < 0) (t, x)];
      if (open.isNotEmpty) return open;
    }
    return const [];
  }

  Widget _checkButton(AppState st, String tag, PastSignal sg) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: SizedBox(
          width: double.infinity,
          height: 36,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gold,
              side: const BorderSide(color: AppColors.gold, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: Text('افحص صفقتي ($tag ${sg.dir > 0 ? 'شراء' : 'بيع'})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            onPressed: () => _showTradeCheck(st, tag, sg),
          ),
        ),
      );

  void _showTradeCheck(AppState st, String tag, PastSignal sg) {
    final r = checkTrade(st.candles, sg);
    if (r == null) return;
    String fr(double x) => '${x >= 0 ? '+' : ''}${x.toStringAsFixed(2)}R';
    final (col, title, odds) = switch (r.state) {
      'strong' => (
          AppColors.up,
          '🟢 زخم قوي — خليها تجري',
          'تاريخياً (ذهب 10 سنوات): النصف الباقي وصل +1R أو أكثر في ~1 من كل 4 صفقات بهذا الوضع، ومتوسطه ~+0.8R'
        ),
      'weak' => (
          AppColors.down,
          '🔴 الحركة تضعف',
          'تاريخياً (ذهب 10 سنوات): النصف الباقي وصل +1R في ~1 من كل 10، ومتوسطه ~+0.3R — الوقف المتحرك يحمي ربحك، ويمكنك تأمينه يدوياً'
        ),
      'normal' => (
          AppColors.gold,
          '🟡 عادية',
          'تاريخياً (ذهب 10 سنوات): النصف الباقي وصل +1R في ~1 من كل 6، ومتوسطه ~+0.5R'
        ),
      _ => (
          AppColors.muted,
          '⏳ لم يتحقق TP1 بعد',
          'الوقف الأصلي ما زال قائماً. بعد TP1 يُغلق النصف ويصبح الوقف عند الدخول، ويظهر هنا تقييم الاستمرار'
        ),
    };
    final board = st.board;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 10),
            Text(
                'فحص الصفقة — $tag ${sg.dir > 0 ? 'شراء' : 'بيع'}${tag == 'نجوم' && st.starR != null ? ' ${'★' * st.starR!.of(sg.i, sg.dir)}${'☆' * (3 - st.starR!.of(sg.i, sg.dir))}' : ''}',
                style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _kv('الآن', fr(r.nowR), r.nowR >= 0 ? AppColors.up : AppColors.down)),
              const SizedBox(width: 8),
              Expanded(
                  child: _kv(r.tp1Hit ? 'مضمون (لو ضُرب الوقف)' : 'أقصى خسارة', fr(r.securedR),
                      r.securedR >= 0 ? AppColors.up : AppColors.down)),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: col.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: col.withOpacity(0.7)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: col, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(odds, style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.4)),
              ]),
            ),
            if (r.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final (pos, t) in r.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(pos ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        size: 16, color: pos ? AppColors.up : AppColors.down),
                    const SizedBox(width: 6),
                    Expanded(child: Text(t, style: const TextStyle(color: AppColors.text, fontSize: 12))),
                  ]),
                ),
            ],
            if (board.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final e in board.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: e.value == sg.dir ? AppColors.up : AppColors.down),
                    ),
                    child: Text('${e.key.toUpperCase()} ${e.value == sg.dir ? 'مع صفقتك' : 'ضدها'}',
                        style: TextStyle(color: e.value == sg.dir ? AppColors.up : AppColors.down, fontSize: 11)),
                  ),
              ]),
            ],
            const SizedBox(height: 10),
            const Text('تقدير من التاريخ وليس ضماناً — الوقف المتحرك يبقى الحماية الأساسية.',
                style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ]),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(v, textDirection: TextDirection.ltr, style: TextStyle(color: col, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      );

  /// قرار مؤشر النجوم مع عدد نجوم الإشارة الحالية.
  Widget _starBar(AppState st) {
    final r = st.starR!;
    final d = r.res.decision;
    var n = 0;
    final oi = r.res.signals.lastIndexWhere((x) => x.exitI < 0);
    if (d.state == 1 && oi >= 0) n = r.of(r.res.signals[oi].i, r.res.signals[oi].dir);
    if (d.state == 2 && r.res.pending.isNotEmpty) n = r.of(r.res.pending.first.i, r.res.pending.first.dir);
    return _decisionBar(d, st.symbol, tag: d.state == 0 ? 'نجوم' : 'نجوم $n/3');
  }

  /// بطاقة قرار واحدة لـ Mp/SM/KM/DM المشغّلة: قرار الأدق الذي عنده صفقة، والاسم يذكر كل المتفقين
  Widget? _familyBar(AppState st, ChartLayers eff) {
    final fam = <(String, AllResult)>[
      if (eff.km && st.kmR != null) ('KM', st.kmR!),
      if (eff.dm && st.dmR != null) ('DM', st.dmR!),
      if (eff.st && st.stR != null) ('ST', st.stR!.res),
      if (eff.sm && st.smR != null) ('SM', st.smR!),
      if (eff.mp && st.mpR != null) ('Mp', st.mpR!),
    ];
    if (fam.isEmpty) return null;
    final active = fam.where((x) => x.$2.decision.state != 0).toList();
    final main = active.isNotEmpty ? active.first : fam.first;
    final d = main.$2.decision;
    const order = ['Mp', 'SM', 'ST', 'DM', 'KM'];
    final same = [
      for (final (t, r) in fam)
        if (r.decision.state == d.state && r.decision.dir == d.dir && (d.state == 0 || r.decision.entry == d.entry)) t
    ]..sort((x, y) => order.indexOf(x).compareTo(order.indexOf(y)));
    return _decisionBar(d, st.symbol, tag: same.join('·'));
  }

  Widget _forecastBar(Forecast f, MarketSymbol sym) {
    final items = <Widget>[];
    if (f.indicators.isNotEmpty) {
      final upN = f.indicators.where((e) => e.bias > 0).length;
      final dnN = f.indicators.where((e) => e.bias < 0).length;
      items.add(InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showPanel(f),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.speed_rounded, size: 17, color: AppColors.gold),
          const SizedBox(width: 5),
          const Icon(Icons.arrow_upward_rounded, size: 13, color: AppColors.up),
          Tag('$upN', color: AppColors.up),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_downward_rounded, size: 13, color: AppColors.down),
          Tag('$dnN', color: AppColors.down),
        ]),
      ));
    }
    final st = context.read<AppState>();
    final inds = _indicators(st);
    final on = inds.where((x) => x.on).toList();
    items.add(const SizedBox(width: 8));
    // زر واحد يذكر المؤشرات المشغّلة (كل اسم بلون حالته) ويفتح لوحة كل المؤشرات
    items.add(Expanded(child: _indButton(on)));
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Row(children: items),
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
                          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
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
        child: Row(children: [
          if (tag.isNotEmpty) ...[
            Tag(tag, color: AppColors.gold),
            const SizedBox(width: 8),
          ],
          const Icon(Icons.hourglass_empty_rounded, size: 14, color: AppColors.muted),
          const SizedBox(width: 4),
          const Expanded(
            child: Text('انتظار — لا توجد إشارة مكتملة الشروط',
                style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }
    final col = d.dir > 0
        ? AppColors.up
        : d.dir < 0
            ? AppColors.down
            : AppColors.muted;
    final label =
        '${tag.isEmpty ? '' : '$tag '}${d.state == 0 ? 'انتظار' : d.state == 1 ? (d.dir > 0 ? 'شراء' : 'بيع') : d.state == 2 ? '⏳ ${d.dir > 0 ? 'شراء' : 'بيع'}' : '⚡ يتكوّن'}';
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
    return InkWell(
      onTap: () => setState(() => why = !why),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: col.withOpacity(0.5), width: 1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: col,
                borderRadius: BorderRadius.circular(7),
              ),
              child:
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: 6),
            if (d.state == 1 || d.state == 2) ...[
              item(d.state == 2 ? 'دخول عند' : 'دخول', d.entry, AppColors.text),
              item('وقف', d.sl, AppColors.down),
              item('TP1', d.tp1, AppColors.up),
              item('TP2', d.tp2, AppColors.up),
              Icon(why ? Icons.expand_more_rounded : Icons.info_outline_rounded, size: 16, color: AppColors.muted),
            ] else
              Expanded(child: Text(d.title, style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
          if (why) ...[
            const SizedBox(height: 6),
            Text(d.state == 1 || d.state == 2 ? '${d.title} • ${d.why}' : d.why,
                style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
          ],
        ]),
      ),
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
          child: Text(dirLabel(s.direction), style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        const SizedBox(width: 6),
        if (active) ...[
          item('دخول', sym.fmt(s.entry), AppColors.accent),
          item('وقف', sym.fmt(s.stopLoss), AppColors.down),
          item('TP1', sym.fmt(s.tp1), AppColors.up),
          item('TP2', sym.fmt(s.tp2), AppColors.up),
          item('TP3', sym.fmt(s.tp3), AppColors.up),
        ] else
          const Expanded(child: Text('لا توجد صفقة — انتظر', style: TextStyle(color: AppColors.muted, fontSize: 12))),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SymbolBadge(st.symbol.code, size: 28),
          const SizedBox(width: 8),
          Text(st.symbol.code,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)),
          const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
        ]),
      ),
    );
  }
}

/// لوحة اتجاهات الفريمات الكبيرة (مثل DTC) في سطر واحد صغير: 1H ▼ 4H ▼ 1D ▲
class _TrendBoard extends StatelessWidget {
  final Map<String, int> board;
  const _TrendBoard({required this.board});
  @override
  Widget build(BuildContext context) {
    Widget chip(String k, int v) {
      final col = v > 0
          ? AppColors.up
          : v < 0
              ? AppColors.down
              : AppColors.muted;
      return Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.fromLTRB(5, 1, 3, 1),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: col.withOpacity(0.8), width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(k.toUpperCase(), style: TextStyle(color: col, fontSize: 9.5, fontWeight: FontWeight.w800)),
          Icon(
              v > 0
                  ? Icons.arrow_drop_up_rounded
                  : v < 0
                      ? Icons.arrow_drop_down_rounded
                      : Icons.remove_rounded,
              size: 15,
              color: col),
        ]),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final k in const ['1h', '4h', '1d'])
          if (board.containsKey(k)) chip(k, board[k]!),
      ]),
    );
  }
}
