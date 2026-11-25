import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../analysis/all_indicator.dart';
import 'package:provider/provider.dart';
import '../analysis/benchmark.dart';
import '../analysis/chart_reader.dart';
import '../analysis/forecast.dart';
import '../analysis/health.dart';
import '../analysis/trade_check.dart';
import '../analysis/lt_indicator.dart';
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
  bool _wasLand = false;

  /// قلب الشاشة: أفقي (الشارت فقط) أو العودة للوضع العمودي.
  Future<void> _rotate(bool landscape) async {
    HapticFeedback.mediumImpact();
    if (landscape) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      // بعد العودة: نسمح بالدوران التلقائي مرة أخرى
      Future.delayed(const Duration(seconds: 2), () => SystemChrome.setPreferredOrientations(const []));
    }
  }
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

  Widget _iconTool(IconData i, String tip, VoidCallback onTap, {bool primary = false, bool on = false}) => Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 29,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              gradient: primary ? AppColors.goldGrad : null,
              color: primary ? null : (on ? AppColors.gold.withOpacity(0.18) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(i, size: 17, color: primary ? AppColors.onAccent : (on ? AppColors.gold : AppColors.text.withOpacity(0.85))),
          ),
        ),
      );

  Widget _tfItem(AppState st, String t) {
    final on = st.tf == t;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => st.setTf(t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          gradient: on ? AppColors.goldGrad : null,
          borderRadius: BorderRadius.circular(8),
          boxShadow: on ? [BoxShadow(color: AppColors.gold.withOpacity(0.35), blurRadius: 8)] : null,
        ),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.3,
                fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                color: on ? AppColors.onAccent : AppColors.muted)),
      ),
    );
  }


  /// كل مؤشراتنا بترتيب واحد (من الأدق للأعم) — للشريط وللوحة المؤشرات.
  List<({String name, String emoji, String desc, IndHealth? health, bool on, VoidCallback toggle})> _indicators(
          AppState st) =>
      [
        (
          name: 'King',
          emoji: '🤖',
          desc: 'ذكاء اصطناعي يقرأ 54 معلومة من السوق ومؤشراتنا — كل إشارة عليها نجوم قوتها: ⭐ 56% • ⭐⭐ 61% • ⭐⭐⭐ 64% (1M/5M: 64% • 67% • 74%)',
          health: st.kingHealthNow,
          on: layers.king,
          toggle: () => layers.king = !layers.king
        ),
        (
          name: 'AK',
          emoji: '🎯',
          desc: 'الأدق: توصيات AAB التي يضعها King في أعلى 15% — علامات شراء وبيع، صفقات قليلة',
          health: st.akHealth,
          on: layers.aiak,
          toggle: () => layers.aiak = !layers.aiak
        ),
        (
          name: 'Q',
          emoji: '🗺️',
          desc: 'يوضّح أين سيكون السعر غالباً في الفترة القادمة، وهل السوق هادئ أو متحرك',
          health: null,
          on: layers.q,
          toggle: () => layers.q = !layers.q
        ),
        (
          name: 'PQ',
          emoji: '🔷',
          desc: 'النجوم + SM + Alka في مؤشر واحد + فهم التوقيت (King): نجمتان فأكثر تكفيهما ثقة جيدة، وغيرها تحتاج ثقة عالية',
          health: null,
          on: layers.pq,
          toggle: () => layers.pq = !layers.pq
        ),
        (
          name: 'LT',
          emoji: '🏔️',
          desc: 'بعيد المدى (يومي، شراء فقط): ترند ~67% وارتداد ~70% — صفقتان تقريباً في الشهر',
          health: null,
          on: layers.lt,
          toggle: () => layers.lt = !layers.lt
        ),
        (
          name: 'نجوم',
          emoji: '⭐',
          desc: 'إشارات Mp ونجوم الثقة + فهم التوقيت (King): كل نجمة أدق، ونجمتان فأكثر تكفيهما ثقة جيدة',
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
          desc: 'SM في السوق الهادئ + فهم التوقيت (King) — صفقات قليلة ودقيقة',
          health: st.kmHealthNow,
          on: layers.km,
          toggle: () => layers.km = !layers.km
        ),
        (
          name: 'ST',
          emoji: '🧠',
          desc: 'نموذج متعلّم: أعلى 30% من إشارات Mp + فهم التوقيت (King)',
          health: st.stHealthNow,
          on: layers.st,
          toggle: () => layers.st = !layers.st
        ),
        (
          name: 'SM',
          emoji: '〰️',
          desc: 'Mp مع شريط المتوسطات + فلتر الذكاء (King أعلى 30%) — «بداية صعود/هبوط» عند تغيّر لون الشريط',
          health: st.smHealthNow,
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
          desc: 'دمج AAB و Alka + فهم التوقيت (King)',
          health: st.allHealthNow,
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
          desc: 'شموع الانعكاس عند الدعم والمقاومة + فهم التوقيت (King)',
          health: st.alkaHealthNow,
          on: layers.alka,
          toggle: () => layers.alka = !layers.alka
        ),
        (
          name: 'AAB',
          emoji: '📈',
          desc: 'توصيات AAB + فلتر الذكاء (King أعلى 30%)',
          health: st.aabHealthNow,
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
        // دقة كل مؤشر على بيانات لم يرها (بهدف 1R) — لشريط الدقة والترتيب
        final acc = <String, double>{
          'AK': 66, 'King': 59.3, 'AAB': 62.4, 'SM': 60.5,
          'نجوم': 61.3, 'PQ': 61.3, 'ST': 60.6, 'KM': 63.3, 'DM': 59.2, 'LT': 67,
          'Mp': 55.7, 'ALL': 60.3, 'Alka': 59.6, '0.1': 51.2,
        };
        final byName = {for (final x in inds) x.name: x};
        const groups = <(String, IconData, List<String>)>[
          ('الأقوى — ذكاء اصطناعي', Icons.emoji_events_rounded, ['AK', 'King', 'AAB', 'SM']),
          ('خريطة الاحتمالات', Icons.map_rounded, ['Q']),
          ('مؤشرات الثقة', Icons.verified_rounded, ['نجوم', 'PQ', 'ST', 'KM', 'DM']),
          ('بعيد المدى', Icons.landscape_rounded, ['LT']),
          ('الأساسية', Icons.layers_rounded, ['Mp', 'ALL', 'Alka', '0.1']),
        ];
        final rankOf = {
          for (final (q, e) in ([...acc.entries.where((e) => e.key != 'LT')]..sort((x, y) => y.value.compareTo(x.value))).indexed) e.key: q + 1
        };
        String live(({String name, String emoji, String desc, IndHealth? health, bool on, VoidCallback toggle}) x) {
          final h = x.health;
          if (x.name == 'نجوم') return st.starMin == 0 ? 'يظهر: كل الإشارات' : 'يظهر: ${st.starMin} نجوم فما فوق';
          if (x.name == 'LT') return _ltStatus(st);
          if (x.name == 'Q') {
            final q = st.qR;
            if (q == null) return 'جاري الحساب…';
            return 'السوق ${q.regimeAr} • ${q.leanUp ? 'أقرب للصعود' : q.leanDown ? 'أقرب للهبوط' : 'الاتجاه غير واضح'}';
          }
          if (x.name == 'PQ') {
            return st.pqV == null || st.pqV!.closed == 0
                ? 'جاري الحساب…'
                : 'الآن ${(st.pqV!.winRate * 100).toStringAsFixed(0)}% من ${st.pqV!.closed}';
          }
          if (h == null) return 'جاري الحساب…';
          if (h.trades < 20) return 'عينة صغيرة (${h.trades} صفقة)';
          return 'الآن ${(h.winRate * 100).toStringAsFixed(0)}% من ${h.trades} صفقة';
        }

        Widget card(({String name, String emoji, String desc, IndHealth? health, bool on, VoidCallback toggle}) x) {
          final h = x.health;
          final col = x.name == 'LT'
              ? ((st.ltR?.signals.any((s) => s.exitI < 0) ?? false) ? AppColors.up : AppColors.muted)
              : switch (h?.light) {
                  'green' => AppColors.up,
                  'yellow' => AppColors.gold,
                  'red' => AppColors.down,
                  _ => AppColors.muted,
                };
          final a = acc[x.name] ?? 50;
          final barCol = a >= 60 ? AppColors.up : a >= 55 ? AppColors.gold : AppColors.muted;
          final rank = rankOf[x.name] ?? 99;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              gradient: x.on
                  ? const LinearGradient(colors: [Color(0xFF241F12), AppColors.card], begin: Alignment.topRight, end: Alignment.bottomLeft)
                  : null,
              color: x.on ? null : AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: x.on ? AppColors.gold : AppColors.border, width: x.on ? 1.4 : 0.8),
              boxShadow: x.on ? [BoxShadow(color: AppColors.gold.withOpacity(0.15), blurRadius: 12)] : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(x.toggle);
                  setSheet(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (rank < 99) Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: rank <= 3 ? AppColors.goldGrad : null,
                          color: rank <= 3 ? null : AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Text('$rank',
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.w900, color: rank <= 3 ? AppColors.onAccent : AppColors.muted)),
                      ),
                      const SizedBox(width: 6),
                      Text(x.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(x.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: x.on ? AppColors.gold : AppColors.text, fontSize: 15, fontWeight: FontWeight.w900)),
                      ),
                      // مفتاح تشغيل صغير
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 34,
                        height: 19,
                        padding: const EdgeInsets.all(2),
                        alignment: x.on ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                        decoration: BoxDecoration(
                          color: x.on ? AppColors.gold : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: x.on ? AppColors.gold : AppColors.border),
                        ),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: x.on ? AppColors.onAccent : AppColors.muted, shape: BoxShape.circle),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(x.desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.3)),
                    const Spacer(),
                    // شريط الدقة (50% → 70%)
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: ((a - 50) / 20).clamp(0.02, 1.0).toDouble(),
                            minHeight: 5,
                            backgroundColor: AppColors.surface,
                            valueColor: AlwaysStoppedAnimation(barCol),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${a.toStringAsFixed(a == a.roundToDouble() ? 0 : 1)}%',
                          style: TextStyle(color: barCol, fontSize: 11.5, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(live(x),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: col, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
          );
        }

        Widget grid(List<String> names) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.42,
              children: [for (final n in names) if (byName[n] != null) card(byName[n]!)],
            );
        Widget optBox(List<Widget> kids) => Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 0.8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
            );
        final onCount = inds.where((x) => x.on).length;
        // King: بدل الاختيار — نجوم على كل إشارة حسب قوتها
        final kingOpts = optBox([
          const Text('نجوم King = قوة الإشارة', style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final (st0, acc, lt) in const [('⭐', '56%', '64%'), ('⭐⭐', '61%', '67%'), ('⭐⭐⭐', '64%', '74%')])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(width: 52, child: Text(st0, style: const TextStyle(fontSize: 12))),
                Text('الدقة ~$acc', style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('1M/5M ~$lt', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
            ),
          const Text('كل ما زادت النجوم: إشارات أقل وأدق. اختبار على سنين لم يرها (هدف 1R، والفريمات الصغيرة بعد السبريد).',
              style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
        ]);
        final starOpts = optBox([
          Row(children: [
            const Text('أقل عدد نجوم:', style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            _seg(const [('0', 'الكل'), ('1', '1'), ('2', '2'), ('3', '3')], '${st.starMin}', (v) {
              st.setStarMin(int.parse(v));
              setSheet(() {});
            }),
          ]),
          const SizedBox(height: 6),
        ]);

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (_, ctl) => ListView(
            controller: ctl,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            children: [
              Center(
                child: Container(
                    width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.auto_graph_rounded, color: AppColors.gold, size: 22),
                const SizedBox(width: 8),
                const Text('المؤشرات', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text('مشغّل: $onCount', style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                if (onCount > 0)
                  TextButton(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 30)),
                    onPressed: () {
                      setState(() {
                        for (final x in inds) {
                          if (x.on) x.toggle();
                        }
                      });
                      setSheet(() {});
                    },
                    child: const Text('إيقاف الكل', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('${st.symbol.code} • ${st.tf.toUpperCase()} — مرتبة من الأدق. النسبة = دقته على بيانات لم يرها (بهدف 1R). السطر الملوّن = أداؤه الآن على هذا السوق (آخر 5000 شمعة).',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
              for (final (title, icon, names) in groups) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Icon(icon, size: 17, color: AppColors.gold),
                  const SizedBox(width: 6),
                  Text(title, style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                grid(names),
                if (names.contains('King') && layers.king) kingOpts,
                if (names.contains('نجوم') && layers.star) starOpts,
              ],
            ],
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        void upd(VoidCallback f) {
          setState(f);
          setSheet(() {});
        }

        Widget head(String t, IconData i) => Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Row(children: [
                Icon(i, size: 16, color: AppColors.gold),
                const SizedBox(width: 6),
                Text(t, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13.5)),
              ]),
            );
        // بلاطة تشغيل/إطفاء: أيقونة + اسم + وصف قصير
        Widget tile(IconData icon, String name, String sub, bool on, VoidCallback toggle) => Material(
              color: on ? AppColors.gold.withOpacity(0.12) : AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: on ? AppColors.gold : AppColors.border, width: on ? 1.3 : 0.8),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => upd(toggle),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Row(children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: on ? AppColors.gold : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 17, color: on ? AppColors.onAccent : AppColors.muted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: on ? AppColors.gold : AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
                        if (sub.isNotEmpty)
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
        Widget grid(List<Widget> c) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3.0,
              children: c,
            );
        final st = context.read<AppState>();
        final onCount = _indicators(st).where((x) => x.on).length;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.95,
          builder: (_, ctl) => ListView(
            controller: ctl,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 10),
              const Row(children: [
                Icon(Icons.layers_rounded, size: 20, color: AppColors.gold),
                SizedBox(width: 8),
                Text('طبقات الشارت', style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
              ]),
              // المؤشرات لها لوحتها الخاصة
              const SizedBox(height: 12),
              Material(
                color: AppColors.card,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.gold, width: 1)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showIndicators();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.auto_graph_rounded, color: AppColors.gold, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('المؤشرات والتوصيات',
                              style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800)),
                          Text('النجوم، LT، SM، ST، KM، ALL، Alka… — المشغّل الآن: $onCount',
                              style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                        ]),
                      ),
                      const Icon(Icons.chevron_left_rounded, color: AppColors.gold),
                    ]),
                  ),
                ),
              ),
              // أوضاع جاهزة بلمسة واحدة
              const SizedBox(height: 12),
              Row(children: [
                for (final (name, icon, apply) in <(String, IconData, VoidCallback)>[
                  ('نظيف', Icons.cleaning_services_outlined, () {
                    layers
                      ..ema = false
                      ..sr = false
                      ..zones = false
                      ..levels = false
                      ..vp = false
                      ..vwap = false
                      ..fib = false
                      ..ce = false
                      ..pats = false
                      ..algo = false;
                  }),
                  ('ترند', Icons.trending_up_rounded, () {
                    layers
                      ..ema = true
                      ..sr = true
                      ..zones = false
                      ..levels = false
                      ..vp = false
                      ..vwap = false
                      ..fib = false
                      ..ce = true;
                  }),
                  ('مناطق', Icons.crop_square_rounded, () {
                    layers
                      ..ema = false
                      ..sr = true
                      ..zones = true
                      ..levels = true
                      ..vp = false
                      ..vwap = false
                      ..fib = true
                      ..ce = false;
                  }),
                  ('حجم', Icons.stacked_bar_chart_rounded, () {
                    layers
                      ..ema = false
                      ..sr = false
                      ..zones = false
                      ..levels = false
                      ..vp = true
                      ..vwap = true
                      ..vol = true
                      ..fib = false
                      ..ce = false;
                  }),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Material(
                        color: AppColors.card,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11), side: const BorderSide(color: AppColors.border, width: 0.8)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => upd(apply),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(icon, size: 19, color: AppColors.gold),
                              const SizedBox(height: 3),
                              Text(name,
                                  style: const TextStyle(color: AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
              head('شكل الشارت', Icons.candlestick_chart_rounded),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _seg(const [('candle', 'شموع'), ('ha', 'Heikin Ashi'), ('line', 'خطي')], layers.type,
                    (v) => upd(() => layers.type = v)),
                _seg(const [('rsi', 'RSI'), ('macd', 'MACD'), ('none', 'بدون')], layers.sub,
                    (v) => upd(() => layers.sub = v)),
              ]),
              const SizedBox(height: 8),
              grid([
                tile(Icons.bar_chart_rounded, 'الحجم', 'أعمدة أسفل الشموع', layers.vol, () => layers.vol = !layers.vol),
                tile(Icons.palette_outlined, 'AAB Algo', 'تلوين الشموع + خط الاتجاه', layers.algo,
                    () => layers.algo = !layers.algo),
                tile(Icons.auto_awesome_outlined, 'توقع الشمعة', 'الشمعة القادمة', layers.fc, () => layers.fc = !layers.fc),
                tile(Icons.text_fields_rounded, 'أنماط الشموع', 'أسماء النماذج', layers.pats,
                    () => layers.pats = !layers.pats),
              ]),
              head('خطوط ومستويات', Icons.straighten_rounded),
              grid([
                tile(Icons.align_vertical_center_rounded, 'الدعم والمقاومة', 'العليا والسفلى والقريبة', layers.sr,
                    () => layers.sr = !layers.sr),
                tile(Icons.show_chart_rounded, 'EMA 20/50/200', 'المتوسطات', layers.ema, () => layers.ema = !layers.ema),
                tile(Icons.crop_square_rounded, 'OB / FVG', 'مناطق وفجوات', layers.zones, () => layers.zones = !layers.zones),
                tile(Icons.schedule_rounded, 'مستويات اليوم', 'PDH/PDL والجلسات', layers.levels,
                    () => layers.levels = !layers.levels),
                tile(Icons.stacked_bar_chart_rounded, 'Volume Profile', 'مناطق الحجم', layers.vp, () => layers.vp = !layers.vp),
                tile(Icons.timeline_rounded, 'VWAP', 'متوسط مرجّح بالحجم', layers.vwap, () => layers.vwap = !layers.vwap),
                tile(Icons.percent_rounded, 'Fibonacci', 'نسب التصحيح', layers.fib, () => layers.fib = !layers.fib),
                tile(Icons.exit_to_app_rounded, 'Chandelier Exit', 'وقف متحرك', layers.ce, () => layers.ce = !layers.ce),
              ]),
              head('خيارات الصفقات', Icons.tune_rounded),
              grid([
                tile(Icons.add_circle_outline_rounded, 'إشارات بعد TP1', 'نفس الاتجاه «+» — مطفأ افتراضياً',
                    st.settings.extraSameDir, () {
                  st.setEngineOptions(extraSameDir: !st.settings.extraSameDir);
                }),
              ]),
            ],
          ),
        );
      }),
    );
  }

  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.signal;
    final mk = '${st.symbol.code}|${st.tf}';
    final auto = st.settings.autoHideWeak;
    final hideAab = auto && st.aabHealthNow?.light == 'red' && !forceShow.contains('AAB|$mk');
    final hideAlka = auto && st.alkaHealthNow?.light == 'red' && !forceShow.contains('Alka|$mk');
    final hideDm = auto && st.dmHealth?.light == 'red' && !forceShow.contains('DM|$mk');
    final hideSt = auto && st.stHealthNow?.light == 'red' && !forceShow.contains('ST|$mk');
    final hideKm = auto && st.kmHealthNow?.light == 'red' && !forceShow.contains('KM|$mk');
    final hideSm = auto && st.smHealthNow?.light == 'red' && !forceShow.contains('SM|$mk');
    final hideMp = auto && st.mpHealth?.light == 'red' && !forceShow.contains('Mp|$mk');
    final hideZero = auto && st.zeroHealth?.light == 'red' && !forceShow.contains('0.1|$mk');
    final hideAll = auto && st.allHealthNow?.light == 'red' && !forceShow.contains('ALL|$mk');
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAlerts(st, eff));
    // الوضع الأفقي (قلب الشاشة): الشارت وحده يملأ الشاشة مثل TradingView
    final land = MediaQuery.orientationOf(context) == Orientation.landscape;
    final fs = full || land;
    if (land != _wasLand) {
      _wasLand = land;
      SystemChrome.setEnabledSystemUIMode(land ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
    return Column(children: [
      // صف 1: الرمز والسعر + أدوات (قراءة، مقارنة، طبقات، شاشة كاملة)
      if (!land)
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
          // مجموعة الأدوات في شريط واحد (مثل TradingView)
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _iconTool(Icons.auto_graph_rounded, 'قراءة الشارت', () => _showReading(st), primary: true),
              _iconTool(Icons.leaderboard_outlined, 'مقارنة المؤشرات', () => _showBench(st)),
              _iconTool(Icons.align_vertical_center_rounded, 'الدعم والمقاومة', () => setState(() => layers.sr = !layers.sr),
                  on: layers.sr),
              _iconTool(Icons.layers_outlined, 'الطبقات', _showLayers),
              _iconTool(Icons.screen_rotation_rounded, 'قلب الشاشة', () => _rotate(true)),
              _iconTool(
                  full ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded, full ? 'إظهار الأدوات' : 'شاشة كاملة',
                  () {
                setState(() => full = !full);
                st.setChartFull(full);
              }),
            ]),
          ),
        ]),
      ),
      if (!fs)
        // صف 2: الأُطر الزمنية | المؤشرات (مع لون حالتها)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 3),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.7),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(children: [for (final t in AppState.timeframes.reversed) Expanded(child: _tfItem(st, t))]),
            ),
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
              alka: st.alkaV,
              zero: st.zero,
              mpR: st.mpR,
              smR: st.smView,
              kmR: st.kmV,
              dmR: st.dmR,
              stR: st.stV,
              starR: st.starV,
              ltR: st.ltR,
              pqR: st.pqV,
              akR: st.akR,
              qR: st.qR,
              kingR: st.kingR,
              allR: st.allV,
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
              top: 60,
              left: 6,
              child: IgnorePointer(child: _TrendBoard(board: st.board)),
            ),
          if (eff.q && st.qR != null && !land)
            Positioned(
              bottom: 26,
              left: 6,
              child: IgnorePointer(child: _QCard(st: st)),
            ),
          if (land)
            Positioned(
              top: 6,
              right: 70,
              child: _LandBar(st: st, onExit: () => _rotate(false), onLayers: _showLayers, onInds: _showIndicators),
            ),
        ]),
      ),
      // الشاشة الكاملة: الشارت وحده بدون أي أشرطة
      if (!fs && st.forecast != null) ...[
        if (sel != null && sel! < st.candles.length)
          _candlePanel(st, sel!)
        else if (!fs)
          _forecastBar(st.forecast!, st.symbol),
        if (hideAll && layers.all) _hiddenNotice('ALL', st.allHealthNow!, 'ALL|$mk'),
        if (hideDm && layers.dm) _hiddenNotice('DM', st.dmHealth!, 'DM|$mk'),
        if (hideSt && layers.st) _hiddenNotice('ST', st.stHealthNow!, 'ST|$mk'),
        if (hideKm && layers.km) _hiddenNotice('KM', st.kmHealthNow!, 'KM|$mk'),
        if (hideSm && layers.sm) _hiddenNotice('SM', st.smHealthNow!, 'SM|$mk'),
        if (hideMp && layers.mp) _hiddenNotice('Mp', st.mpHealth!, 'Mp|$mk'),
        if (hideZero && layers.zero) _hiddenNotice('0.1', st.zeroHealth!, '0.1|$mk'),
        if (hideAlka && layers.alka) _hiddenNotice('Alka', st.alkaHealthNow!, 'Alka|$mk'),
        if (hideAab && layers.sigs) _hiddenNotice('AAB', st.aabHealthNow!, 'AAB|$mk'),
        ..._bars(st, eff, showAab: !(hideAab && layers.sigs)),
      ] else if (!fs && st.forecast == null && s != null)
        _bottomBar(s, st.symbol),
    ]);
  }

  /// أشرطة القرار مجمّعة: الصفقة نفسها من أكثر من مؤشر = شريط واحد يذكرهم كلهم،
  /// والمؤشرات المنتظرة كلها في سطر واحد صغير — حتى يبقى الشارت كبيراً.
  List<Widget> _bars(AppState st, ChartLayers eff, {bool showAab = true}) {
    final e = <(String, Decision, String?)>[];
    if (eff.star && st.starV != null) {
      final r = st.starV!;
      final d = r.res.decision;
      var n = 0;
      final oi = r.res.signals.lastIndexWhere((x) => x.exitI < 0);
      if (d.state == 1 && oi >= 0) n = r.of(r.res.signals[oi].i, r.res.signals[oi].dir);
      if (d.state == 2 && r.res.pending.isNotEmpty) n = r.of(r.res.pending.first.i, r.res.pending.first.dir);
      e.add((d.state == 0 ? 'نجوم' : 'نجوم $n/3', d, null));
    }
    if (eff.king && st.kingR != null) e.add(('King', st.kingR!.res.decision, null));
    if (eff.aiak && st.akR != null) e.add(('AK', st.akR!.decision, null));
    if (eff.pq && st.pqV != null) e.add(('PQ', st.pqV!.decision, null));
    if (eff.lt) e.add(_ltEntry(st));
    final fam = <(String, AllResult)>[
      if (eff.km && st.kmV != null) ('KM', st.kmV!),
      if (eff.dm && st.dmR != null) ('DM', st.dmR!),
      if (eff.st && st.stV != null) ('ST', st.stV!.res),
      if (eff.sm && st.smView != null) ('SM', st.smView!),
      if (eff.mp && st.mpR != null) ('Mp', st.mpR!),
    ];
    for (final (t, r) in fam) {
      e.add((t, r.decision, null));
    }
    if (eff.all && st.allV != null) e.add(('ALL', st.allV!.decision, null));
    if (eff.zero && st.zero != null) e.add(('0.1', st.zero!.decision, null));
    if (eff.alka && st.alkaV != null) e.add(('Alka', st.alkaV!.decision, null));
    final anyInd = eff.all || eff.alka || eff.mp || eff.zero || eff.sm || eff.km || eff.dm || eff.st || eff.star || eff.lt || eff.pq || eff.king || eff.aiak;
    if (showAab && st.forecast != null && (eff.sigs || !anyInd)) e.add(('AAB', st.forecast!.decision, null));

    // تجميع الصفقات المتطابقة
    final groups = <String, (List<String>, Decision)>{};
    final waiting = <(String, String?)>[];
    for (final (t, d, w) in e) {
      if (d.state == 0) {
        waiting.add((t, w));
        continue;
      }
      final k = '${d.state}|${d.dir}|${st.symbol.fmt(d.entry)}';
      final g = groups[k];
      if (g == null) {
        groups[k] = ([t], d);
      } else {
        g.$1.add(t);
      }
    }
    // زر فحص الصفقة داخل الشريط نفسه (بدل زر كامل العرض)
    final open = _openTrades(st, eff);
    final price = st.candles.isEmpty ? double.nan : st.candles.last.close;
    VoidCallback? checkFor(Decision d) {
      if (d.state != 1) return null;
      for (final (t, sg) in open) {
        if (sg.dir == d.dir && st.symbol.fmt(sg.entry) == st.symbol.fmt(d.entry)) {
          return () => _showTradeCheck(st, t, sg);
        }
      }
      return null;
    }

    return [
      for (final g in groups.values)
        _decisionBar(g.$2, st.symbol, tag: g.$1.join(' · '), price: price, onCheck: checkFor(g.$2)),
      if (waiting.isNotEmpty) _waitLine(waiting),
    ];
  }

  /// سطر واحد صغير للمؤشرات التي لا صفقة لها الآن.
  Widget _waitLine(List<(String, String?)> w) {
    final spans = <InlineSpan>[];
    for (final (i, (t, why)) in w.indexed) {
      if (i > 0) spans.add(const TextSpan(text: '  •  ', style: TextStyle(color: AppColors.border)));
      // عزل كل عنصر (الاسم + السبب) حتى لا يختلط ترتيب العربي والإنجليزي بين المؤشرات
      spans.add(TextSpan(text: '\u2067$t', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)));
      spans.add(TextSpan(text: why != null ? ' ($why)\u2069' : '\u2069', style: const TextStyle(color: AppColors.muted)));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        const Icon(Icons.hourglass_empty_rounded, size: 13, color: AppColors.muted),
        const SizedBox(width: 5),
        const Text('انتظار: ', style: TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
        Expanded(
          child: Text.rich(TextSpan(children: spans),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
        ),
      ]),
    );
  }

  /// أول صفقة مفتوحة في المؤشرات المشغّلة (للزر "افحص صفقتي").
  /// كل الصفقات المفتوحة لأول مؤشر مشغّل عنده صفقة (مع محركين: قد تكون شراء + بيع).
  List<(String, PastSignal)> _openTrades(AppState st, ChartLayers eff) {
    final l = <(String, List<PastSignal>?)>[
      if (eff.star) ('نجوم', st.starV?.res.signals),
      if (eff.king) ('King', st.kingR?.res.signals),
      if (eff.aiak) ('AK', st.akR?.signals),
      if (eff.pq) ('PQ', st.pqV?.signals),
      if (eff.lt && st.tf == '1d') ('LT', st.ltR?.signals),
      if (eff.km) ('KM', st.kmV?.signals),
      if (eff.dm) ('DM', st.dmR?.signals),
      if (eff.st) ('ST', st.stV?.res.signals),
      if (eff.sm) ('SM', st.smView?.signals),
      if (eff.mp) ('Mp', st.mpR?.signals),
      if (eff.all) ('ALL', st.allV?.signals),
      if (eff.zero) ('0.1', st.zero?.signals),
      if (eff.alka) ('Alka', st.alkaV?.signals),
    ];
    for (final (t, sg) in l) {
      final open = [for (final x in sg ?? const <PastSignal>[]) if (x.exitI < 0) (t, x)];
      if (open.isNotEmpty) return open;
    }
    return const [];
  }

  /// تنبيه فوري: أول ما تظهر إشارة جديدة (عند إغلاق الشمعة) في أي مؤشر مشغّل — اهتزاز + شريط تنبيه.
  final Set<String> _seenSig = {};
  String _seenMk = '';
  DateTime _seenAt = DateTime(2000);
  void _checkAlerts(AppState st, ChartLayers eff) {
    final n = st.candles.length;
    if (n < 3) return;
    final mk = '${st.symbol.code}|${st.tf}';
    if (mk != _seenMk) _seenAt = DateTime.now();
    _seenMk = mk;
    // أول ثوانٍ بعد تغيير الرمز/الفريم: نسجّل الإشارات الموجودة بدون تنبيه (حتى تكتمل البيانات)
    final first = st.loading || DateTime.now().difference(_seenAt).inSeconds < 8;
    final l = <(String, List<PastSignal>?, List<PendingSetup>?)>[
      if (eff.king) ('King', st.kingR?.res.signals, st.kingR?.res.pending),
      if (eff.star) ('نجوم', st.starV?.res.signals, st.starV?.res.pending),
      if (eff.aiak) ('AK', st.akR?.signals, st.akR?.pending),
      if (eff.pq) ('PQ', st.pqV?.signals, st.pqV?.pending),
      if (eff.sm) ('SM', st.smView?.signals, st.smView?.pending),
      if (eff.st) ('ST', st.stV?.res.signals, st.stV?.res.pending),
      if (eff.km) ('KM', st.kmV?.signals, st.kmV?.pending),
      if (eff.mp) ('Mp', st.mpR?.signals, st.mpR?.pending),
      if (eff.sigs) ('AAB', st.forecast?.signals, st.forecast?.pending),
    ];
    final fresh = <String>[];
    for (final (name, sg, pd) in l) {
      for (final x in sg ?? const <PastSignal>[]) {
        if (x.exitI >= 0 || x.i < n - 3) continue;
        if (_seenSig.add('$mk|$name|s|${x.i}|${x.dir}') && !first) {
          fresh.add('$name: ${x.dir > 0 ? 'شراء' : 'بيع'} الآن عند ${st.symbol.fmt(x.entry)}');
        }
      }
      for (final p in pd ?? const <PendingSetup>[]) {
        if (p.i < n - 3) continue;
        if (_seenSig.add('$mk|$name|p|${p.i}|${p.dir}') && !first) {
          fresh.add('$name: ${p.dir > 0 ? 'شراء' : 'بيع'} عند ${p.dir > 0 ? 'اختراق' : 'كسر'} ${st.symbol.fmt(p.trigger)}');
        }
      }
    }
    if (fresh.isEmpty || !mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 90),
        backgroundColor: AppColors.card,
        duration: const Duration(seconds: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.gold)),
        content: Row(children: [
          const Icon(Icons.notifications_active_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('إشارة جديدة — ${st.symbol.code} ${st.tf.toUpperCase()}\n${fresh.take(3).join('\n')}',
                style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ));
  }

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

  /// سطر حالة LT في لوحة المؤشرات.
  String _ltStatus(AppState st) {
    final d = st.tf == '1d' ? st.candles : st.daily;
    if (d == null) return 'تحميل الشموع اليومية…';
    if (d.length < 230) return 'يحتاج 230 يوماً (المتاح ${d.length})';
    final r = st.ltR;
    if (r == null) return 'تحميل الشموع اليومية…';
    final oi = r.signals.lastIndexWhere((x) => x.exitI < 0);
    if (oi >= 0) {
      final s = r.signals[oi];
      final px = st.candles.isEmpty ? s.entry : st.candles.last.close;
      final p = (px / s.entry - 1) * 100;
      return 'صفقة ${r.sources[oi]} مفتوحة ${p >= 0 ? '+' : ''}${p.toStringAsFixed(1)}%';
    }
    return ltUptrend(d) ? 'لا صفقة — السوق صاعد، انتظر' : 'لا صفقة — تحت متوسط 200 (لا شراء)';
  }

  /// LT كمدخل لأشرطة القرار: (الاسم، القرار، سبب الانتظار).
  (String, Decision, String?) _ltEntry(AppState st) {
    const none = Decision(0, 0, double.nan, double.nan, double.nan, double.nan, '', '');
    final r = st.ltR;
    if (r == null) return ('LT', none, _ltStatus(st));
    final d = r.decision;
    if (d.state != 0) {
      final oi = r.signals.lastIndexWhere((x) => x.exitI < 0);
      return ('LT ${oi >= 0 ? r.sources[oi] : ''}'.trim(), d, null);
    }
    final up = ltUptrend(st.tf == '1d' ? st.candles : (st.daily ?? const []));
    return ('LT', none, up ? 'فوق متوسط 200 يوم — انتظر شراء' : 'تحت متوسط 200 يوم — لا شراء');
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
  Widget _decisionBar(Decision d, MarketSymbol sym,
      {String tag = '', String? waitText, double price = double.nan, VoidCallback? onCheck}) {
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
          Expanded(
            child: Text(waitText ?? 'انتظار — لا توجد إشارة مكتملة الشروط',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(children: [
              Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(v.isNaN ? '-' : sym.fmt(v),
                    style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                if (d.state == 1 && !price.isNaN)
                  Builder(builder: (_) {
                    final risk = !d.risk.isNaN && d.risk > 0 ? d.risk : (d.entry - d.sl).abs();
                    final r = risk > 0 ? (price - d.entry) * d.dir / risk : double.nan;
                    if (r.isNaN) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(5)),
                      child: Text('الآن \u2066${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)}R\u2069',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                              color: r >= 0 ? const Color(0xFFB9F6CA) : const Color(0xFFFFCDD2),
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    );
                  }),
              ]),
            ),
            const SizedBox(width: 6),
            if (d.state == 1 || d.state == 2) ...[
              item(d.state == 2 ? 'دخول عند' : 'دخول', d.entry, AppColors.text),
              item('وقف', d.sl, AppColors.down),
              item('TP1', d.tp1, AppColors.up),
              item('TP2', d.tp2, AppColors.up),
              if (onCheck != null)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onCheck,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.gold, width: 1),
                    ),
                    child: const Icon(Icons.manage_search_rounded, size: 17, color: AppColors.gold),
                  ),
                )
              else
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
    final c = st.candles;
    double? px, chg;
    if (c.isNotEmpty) {
      px = c.last.close;
      // التغيّر اليومي: من إغلاق اليوم السابق (اليومي) أو من افتتاح أول شمعة اليوم
      final d = st.daily;
      double? ref;
      if (d != null && d.length >= 2) {
        final today = c.last.time.toUtc();
        final lastD = d.last.time.toUtc();
        ref = (lastD.year == today.year && lastD.month == today.month && lastD.day == today.day) ? d[d.length - 2].close : d.last.close;
      } else {
        final day = c.last.time.toUtc().day;
        for (var q = c.length - 1; q >= 0 && c[q].time.toUtc().day == day; q--) {
          ref = c[q].open;
        }
      }
      if (ref != null && ref > 0) chg = (px - ref) / ref * 100;
    }
    final col = (chg ?? 0) >= 0 ? AppColors.up : AppColors.down;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showSymbolSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SymbolBadge(st.symbol.code, size: 30),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(st.symbol.code,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppColors.text, height: 1.1)),
              const Icon(Icons.expand_more, size: 16, color: AppColors.muted),
            ]),
            if (px != null)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(st.symbol.fmt(px),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: col, height: 1.2)),
                  if (chg != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                      decoration: BoxDecoration(color: col.withOpacity(0.16), borderRadius: BorderRadius.circular(4)),
                      child: Text('${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: col)),
                    ),
                  ],
                ]),
              ),
          ]),
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


