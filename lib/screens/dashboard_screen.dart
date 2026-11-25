import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../analysis/all_indicator.dart';
import '../analysis/forecast.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/signal_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final sig = st.signal;
    return RefreshIndicator(
      onRefresh: st.refresh,
      child: ListView(
        padding: const EdgeInsets.all(14),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const WatchStrip(),
          const SizedBox(height: 12),
          _PriceHero(st: st),
          const SizedBox(height: 12),
          if (st.error != null) ErrorBanner(st.error!),
          if (st.loading && sig == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (st.mpR != null) ...[
            _BestNow(st: st),
            _IndicatorsNow(st: st),
            _RecentTrades(st: st),
          ],
          if (sig != null)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  iconColor: AppColors.gold,
                  collapsedIconColor: AppColors.muted,
                  leading: const Icon(Icons.analytics_outlined, color: AppColors.gold, size: 20),
                  title: const Text('التحليل التفصيلي',
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
                  subtitle: const Text('المحرك الأساسي، أسباب الإشارة، المؤشرات الفنية، نماذج الشموع',
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [
                    SignalCard(sig: sig, sym: st.symbol),
                    _AiPanel(st: st, sig: sig),
                    _ReasonsPanel(sig: sig),
                    _IndicatorsPanel(sig: sig),
                    _PatternsPanel(sig: sig),
                  ],
                ),
              ),
            ),
          const _Disclaimer(),
        ],
      ),
    );
  }

  static String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

/// بطاقة القرار الرئيسية: قرار مؤشر Mp الآن (دمج مؤشراتنا الأربعة).
/// بطاقة السعر: الرمز، السعر، التغير، خط السعر المصغر، والأُطر الزمنية.
class _PriceHero extends StatelessWidget {
  final AppState st;
  const _PriceHero({required this.st});
  @override
  Widget build(BuildContext context) {
    final c = st.candles;
    final price = st.signal?.price ?? (c.isEmpty ? double.nan : c.last.close);
    double chg = 0;
    if (c.length > 2) {
      final dayStart = c.lastIndexWhere((k) => k.time.day != c.last.time.day);
      final ref = c[dayStart < 0 ? 0 : dayStart].close;
      chg = (c.last.close - ref) / ref * 100;
    }
    final col = chg >= 0 ? AppColors.up : AppColors.down;
    final closes = [for (final k in c.skip(math.max(0, c.length - 90))) k.close];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1710), Color(0xFF111114)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(color: AppColors.accent.withOpacity(0.35), width: 0.8),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SymbolButton(),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(price.isNaN ? '—' : st.symbol.fmt(price),
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.15)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: col.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(chg >= 0 ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                      color: col, size: 18),
                  Text('${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}% اليوم',
                      style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 6),
        Sparkline(closes, color: col, height: 84),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: TfTabs(current: st.tf, onPick: st.setTf, height: 38),
        ),
        if (st.lastUpdate != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: AppColors.up, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('آخر تحديث ${DashboardScreen._hhmmss(st.lastUpdate!)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
      ]),
    );
  }
}

class _AllHero extends StatelessWidget {
  final AppState st;
  const _AllHero({required this.st});

