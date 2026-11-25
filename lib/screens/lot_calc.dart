import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/forecast.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// حاسبة اللوت: حجم الصفقة حسب رأس المال ونسبة المخاطرة ومسافة الوقف.
Future<void> showLotCalc(BuildContext context, AppState st) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _LotCalc(st: st),
  );
}

/// آخر إشارة مفتوحة من الأقوى: AK ثم King ثم توصية الشاشة.
(String, int, double, double, double, double)? lotSignal(AppState st) {
  PastSignal? open(List<PastSignal>? l) {
    if (l == null) return null;
    for (final s in l.reversed) {
      if (s.exitI < 0) return s;
    }
    return null;
  }

  final ak = open(st.akR?.signals);
  if (ak != null) return ('AK', ak.dir, ak.entry, ak.sl, ak.tp1, ak.tp2);
  final k = open(st.kingR?.res.signals);
  if (k != null) {
    final n = st.kingR!.stars(k.i, k.dir);
    return ('King ${'⭐' * math.max(1, n)}', k.dir, k.entry, k.sl, k.tp1, k.tp2);
  }
  final s = st.signal;
  if (s != null && s.direction != Direction.neutral) {
    return ('التوصية', s.direction == Direction.buy ? 1 : -1, s.entry, s.stopLoss, s.tp1, s.tp2);
  }
  return null;
}

/// قيمة حركة 1.0 في السعر لعقد/لوت واحد بالدولار، ووحدة الحجم.
/// (null = يحتاج سعر تحويل عملة التسعير للدولار)
(double?, String, bool) _spec(MarketSymbol s, double price) {
  final c = s.code;
  if (c == 'XAU/USD') return (100, 'لوت (100 أونصة)', true);
  if (c == 'XAG/USD') return (5000, 'لوت (5000 أونصة)', true);
  if (c == 'XPT/USD' || c == 'XPD/USD') return (100, 'لوت (100 أونصة)', true);
  if (s.category == 'crypto') return (1, 'وحدة (${c.split('/').first})', false);
  if (s.category == 'stock') return (1, 'سهم', false);
  if (s.category == 'index') return (1, 'عقد (1\$ للنقطة)', false);
  final p = c.split('/');
  if (p.length == 2) {
    if (p[1] == 'USD') return (100000, 'لوت (100,000)', true);
    if (p[0] == 'USD') return (100000 / price, 'لوت (100,000)', true);
    return (null, 'لوت (100,000)', true); // تقاطع: نحتاج سعر عملة التسعير مقابل الدولار
  }
  return (1, 'وحدة', false);
}

class _LotCalc extends StatefulWidget {
  final AppState st;
  const _LotCalc({required this.st});
  @override
  State<_LotCalc> createState() => _LotCalcState();
}

class _LotCalcState extends State<_LotCalc> {
  final bal = TextEditingController(), risk = TextEditingController(), entry = TextEditingController(), stop = TextEditingController();
  final tp1 = TextEditingController(), tp2 = TextEditingController(), conv = TextEditingController(text: '1');
  String src = '';
  int dir = 0;

  @override
  void initState() {
    super.initState();
    final sym = widget.st.symbol;
    final sg = lotSignal(widget.st);
    if (sg != null) {
      final (n, d, e, sl, t1, t2) = sg;
      src = n;
      dir = d;
      entry.text = sym.fmt(e);
      stop.text = sym.fmt(sl);
      tp1.text = sym.fmt(t1);
      tp2.text = sym.fmt(t2);
    } else if (widget.st.candles.isNotEmpty) {
      entry.text = sym.fmt(widget.st.candles.last.close);
    }
    () async {
      try {
        final p = await SharedPreferences.getInstance();
        bal.text = (p.getDouble('lot_balance') ?? 1000).toStringAsFixed(0);
        risk.text = (p.getDouble('lot_risk') ?? 1).toString();
      } catch (_) {
        bal.text = '1000';
        risk.text = '1';
      }
      if (mounted) setState(() {});
    }();
  }