/// شريط عائم صغير فوق الشارت في الوضع الأفقي: الرمز والسعر، الفريمات، المؤشرات/الطبقات، والعودة.
class _LandBar extends StatelessWidget {
  final AppState st;
  final VoidCallback onExit, onLayers, onInds;
  const _LandBar({required this.st, required this.onExit, required this.onLayers, required this.onInds});
  @override
  Widget build(BuildContext context) {
    final c = st.candles;
    final px = c.isEmpty ? double.nan : c.last.close;
    Widget btn(IconData i, VoidCallback f, {bool gold = false}) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: f,
          child: Container(
            width: 30,
            height: 28,
            decoration: BoxDecoration(
              gradient: gold ? AppColors.goldGrad : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(i, size: 17, color: gold ? AppColors.onAccent : AppColors.text),
          ),
        );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(st.symbol.code, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 12.5)),
        const SizedBox(width: 6),
        if (!px.isNaN)
          Text(st.symbol.fmt(px), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(width: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final t in AppState.timeframes.reversed)
              InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => st.setTf(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: st.tf == t ? AppColors.goldGrad : null,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(t.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: st.tf == t ? AppColors.onAccent : AppColors.muted)),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 6),
        btn(Icons.auto_graph_rounded, onInds),
        btn(Icons.layers_outlined, onLayers),
        btn(Icons.screen_lock_portrait_rounded, onExit, gold: true),
      ]),
    );
  }
}