  @override
  Widget build(BuildContext context) {
    final d = st.mpR!.decision;
    final sym = st.symbol;
    final h = st.mpHealth;
    final col = d.state == 0 ? AppColors.muted : (d.dir > 0 ? AppColors.up : AppColors.down);
    final head = d.state == 0
        ? 'لا توجد صفقة الآن'
        : '${d.dir > 0 ? 'شراء' : 'بيع'} • ${d.state == 1 ? 'صفقة مفتوحة' : 'ينتظر التأكيد'}';
    Widget lv(String k, double v, Color c) => Expanded(
          child: Column(children: [
            Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 2),
            Text(v.isNaN ? '—' : sym.fmt(v),
                style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        gradient: AppColors.goldGrad,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(0.18), blurRadius: 18)],
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          gradient: const LinearGradient(
            colors: [Color(0xFF1C1912), AppColors.card],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  gradient: AppColors.goldGrad, borderRadius: BorderRadius.circular(20)),
              child: const Text('Mp',
                  style: TextStyle(
                      color: AppColors.onAccent, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('القرار الآن',
                  style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
            ),
            if (h != null)
              Text('${h.dot} ${h.label} • ${(h.winRate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          Text(head,
              style: TextStyle(color: col, fontSize: 22, fontWeight: FontWeight.w800)),
          if (d.why.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(d.why,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
          ],
          if (d.state != 0) ...[
            const SizedBox(height: 14),
            Row(children: [
              lv(d.state == 2 ? 'الدخول عند' : 'الدخول', d.entry, AppColors.text),
              lv('الوقف', d.sl, AppColors.down),
              lv('الهدف 1', d.tp1, AppColors.up),
              lv('الهدف 2', d.tp2, AppColors.up),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _AiPanel extends StatelessWidget {
  final AppState st;
  final TradeSignal sig;
  const _AiPanel({required this.st, required this.sig});

  @override
  Widget build(BuildContext context) {
    if (!st.settings.useAi || !st.settings.hasGemini) return const SizedBox.shrink();
    if (sig.direction == Direction.neutral) return const SizedBox.shrink();
    final v = sig.aiVerdict;
    final mine = sig.direction == Direction.buy ? 'BUY' : 'SELL';
    Color c = AppColors.muted;
    String t = 'Gemini يراجع الإشارة…';
    if (v != null) {
      if (v == mine) {
        c = AppColors.up;
        t = 'Gemini يؤكد الإشارة';
      } else if (v == 'WAIT') {
        c = AppColors.gold;
        t = 'Gemini ينصح بالانتظار';
      } else {
        c = AppColors.down;
        t = 'Gemini يخالف الإشارة';
      }
    }
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(t,
                  style: TextStyle(color: c, fontWeight: FontWeight.bold))),
          if (st.aiLoading)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (sig.aiComment != null) ...[
          const SizedBox(height: 8),
          Text(sig.aiComment!,
              style: const TextStyle(color: AppColors.text, height: 1.5)),
        ],
        if (st.aiError != null && sig.aiComment == null) ...[
          const SizedBox(height: 8),
          Text(st.aiError!,
              style: const TextStyle(color: AppColors.down, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _ReasonsPanel extends StatelessWidget {
  final TradeSignal sig;
  const _ReasonsPanel({required this.sig});
  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'أسباب الإشارة',
      icon: Icons.fact_check_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in sig.reasons.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_left_rounded, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(r,
                      style: const TextStyle(
                          color: AppColors.text, fontSize: 13, height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}

class _IndicatorsPanel extends StatelessWidget {
  final TradeSignal sig;
  const _IndicatorsPanel({required this.sig});
  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'المؤشرات الفنية',
      icon: Icons.speed_outlined,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (k, v) in sig.votes.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: k == sig.votes.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5), width: 0.6)),
            ),
            child: Row(children: [
              SizedBox(
                  width: 92,
                  child: Text(v.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Expanded(
                  child: Text(v.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12))),
              const SizedBox(width: 8),
              Tag(
                  v.vote > 0
                      ? 'صاعد'
                      : v.vote < 0
                          ? 'هابط'
                          : 'محايد',
                  color: v.vote > 0
                      ? AppColors.up
                      : v.vote < 0
                          ? AppColors.down
                          : AppColors.muted),
            ]),
          ),
      ]),
    );
  }
}

class _PatternsPanel extends StatelessWidget {
  final TradeSignal sig;
  const _PatternsPanel({required this.sig});
  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'نماذج الشموع اليابانية',
      icon: Icons.candlestick_chart_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (sig.patterns.isEmpty)
          const Text('لا يوجد نموذج شموع واضح على آخر الشموع.',
              style: TextStyle(color: AppColors.muted, fontSize: 13))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in sig.patterns)
              Tag(p.ar,
                  color: p.bias > 0
                      ? AppColors.up
                      : p.bias < 0
                          ? AppColors.down
                          : AppColors.gold),
          ]),
      ]),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'تنبيه: التوصيات تحليل فني مبني على الاحتمالات وليست نصيحة مالية ولا تضمن الربح. لا تخاطر بأكثر مما تتحمل خسارته.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
        ),
      );
}


/// مؤشراتنا مرتبة من الأقوى (دقة اختبار لم يره بهدف 1R).
List<(String, String, double, AllResult?)> _ranked(AppState st) => [
      ('AK', '🎯', 66, st.akR),
      ('King', '🤖', st.kingTop == 15 ? 62.4 : 59.5, st.kingR?.res),
      ('AAB', '📈', 62.4, null),
      ('SM', '〰️', 60.5, st.smView),
      ('النجوم', '⭐', 59.7, st.starV?.res),
      ('Mp', '👑', 55.4, st.mpR),
    ];

Decision? _decOf(AppState st, String name, AllResult? r) {
  if (name == 'AAB') return st.forecast?.decision;
  return r?.decision;
}

