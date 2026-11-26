import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/forecast.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// حاسبة اللوت: تكتب رأس المال فقط — الدخول والوقف والأهداف من الإشارة المفتوحة،
/// ونسبة المخاطرة حسب قوة الإشارة، ثم حجم الصفقة.
Future<void> showLotCalc(BuildContext context, AppState st) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _LotCalc(st: st),
  );
}

/// آخر إشارة مفتوحة من الأقوى: AK ثم King ثم توصية الشاشة — مع نسبة المخاطرة المناسبة لقوتها.
/// المخاطرة تلقائياً: AK و King ⭐⭐⭐ ← 1% • ⭐⭐ ← 0.75% • ⭐ والتوصية ← 0.5%.
(String, int, double, double, double, double, double)? lotSignal(AppState st) {
  PastSignal? open(List<PastSignal>? l) {
    if (l == null) return null;
    for (final s in l.reversed) {
      if (s.exitI < 0) return s;
    }
    return null;
  }

  final ak = open(st.akR?.signals);
  if (ak != null) return ('AK', ak.dir, ak.entry, ak.sl, ak.tp1, ak.tp2, 1.0);
  final k = open(st.kingR?.res.signals);
  if (k != null) {
    final n = math.max(1, st.kingR!.stars(k.i, k.dir));
    return ('King ${'⭐' * n}', k.dir, k.entry, k.sl, k.tp1, k.tp2, n >= 3 ? 1.0 : (n == 2 ? 0.75 : 0.5));
  }
  final s = st.signal;
  if (s != null && s.direction != Direction.neutral) {
    return ('التوصية', s.direction == Direction.buy ? 1 : -1, s.entry, s.stopLoss, s.tp1, s.tp2, 0.5);
  }
  return null;
}

/// قيمة حركة 1.0 في السعر لعقد/لوت واحد بالدولار، ووحدة الحجم، وهل الحجم بالـ «لوت».
/// (null = تقاطع عملات يحتاج سعر عملة التسعير مقابل الدولار)
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
    return (null, 'لوت (100,000)', true);
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
  final bal = TextEditingController(), conv = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final p = await SharedPreferences.getInstance();
        final v = p.getDouble('lot_balance');
        if (v != null) bal.text = v.toStringAsFixed(0);
      } catch (_) {}
      if (mounted) setState(() {});
    }();
  }

  double _n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? double.nan;

  Future<void> _save() async {
    try {
      final b = _n(bal);
      if (b > 0) await (await SharedPreferences.getInstance()).setDouble('lot_balance', b);
    } catch (_) {}
  }

  Widget _input(String label, TextEditingController c, String suffix, {bool big = false}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: big ? 24 : 15, fontWeight: FontWeight.w800),
        onChanged: (_) {
          setState(() {});
          _save();
        },
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.gold)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
        ),
      );

  Widget _row(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const Spacer(),
          Text(v, textDirection: TextDirection.ltr, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final sym = widget.st.symbol;
    final sg = lotSignal(widget.st);
    final b = _n(bal);
    final kids = <Widget>[
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 10),
      Row(children: [
        const Icon(Icons.calculate_rounded, color: AppColors.gold),
        const SizedBox(width: 8),
        const Text('حاسبة اللوت', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const Spacer(),
        Text(sym.code, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 12),
      _input('رأس المال', bal, '\$', big: true),
      const SizedBox(height: 4),
      const Text('اكتب رأس مالك فقط — الباقي يُحسب تلقائياً من الإشارة المفتوحة.', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
      const SizedBox(height: 12),
    ];
    if (sg == null) {
      kids.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
        child: const Text('لا توجد إشارة مفتوحة الآن على هذا الشارت — افتح الحاسبة عند ظهور إشارة.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
      ));
    } else {
      final (src, dir, e, sl, t1, t2, riskPct) = sg;
      final (per0, unit, isLot) = _spec(sym, e);
      final cross = per0 == null;
      final per = per0 ?? 100000 * (_n(conv).isNaN ? 1 : _n(conv));
      final dist = (e - sl).abs();
      final ok = b > 0 && dist > 0;
      final want = ok ? b * riskPct / 100 / (dist * per) : double.nan;
      final lot = !ok ? double.nan : (isLot ? math.max(0.01, (want * 100).floorToDouble() / 100) : want);
      final riskUsd = ok ? lot * dist * per : double.nan;
      final realPct = ok ? riskUsd / b * 100 : double.nan;
      final tooBig = ok && realPct > 2.0;
      String money(double v) => v.isNaN ? '—' : '\$${v.toStringAsFixed(2)}';
      final up = dir > 0;
      final good = ok && !tooBig;
      kids.addAll([
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: up ? AppColors.up : AppColors.down, borderRadius: BorderRadius.circular(8)),
            child: Text(up ? 'شراء' : 'بيع', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text(src, style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('المخاطرة ${riskPct == 1 ? '1' : riskPct.toStringAsFixed(riskPct == 0.5 ? 1 : 2)}%',
              style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
        const SizedBox(height: 4),
        Text(riskPct >= 1 ? 'إشارة قوية — مخاطرة 1%' : (riskPct >= 0.75 ? 'إشارة جيدة — مخاطرة 0.75%' : 'إشارة عادية — مخاطرة 0.5% فقط'),
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
        if (cross) ...[
          const SizedBox(height: 10),
          _input('سعر ${sym.code.split('/').last} مقابل الدولار (مثلاً GBP = 1.27)', conv, ''),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: good ? AppColors.goldGrad : null,
            color: good ? null : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: tooBig ? Border.all(color: AppColors.down) : null,
          ),
          child: Column(children: [
            Text(!ok ? '—' : (isLot ? lot.toStringAsFixed(2) : lot.toStringAsFixed(lot >= 10 ? 0 : 3)),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: good ? AppColors.onAccent : AppColors.text)),
            Text(ok ? unit : 'اكتب رأس المال', style: TextStyle(color: good ? AppColors.onAccent : AppColors.muted, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 10),
        _row('الدخول', sym.fmt(e), AppColors.text),
        _row('الوقف', sym.fmt(sl), AppColors.down),
        _row('الهدف 1', sym.fmt(t1), AppColors.up),
        _row('الهدف 2', sym.fmt(t2), AppColors.up),
        const Divider(color: AppColors.border, height: 18),
        _row('تخسر لو ضرب الوقف', '${money(riskUsd)} (${realPct.isNaN ? '—' : realPct.toStringAsFixed(1)}%)', AppColors.down),
        _row('تربح عند الهدف 1', money(ok ? (t1 - e).abs() * lot * per : double.nan), AppColors.up),
        _row('تربح عند الهدف 2', money(ok ? (t2 - e).abs() * lot * per : double.nan), AppColors.up),
        if (tooBig)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('⚠️ رأس المال صغير على هذه الصفقة: أصغر لوت (0.01) يخاطر بـ ${realPct.toStringAsFixed(1)}% — الأفضل تخطيها وانتظار إشارة بوقف أقرب.',
                style: const TextStyle(color: AppColors.down, fontSize: 12, height: 1.4)),
          ),
        const SizedBox(height: 8),
        Text(
            sym.category == 'index'
                ? 'قيمة النقطة تختلف بين الوسطاء (1\$ أو 10\$) — راجع مواصفات العقد عند وسيطك.'
                : 'تقريبي بمواصفات العقد الشائعة — السبريد والعمولة غير محسوبين.',
            style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
      ]);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: kids)),
    );
  }
}
