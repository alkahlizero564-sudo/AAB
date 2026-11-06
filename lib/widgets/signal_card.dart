import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

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
          const Text('قوة الإشارة',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _tag('اتفاق ${sig.agree}/${sig.total} مؤشر'),
            _tag('ATR ${sym.fmt(sig.atr)}'),
            _tag(sig.htfTrend == 0
                ? 'الإطار الأعلى: محايد'
                : sig.htfTrend == 1
                    ? 'الإطار الأعلى: صاعد'
                    : 'الإطار الأعلى: هابط'),
          ]),
        ] else ...[
          const SizedBox(height: 12),
          const Text('لا توجد صفقة الآن — انتظر وضوح الاتجاه.',
              style: TextStyle(color: AppColors.muted)),
        ],
      ]),
    );
  }

  Widget _lv(String t, String v, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(v,
                style: TextStyle(
                    color: c, fontSize: 16, fontWeight: FontWeight.bold)),
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