/// بطاقة «أقوى إشارة الآن»: أول مؤشر (من الأقوى) عنده صفقة مفتوحة أو إشارة تنتظر التأكيد.
class _BestNow extends StatelessWidget {
  final AppState st;
  const _BestNow({required this.st});
  @override
  Widget build(BuildContext context) {
    final sym = st.symbol;
    (String, String, double, Decision)? best;
    for (final (n, e, acc, r) in _ranked(st)) {
      final d = _decOf(st, n, r);
      if (d != null && (d.state == 1 || d.state == 2)) {
        best = (n, e, acc, d);
        break;
      }
    }
    final px = st.candles.isEmpty ? double.nan : st.candles.last.close;
    Widget shell(List<Widget> kids, {Color edge = AppColors.accent}) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(1.2),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [edge, edge.withOpacity(0.35)], begin: Alignment.topRight, end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: edge.withOpacity(0.22), blurRadius: 22)],
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: const LinearGradient(colors: [Color(0xFF1C1912), AppColors.card], begin: Alignment.topRight, end: Alignment.bottomLeft),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
          ),
        );
    final title = Row(children: [
      const Icon(Icons.bolt_rounded, color: AppColors.gold, size: 20),
      const SizedBox(width: 6),
      const Expanded(
          child: Text('أقوى إشارة الآن', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 14))),
      Text('${sym.code} • ${st.tf.toUpperCase()}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
    ]);
    if (best == null) {
      return shell([
        title,
        const SizedBox(height: 14),
        const Text('لا توجد إشارة الآن', style: TextStyle(color: AppColors.text, fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('لا يوجد عند AK ولا King ولا AAB ولا SM ولا النجوم صفقة مفتوحة أو إشارة تنتظر التأكيد على هذا السوق والفريم.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 12),
        _openChart(context),
      ], edge: AppColors.border);
    }
    final (name, emoji, acc, d) = best;
    final col = d.dir > 0 ? AppColors.up : AppColors.down;
    final open = d.state == 1;
    final risk = (d.entry - d.sl).abs();
    final liveR = open && risk > 0 && !px.isNaN ? (px - d.entry) * d.dir / risk : double.nan;
    Widget lv(String k, double v, Color c) => Expanded(
          child: Column(children: [
            Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
            const SizedBox(height: 3),
            Text(v.isNaN ? '—' : sym.fmt(v), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        );
    // موقع السعر بين الوقف والهدف الثاني
    double? prog;
    if (!px.isNaN && !d.sl.isNaN && !d.tp2.isNaN && d.tp2 != d.sl) {
      prog = ((px - d.sl) / (d.tp2 - d.sl)).clamp(0.0, 1.0).toDouble();
    }
    return shell([
      title,
      const SizedBox(height: 12),
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(gradient: AppColors.goldGrad, borderRadius: BorderRadius.circular(20)),
          child: Text('$emoji $name', style: const TextStyle(color: AppColors.onAccent, fontWeight: FontWeight.w900, fontSize: 12.5)),
        ),
        const SizedBox(width: 8),
        Text('دقة ${acc.toStringAsFixed(acc == acc.roundToDouble() ? 0 : 1)}%',
            style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (!liveR.isNaN)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
                color: (liveR >= 0 ? AppColors.up : AppColors.down).withOpacity(0.16), borderRadius: BorderRadius.circular(8)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('الآن ${liveR >= 0 ? '+' : ''}${liveR.toStringAsFixed(2)}R',
                  style: TextStyle(color: liveR >= 0 ? AppColors.up : AppColors.down, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(d.dir > 0 ? 'شراء' : 'بيع', style: TextStyle(color: col, fontSize: 30, fontWeight: FontWeight.w900, height: 1.1)),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(open ? 'صفقة مفتوحة' : 'تنتظر التأكيد', style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ]),
      if (!open)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('ادخل عند ${d.dir > 0 ? 'اختراق' : 'كسر'} ${sym.fmt(d.entry)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
      const SizedBox(height: 14),
      Row(children: [
        lv(open ? 'الدخول' : 'الدخول عند', d.entry, AppColors.text),
        lv('الوقف', d.sl, AppColors.down),
        lv('الهدف 1', d.tp1, AppColors.up),
        lv('الهدف 2', d.tp2, AppColors.up),
      ]),
      if (prog != null) ...[
        const SizedBox(height: 14),
        Directionality(
          textDirection: d.dir > 0 ? TextDirection.ltr : TextDirection.rtl,
          child: LayoutBuilder(builder: (_, cs) {
            final w = cs.maxWidth;
            final ent = ((d.entry - d.sl) / (d.tp2 - d.sl)).clamp(0.0, 1.0).toDouble();
            return SizedBox(
              height: 18,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  top: 7,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(colors: [AppColors.down, Color(0xFF3A3A44), AppColors.up]),
                    ),
                  ),
                ),
                Positioned(left: w * ent - 1, top: 3, child: Container(width: 2, height: 13, color: AppColors.text)),
                Positioned(
                  left: (w * prog! - 7).clamp(0.0, w - 14).toDouble(),
                  top: 2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.6), blurRadius: 8)],
                    ),
                  ),
                ),
              ]),
            );
          }),
        ),
        const SizedBox(height: 4),
        const Row(children: [
          Text('الوقف', style: TextStyle(color: AppColors.down, fontSize: 10)),
          Spacer(),
          Text('السعر الآن ●', style: TextStyle(color: AppColors.gold, fontSize: 10)),
          Spacer(),
          Text('الهدف 2', style: TextStyle(color: AppColors.up, fontSize: 10)),
        ]),
      ],
      const SizedBox(height: 14),
      _openChart(context),
    ], edge: col);
  }

  Widget _openChart(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.read<AppState>().setTab(1),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 11),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.candlestick_chart_rounded, color: AppColors.gold, size: 18),
                SizedBox(width: 6),
                Text('افتح الشارت', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
            ),
          ),
        ),
      );
}

