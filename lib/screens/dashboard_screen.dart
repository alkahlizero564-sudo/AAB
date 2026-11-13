import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
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
          if (st.mpR != null) _AllHero(st: st),
          if (sig != null) ...[
            SignalCard(sig: sig, sym: st.symbol),
            _AiPanel(st: st, sig: sig),
            _ReasonsPanel(sig: sig),
            _IndicatorsPanel(sig: sig),
            _PatternsPanel(sig: sig),
          ],
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