  double _n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? double.nan;

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final b = _n(bal), r = _n(risk);
      if (b > 0) await p.setDouble('lot_balance', b);
      if (r > 0) await p.setDouble('lot_risk', r);
    } catch (_) {}
  }

  Widget _field(String label, TextEditingController c, {String? suffix}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            textDirection: TextDirection.ltr,
            onChanged: (_) {
              setState(() {});
              _save();
            },
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              isDense: true,
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final sym = widget.st.symbol;
    final b = _n(bal), r = _n(risk), e = _n(entry), sl = _n(stop);
    final (per0, unit, isLot) = _spec(sym, e.isNaN ? 1 : e);
    final cross = per0 == null;
    final per = per0 ?? 100000 * (_n(conv).isNaN ? 1 : _n(conv));
    final riskUsd = b * r / 100;
    final dist = (e - sl).abs();
    final ok = riskUsd > 0 && dist > 0 && !dist.isNaN;
    final size = ok ? riskUsd / (dist * per) : double.nan;
    final shown = isLot ? (size * 100).floorToDouble() / 100 : size;
    final realRisk = ok ? shown * dist * per : double.nan;
    double profit(TextEditingController t) {
      final x = _n(t);
      return ok && !x.isNaN ? (x - e).abs() * shown * per : double.nan;
    }

    String money(double v) => v.isNaN ? '—' : '\$${v.toStringAsFixed(2)}';
    final bad = ok && isLot && shown < 0.01;
    final big = r > 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.calculate_rounded, color: AppColors.gold),
            const SizedBox(width: 8),
            const Text('حاسبة اللوت', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            Text(sym.code, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
          ]),
          if (src.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('من آخر إشارة مفتوحة: $src ${dir > 0 ? 'شراء' : 'بيع'}',
                  style: TextStyle(color: dir > 0 ? AppColors.up : AppColors.down, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 12),
          Row(children: [_field('رأس المال', bal, suffix: '\$'), _field('المخاطرة', risk, suffix: '%')]),
          const SizedBox(height: 10),
          Row(children: [_field('الدخول', entry), _field('الوقف', stop)]),
          const SizedBox(height: 10),
          Row(children: [_field('الهدف 1', tp1), _field('الهدف 2', tp2)]),
          if (cross) ...[
            const SizedBox(height: 10),
            Row(children: [_field('سعر ${sym.code.split('/').last} مقابل الدولار (مثلاً GBP = 1.27)', conv)]),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: ok ? AppColors.goldGrad : null,
              color: ok ? null : AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Text(ok ? (isLot ? shown.toStringAsFixed(2) : shown.toStringAsFixed(shown >= 10 ? 0 : 3)) : '—',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: ok ? AppColors.onAccent : AppColors.muted)),
              Text(unit, style: TextStyle(color: ok ? AppColors.onAccent : AppColors.muted, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 10),
          _row('مبلغ المخاطرة', money(realRisk.isNaN ? riskUsd : realRisk), AppColors.down),
          _row('مسافة الوقف', dist.isNaN || dist == 0 ? '—' : sym.fmt(dist), AppColors.text),
          _row('الربح عند الهدف 1', money(profit(tp1)), AppColors.up),
          _row('الربح عند الهدف 2', money(profit(tp2)), AppColors.up),
          if (bad)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('⚠️ الحجم أقل من 0.01 لوت (أصغر حجم عند أغلب الوسطاء) — المخاطرة الحقيقية ستكون أكبر من المطلوب، أو انتظر وقفاً أقرب.',
                  style: TextStyle(color: AppColors.down, fontSize: 12, height: 1.4)),
            ),
          if (big)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('⚠️ مخاطرة أكثر من 2% في الصفقة عالية — الأفضل 0.5% إلى 1%.',
                  style: TextStyle(color: AppColors.down, fontSize: 12, height: 1.4)),
            ),
          const SizedBox(height: 8),
          Text(
              sym.category == 'index'
                  ? 'قيمة النقطة تختلف بين الوسطاء (1\$ أو 10\$ أو غيرها) — راجع مواصفات العقد عند وسيطك.'
                  : 'الحساب تقريبي بمواصفات العقد الشائعة — راجع مواصفات العقد عند وسيطك. السبريد والعمولة غير محسوبين.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
        ]),
      ),
    );
  }

  Widget _row(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const Spacer(),
          Text(v, textDirection: TextDirection.ltr, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
      );
}
