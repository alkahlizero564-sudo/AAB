import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    Color c;
    String t;
    switch (st.liveStatus) {
      case 'live':
        c = AppColors.up;
        t = 'LIVE • ${st.liveSource}';
        break;
      case 'poll':
        c = AppColors.gold;
        t = 'تحديث دوري • ${st.liveSource}';
        break;
      case 'connecting':
        c = AppColors.accent;
        t = 'جاري الاتصال…';
        break;
      case 'error':
        c = AppColors.down;
        t = st.liveSource.isEmpty ? 'خطأ في البث' : st.liveSource;
        break;
      default:
        c = AppColors.muted;
        t = 'REST فقط';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 8, color: c),
        const SizedBox(width: 5),
        Flexible(
          child: Text(t,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class SignalCard extends StatelessWidget {
  final TradeSignal sig;
  final MarketSymbol sym;
  const SignalCard({super.key, required this.sig, required this.sym});

  @override
  Widget build(BuildContext context) {
    final col = dirColor(sig.direction);
    final active = sig.direction != Direction.neutral;
    final word = sig.direction == Direction.buy
        ? 'شراء'
        : sig.direction == Direction.sell
            ? 'بيع'
            : 'انتظار';
    return Panel(
      title: 'توصية المحرك',
      icon: Icons.bolt_rounded,
      trailing: const LiveBadge(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          GaugeRing(
            value: sig.strength / 100,
            color: active ? col : AppColors.accent,
            size: 118,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  sig.direction == Direction.buy
                      ? Icons.trending_up_rounded
                      : sig.direction == Direction.sell
                          ? Icons.trending_down_rounded
                          : Icons.pause_circle_outline_rounded,
                  size: 20,
                  color: active ? col : AppColors.gold),
              Text(word,
                  style: TextStyle(
                      color: active ? col : AppColors.gold,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.15)),
              Text('${sig.strength.toStringAsFixed(0)}%',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dirOutlook(sig.direction),
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              const Text('قوة الإشارة وتوافق المؤشرات',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (active) Tag('درجة ${sig.grade}', color: col),
                Tag('توافق ${sig.agree}/${sig.total}'),
                if (sig.killzone.isNotEmpty) Tag(sig.killzone),
              ]),
            ]),
          ),
        ]),
        if (active) ...[
          const SizedBox(height: 14),
          _row('الدخول', sig.entry, AppColors.text, first: true),
          _row('وقف الخسارة', sig.stopLoss, AppColors.down),
          _row('الهدف 1', sig.tp1, AppColors.up),
          _row('الهدف 2', sig.tp2, AppColors.up),
          _row('الهدف 3', sig.tp3, AppColors.up),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Tag('ATR ${sym.fmt(sig.atr)}'),
            Tag(sig.htfTrend == 0
                ? 'الإطار الأعلى: محايد'
                : sig.htfTrend == 1
                    ? 'الإطار الأعلى: صاعد'
                    : 'الإطار الأعلى: هابط'),
          ]),
        ] else ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final r in sig.reasons.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(r,
                      style: TextStyle(
                          color: r == sig.reasons.first ? AppColors.text : AppColors.muted,
                          fontWeight: r == sig.reasons.first ? FontWeight.w700 : FontWeight.w400,
                          fontSize: 12,
                          height: 1.45)),
                ),
              if (sig.reasons.isEmpty)
                const Text('لا توجد صفقة الآن — انتظر وضوح الاتجاه.',
                    style: TextStyle(color: AppColors.muted)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _row(String t, double v, Color c, {bool first = false}) {
    final pct = sig.price > 0 ? (v - sig.price) / sig.price * 100 : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border.withOpacity(first ? 0.8 : 0.45), width: 0.6)),
      ),
      child: Row(children: [
        Container(width: 3, height: 16, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const Spacer(),
        Text('${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(sym.fmt(v),
              textAlign: TextAlign.end,
              style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}