/// «المؤشرات الآن»: حالة كل مؤشر قوي في بطاقة صغيرة.
class _IndicatorsNow extends StatelessWidget {
  final AppState st;
  const _IndicatorsNow({required this.st});
  @override
  Widget build(BuildContext context) {
    final items = _ranked(st);
    Widget tile((String, String, double, AllResult?) x) {
      final (n, e, acc, r) = x;
      final d = _decOf(st, n, r);
      final state = d?.state ?? 0;
      final col = state == 0 ? AppColors.muted : (d!.dir > 0 ? AppColors.up : AppColors.down);
      final txt = state == 0
          ? 'لا شيء'
          : '${d!.dir > 0 ? 'شراء' : 'بيع'} ${state == 1 ? 'مفتوحة' : state == 2 ? 'ينتظر' : 'يتكوّن'}';
      return Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        decoration: BoxDecoration(
          color: state == 0 ? AppColors.card : col.withOpacity(0.10),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: state == 0 ? AppColors.border : col.withOpacity(0.6), width: 0.9),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Text('$e $n', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13)),
            const Spacer(),
            Text('${acc.toStringAsFixed(acc == acc.roundToDouble() ? 0 : 1)}%',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(txt, style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, right: 2),
          child: Row(children: [
            Icon(Icons.dashboard_customize_outlined, color: AppColors.gold, size: 18),
            SizedBox(width: 6),
            Text('المؤشرات الآن', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
            SizedBox(width: 6),
            Text('(مرتبة من الأدق)', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.55,
          children: [for (final x in items) tile(x)],
        ),
      ]),
    );
  }
}

/// «آخر الصفقات»: نتائج آخر الصفقات المغلقة لـ AK و King على هذا الشارت.
class _RecentTrades extends StatelessWidget {
  final AppState st;
  const _RecentTrades({required this.st});
  @override
  Widget build(BuildContext context) {
    final c = st.candles;
    final l = <(String, PastSignal)>[
      for (final s in st.akR?.signals ?? const <PastSignal>[]) if (s.result != 0) ('AK', s),
      for (final s in st.kingR?.res.signals ?? const <PastSignal>[]) if (s.result != 0) ('King', s),
    ]..sort((a, b) => b.$2.i.compareTo(a.$2.i));
    final seen = <String>{};
    final rows = [for (final x in l) if (seen.add('${x.$2.i}|${x.$2.dir}')) x].take(6).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final w = rows.where((x) => x.$2.result > 0).length;
    String ago(int i) {
      if (i < 0 || i >= c.length) return '';
      final m = DateTime.now().toUtc().difference(c[i].time.toUtc()).inMinutes;
      if (m < 60) return 'قبل $m د';
      if (m < 1440) return 'قبل ${m ~/ 60} س';
      return 'قبل ${m ~/ 1440} يوم';
    }

    return Panel(
      title: 'آخر الصفقات (AK و King)',
      icon: Icons.history_rounded,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            for (final x in rows.reversed)
              Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                      color: x.$2.result > 0 ? AppColors.up : AppColors.down, borderRadius: BorderRadius.circular(3)),
                ),
              ),
          ]),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('$w رابحة من ${rows.length}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ),
        for (final (n, s) in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.5), width: 0.6))),
            child: Row(children: [
              Icon(s.dir > 0 ? Icons.north_east_rounded : Icons.south_east_rounded,
                  size: 16, color: s.dir > 0 ? AppColors.up : AppColors.down),
              const SizedBox(width: 6),
              Text('${s.dir > 0 ? 'شراء' : 'بيع'} $n', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
              const SizedBox(width: 6),
              Text(ago(s.i), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              const Spacer(),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                    s.result > 0 ? '${s.rMultiple >= 0 ? '+' : ''}${s.rMultiple.toStringAsFixed(2)}R' : '-1R',
                    style: TextStyle(
                        color: s.result > 0 ? AppColors.up : AppColors.down, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            ]),
          ),
      ]),
    );
  }
}
