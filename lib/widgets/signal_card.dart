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
          Container(
            width: 86,
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? col : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: active ? null : Border.all(color: AppColors.accent.withOpacity(0.6)),
            ),
            child: Column(children: [
              Icon(
                  sig.direction == Direction.buy
                      ? Icons.north_east_rounded
                      : sig.direction == Direction.sell
                          ? Icons.south_east_rounded
                          : Icons.pause_rounded,
                  size: 18,
                  color: active ? Colors.white : AppColors.gold),
              Text(word,
                  style: TextStyle(
                      color: active ? Colors.white : AppColors.gold,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dirOutlook(sig.direction),
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              Row(children: [
                const Text('قوة الإشارة',
                    style: TextStyle(color: AppColors.muted, fontSize: 11)),
                const Spacer(),
                Text('${sig.strength.toStringAsFixed(0)}%',
                    style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
              const SizedBox(height: 5),
              _meter(sig.strength / 100, col),
              if (sig.killzone.isNotEmpty || active) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (active) Tag('درجة ${sig.grade}', color: col),
                  if (sig.killzone.isNotEmpty) Tag(sig.killzone),
                ]),
              ],
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
            Tag('توافق ${sig.agree}/${sig.total}'),
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

  /// مقياس مقسّم (20 خانة) بأسلوب المنصات.
  Widget _meter(double v, Color c) => Row(children: [
        for (var i = 0; i < 20; i++)
          Expanded(
            child: Container(
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: i < (v * 20).round() ? c : AppColors.border.withOpacity(0.6),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
      ]);

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