/// بطاقة Q الصغيرة (مبسّطة): حال السوق، أين سيكون السعر غالباً، وأي جهة أقرب.
class _QCard extends StatelessWidget {
  final AppState st;
  const _QCard({required this.st});
  @override
  Widget build(BuildContext context) {
    final q = st.qR!;
    final sym = st.symbol;
    final mood = const ['السوق هادئ — حركة صغيرة', 'السوق عادي', 'السوق متحرك — حركة كبيرة'][q.regime];
    final col = q.regime == 2 ? AppColors.down : (q.regime == 0 ? AppColors.up : AppColors.gold);
    final lean = q.leanUp
        ? ('أقرب للصعود', AppColors.up)
        : q.leanDown
            ? ('أقرب للهبوط', AppColors.down)
            : ('الاتجاه غير واضح', AppColors.muted);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.93),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withOpacity(0.6), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Q', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(width: 6),
          Flexible(child: Text(mood, style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 3),
        const Text('السعر غالباً سيكون بين:', style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
        Text('\u2066${sym.fmt(q.band(1, 12))}  —  ${sym.fmt(q.band(3, 12))}\u2069',
            style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(lean.$1, style: TextStyle(color: lean.$2, fontSize: 11, fontWeight: FontWeight.w700)),
        if (q.arrowStats.$2 > 0)
          Text('أسهم Q على هذا الشارت: صحيحة ${q.arrowStats.$1} من ${q.arrowStats.$2} (${(q.arrowStats.$1 / q.arrowStats.$2 * 100).round()}%)',
              style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      ]),
    );
  }
}
