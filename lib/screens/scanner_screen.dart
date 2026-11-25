import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../analysis/scan.dart';
import '../data/symbols.dart';
import '../models.dart';
import '../services/market_data_service.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// ماسح الأسواق: يفحص الأسواق والفريمات ويعرض أين توجد إشارة قوية الآن (AK، King، النجوم).
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _Row {
  final MarketSymbol sym;
  final String tf;
  final ScanHit hit;
  _Row(this.sym, this.tf, this.hit);
}

class _ScannerScreenState extends State<ScannerScreen> {
  String scope = 'fav';
  final tfs = <String>{'15m', '1h'};
  bool running = false, stop = false;
  int done = 0, total = 0;
  String now = '';
  final rows = <_Row>[];
  final errors = <String>[];
  final _md = MarketDataService();

  List<MarketSymbol> _symbols(AppState st) {
    switch (scope) {
      case 'fav':
        final f = [for (final s in allSymbols) if (st.favorites.contains(s.code)) s];
        return f.isEmpty ? [st.symbol] : f;
      case 'gold':
        return [for (final s in allSymbols) if (s.category == 'metal' || s.isCrypto) s];
      default:
        return allSymbols;
    }
  }

  Future<void> _run(AppState st) async {
    final syms = _symbols(st);
    final tfl = [for (final t in const ['5m', '15m', '1h', '4h']) if (tfs.contains(t)) t];
    setState(() {
      running = true;
      stop = false;
      rows.clear();
      errors.clear();
      done = 0;
      total = syms.length * tfl.length;
    });
    final s = st.settings;
    var lastApi = DateTime.fromMillisecondsSinceEpoch(0);
    for (final sym in syms) {
      for (final tf in tfl) {
        if (stop || !mounted) break;
        setState(() => now = '${sym.code} • ${tf.toUpperCase()}');
        try {
          // مفاتيح البيانات المجانية محدودة (حوالي 8 طلبات في الدقيقة): ننتظر بين الطلبات لغير العملات الرقمية
          if (!sym.isCrypto) {
            final wait = const Duration(seconds: 8) - DateTime.now().difference(lastApi);
            if (wait > Duration.zero) await Future.delayed(wait);
            lastApi = DateTime.now();
          }
          final c = await _md.fetch(sym, tf, s, count: AppState.candleCount(tf));
          final rr1 = s.rr1For(sym.category), rr2 = s.rr2, a1 = s.alkaTp1;
          final hits = await Isolate.run(() => scanCandles(c, sym, rr1: rr1, rr2: rr2, alkaTp1: a1));
          if (!mounted) return;
          setState(() {
            for (final h in hits) {
              rows.add(_Row(sym, tf, h));
            }
          });
        } catch (e) {
          errors.add('${sym.code} ${tf.toUpperCase()}: ${e.toString().replaceFirst('Exception: ', '')}');
        }
        if (mounted) setState(() => done++);
      }
    }
    if (!mounted) return;
    if (rows.isNotEmpty) HapticFeedback.mediumImpact();
    setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final syms = _symbols(st);
    rows.sort((a, b) {
      final x = (scanAcc[b.hit.ind] ?? 0).compareTo(scanAcc[a.hit.ind] ?? 0);
      return x != 0 ? x : a.hit.barsAgo.compareTo(b.hit.barsAgo);
    });
    Widget chip(String label, bool on, VoidCallback tap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: ChoiceChip(
            label: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? AppColors.onAccent : AppColors.text)),
            selected: on,
            onSelected: running ? null : (_) => setState(tap),
            selectedColor: AppColors.gold,
            backgroundColor: AppColors.card,
            side: BorderSide(color: on ? AppColors.gold : AppColors.border),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('ماسح الأسواق', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          const Text('يفحص الأسواق ويعرض أين توجد إشارة قوية الآن (ظهرت خلال آخر 6 شموع وما زالت مفتوحة).',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 12),
          const Text('الأسواق', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(children: [
            chip('المفضلة', scope == 'fav', () => scope = 'fav'),
            chip('الذهب والكريبتو', scope == 'gold', () => scope = 'gold'),
            chip('كل الأسواق', scope == 'all', () => scope = 'all'),
          ]),
          const SizedBox(height: 10),
          const Text('الفريمات', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(children: [
            for (final t in const ['5m', '15m', '1h', '4h'])
              chip(t.toUpperCase(), tfs.contains(t), () {
                if (tfs.contains(t)) {
                  if (tfs.length > 1) tfs.remove(t);
                } else {
                  tfs.add(t);
                }
              }),
          ]),
          const SizedBox(height: 6),
          Text('${syms.length} سوق × ${tfs.length} فريم = ${syms.length * tfs.length} فحص',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: running ? AppColors.card : AppColors.gold,
                foregroundColor: running ? AppColors.text : AppColors.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: running ? () => setState(() => stop = true) : () => _run(st),
              icon: Icon(running ? Icons.stop_rounded : Icons.radar_rounded),
              label: Text(running ? 'إيقاف' : 'ابدأ الفحص', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          if (running || total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? null : done / total,
                minHeight: 6,
                backgroundColor: AppColors.card,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 6),
            Text(running ? 'جاري فحص $now  ($done من $total)' : 'انتهى الفحص: $done من $total',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          if (!running && total > 0 && rows.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: const Text('لا توجد إشارة قوية الآن في هذه الأسواق. الصبر جزء من الربح — جرّب لاحقاً.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
            ),
          for (final r in rows) _HitCard(r: r, onTap: () async {
            await st.setSymbol(r.sym);
            await st.setTf(r.tf);
            st.setTab(1);
            if (context.mounted) Navigator.of(context).pop();
          }),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('تعذّر فحص ${errors.length}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              children: [for (final e in errors) Text(e, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))],
            ),
          ],
        ],
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  final _Row r;
  final VoidCallback onTap;
  const _HitCard({required this.r, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = r.hit;
    final up = h.dir > 0;
    final col = up ? AppColors.up : AppColors.down;
    String f(double v) => r.sym.fmt(v);
    final age = h.barsAgo == 0 ? 'الآن' : 'قبل ${h.barsAgo} شمعة';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.withOpacity(0.55)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(8)),
                child: Text(up ? 'شراء' : 'بيع', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text(r.sym.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(width: 6),
              Text(r.tf.toUpperCase(), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${h.ind} • ~${(scanAcc[h.ind] ?? 0).toStringAsFixed(0)}%',
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ]),
            const SizedBox(height: 8),
            Text('دخول \u2066${f(h.entry)}\u2069 — وقف \u2066${f(h.sl)}\u2069 — هدف \u2066${f(h.tp1)}\u2069',
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 2),
            Text('$age • اضغط لفتح الشارت', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}
