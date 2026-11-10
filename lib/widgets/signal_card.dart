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
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
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
    return Panel(
      borderColor: col.withOpacity(0.6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Flexible(child: LiveBadge()),
          const Spacer(),
          if (sig.killzone.isNotEmpty)
            Text(sig.killzone,
                style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: col.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(dirLabel(sig.direction),
                style: TextStyle(
                    color: col, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(dirOutlook(sig.direction),
                  style: const TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w600))),
          Text(sym.fmt(sig.price),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          const Text('توافق المؤشرات',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          if (active) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: col.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('درجة ${sig.grade}',
                  style: TextStyle(
                      color: col, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
          const Spacer(),
          Text('${sig.strength.toStringAsFixed(0)}%',
              style: TextStyle(color: col, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: sig.strength / 100,
            minHeight: 8,
            color: col,
            backgroundColor: AppColors.surface,
          ),
        ),
        if (active) ...[
          const SizedBox(height: 14),
          Row(children: [
            _lv('الدخول', sym.fmt(sig.entry), AppColors.accent),
            const SizedBox(width: 8),
            _lv('وقف الخسارة', sym.fmt(sig.stopLoss), AppColors.down),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _lv('الهدف 1', sym.fmt(sig.tp1), AppColors.up),
            const SizedBox(width: 8),
            _lv('الهدف 2', sym.fmt(sig.tp2), AppColors.up),
            const SizedBox(width: 8),
            _lv('الهدف 3', sym.fmt(sig.tp3), AppColors.up),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _tag('توافق المؤشرات ${sig.agree}/${sig.total}'),
            _tag('ATR ${sym.fmt(sig.atr)}'),
            _tag(sig.htfTrend == 0
                ? 'الإطار الأعلى: محايد'
                : sig.htfTrend == 1
                    ? 'الإطار الأعلى: صاعد'
                    : 'الإطار الأعلى: هابط'),
          ]),
        ] else ...[
          const SizedBox(height: 12),
          for (final r in sig.reasons.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(r,
                  style: TextStyle(
                      color: r == sig.reasons.first ? AppColors.text : AppColors.muted,
                      fontWeight: r == sig.reasons.first ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 12)),
            ),
          if (sig.reasons.isEmpty)
            const Text('لا توجد صفقة الآن — انتظر وضوح الاتجاه.',
                style: TextStyle(color: AppColors.muted)),
        ],
      ]),
    );
  }

  Widget _lv(String t, String v, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(v,
                  style: TextStyle(
                      color: c, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      );

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t,
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      );
}
