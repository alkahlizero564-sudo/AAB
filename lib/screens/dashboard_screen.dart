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
          Row(children: [
            const SymbolButton(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(st.symbol.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
            if (st.lastUpdate != null) ...[
              const Icon(Icons.circle, size: 9, color: AppColors.up),
              const SizedBox(width: 5),
              Text(_hhmmss(st.lastUpdate!),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ]),
          const SizedBox(height: 12),
          const TfChips(),
          const SizedBox(height: 14),
          if (st.error != null) ErrorBanner(st.error!),
          if (st.loading && sig == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('أسباب الإشارة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        for (final r in sig.reasons.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(Icons.circle, size: 6, color: AppColors.accent),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('المؤشرات الفنية',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        for (final v in sig.votes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Icon(
                v.vote > 0
                    ? Icons.arrow_circle_up
                    : v.vote < 0
                        ? Icons.arrow_circle_down
                        : Icons.remove_circle_outline,
                size: 20,
                color: v.vote > 0
                    ? AppColors.up
                    : v.vote < 0
                        ? AppColors.down
                        : AppColors.muted,
              ),
              const SizedBox(width: 10),
              SizedBox(
                  width: 96,
                  child: Text(v.name,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(
                  child: Text(v.value,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12))),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('نماذج الشموع اليابانية',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (sig.patterns.isEmpty)
          const Text('لا يوجد نموذج شموع واضح على آخر الشموع.',
              style: TextStyle(color: AppColors.muted, fontSize: 13))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in sig.patterns)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: (p.bias > 0
                          ? AppColors.up
                          : p.bias < 0
                              ? AppColors.down
                              : AppColors.gold)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(p.ar,
                    style: TextStyle(
                        fontSize: 12,
                        color: p.bias > 0
                            ? AppColors.up
                            : p.bias < 0
                                ? AppColors.down
                                : AppColors.gold)),
              ),
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
