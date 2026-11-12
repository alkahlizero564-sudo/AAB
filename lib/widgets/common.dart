import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/symbols.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderColor,
    this.title,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? AppColors.border.withOpacity(0.55), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.6), width: 0.7)),
            ),
            child: Row(children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(
                  gradient: AppColors.goldGrad, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(title!,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// زر بأسلوب منصات التداول: أيقونة + نص، بدون إطارات ثقيلة.
class ProButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const ProButton(this.icon, this.label, this.onTap, {super.key, this.primary = false});
  @override
  Widget build(BuildContext context) => Material(
        color: primary ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: primary
              ? BoxDecoration(gradient: AppColors.goldGrad, borderRadius: BorderRadius.circular(10))
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 17, color: primary ? AppColors.onAccent : AppColors.accent),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: primary ? AppColors.onAccent : AppColors.text)),
              ]),
            ),
          ),
        ),
      );
}

/// شارة صغيرة (بيانات مختصرة).
class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  const Tag(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (color ?? AppColors.muted).withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: (color ?? AppColors.muted).withOpacity(0.25), width: 0.7),
        ),
        child: Text(text,
            style: TextStyle(color: color ?? AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
      );
}

Color dirColor(Direction d) => d == Direction.buy
    ? AppColors.up
    : d == Direction.sell
        ? AppColors.down
        : AppColors.gold;

String dirLabel(Direction d) => d == Direction.buy
    ? 'شراء BUY'
    : d == Direction.sell
        ? 'بيع SELL'
        : 'انتظار';

String dirOutlook(Direction d) => d == Direction.buy
    ? 'متوقع: صعود ▲'
    : d == Direction.sell
        ? 'متوقع: هبوط ▼'
        : 'متوقع: عرضي ↔';

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Panel(
        color: AppColors.down.withOpacity(0.12),
        borderColor: AppColors.down.withOpacity(0.5),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AppColors.down),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppColors.text, fontSize: 13))),
        ]),
      );
}

/// الأُطر الزمنية بأسلوب المنصات الاحترافية: نص بسيط وخط ذهبي تحت المختار.
class TfChips extends StatelessWidget {
  const TfChips({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return TfTabs(current: st.tf, onPick: st.setTf);
  }
}

class TfTabs extends StatelessWidget {
  final String current;
  final ValueChanged<String> onPick;
  final double height;
  const TfTabs({super.key, required this.current, required this.onPick, this.height = 36});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.7)),
      ),
      child: Row(children: [
        for (final t in AppState.timeframes)
          Expanded(
            child: InkWell(
              onTap: () => onPick(t),
              child: Stack(alignment: Alignment.center, children: [
                Text(t.toUpperCase(),
                    style: TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 0.3,
                        fontWeight: current == t ? FontWeight.w800 : FontWeight.w500,
                        color: current == t ? AppColors.gold : AppColors.muted)),
                if (current == t)
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 22,
                      height: 2.5,
                      decoration: BoxDecoration(
                          gradient: AppColors.goldGrad, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// شارة الرمز (مربع ذهبي بالحرفين الأولين).
class SymbolBadge extends StatelessWidget {
  final String code;
  final double size;
  const SymbolBadge(this.code, {super.key, this.size = 36});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: AppColors.accent.withOpacity(0.45), width: 0.8),
        ),
        child: Text(code.replaceAll('/', '').substring(0, code.length >= 2 ? 2 : 1),
            style: TextStyle(
                fontSize: size * 0.34, fontWeight: FontWeight.w800, color: AppColors.gold)),
      );
}

class SymbolButton extends StatelessWidget {
  const SymbolButton({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showSymbolSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SymbolBadge(st.symbol.code),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(st.symbol.code,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.2)),
              const Icon(Icons.expand_more, size: 20, color: AppColors.muted),
            ]),
            Text(st.symbol.name,
                style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.2)),
          ]),
        ]),
      ),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          width: 38,
          height: 4,
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
        ),
      );
}

void showSymbolSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.85,
      child: Column(children: [
        const SheetHandle(),
        Expanded(child: MarketsList(onPicked: () => Navigator.of(ctx).pop())),
      ]),
    ),
  );
}

/// Searchable list of every pair / metal / crypto / stock.
class MarketsList extends StatefulWidget {
  final VoidCallback? onPicked;
  const MarketsList({super.key, this.onPicked});
  @override
  State<MarketsList> createState() => _MarketsListState();
}

class _MarketsListState extends State<MarketsList> {
  String q = '';
  String cat = 'all';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cats = <String, String>{
      'all': 'الكل',
      'fav': '⭐ المفضلة',
      ...categoryAr,
    };
    final list = allSymbols.where((s) {
      if (cat == 'fav' && !st.favorites.contains(s.code)) return false;
      if (cat != 'all' && cat != 'fav' && s.category != cat) return false;
      if (q.isEmpty) return true;
      final t = q.toLowerCase();
      return s.code.toLowerCase().contains(t) || s.name.contains(q);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: TextField(
          onChanged: (v) => setState(() => q = v.trim()),
          decoration: const InputDecoration(
            hintText: 'ابحث: EUR/USD أو ذهب أو AAPL',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final e in cats.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => cat = e.key),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: cat == e.key ? AppColors.accent.withOpacity(0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: cat == e.key ? AppColors.accent.withOpacity(0.6) : AppColors.border,
                          width: 0.8),
                    ),
                    child: Text(e.value,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: cat == e.key ? FontWeight.w700 : FontWeight.w500,
                            color: cat == e.key ? AppColors.gold : AppColors.muted)),
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? const Center(
                child: Text('لا نتائج', style: TextStyle(color: AppColors.muted)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final sel = s.code == st.symbol.code;
                  final fav = st.favorites.contains(s.code);
                  return InkWell(
                    onTap: () {
                      st.setSymbol(s);
                      st.setTab(0);
                      widget.onPicked?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.accent.withOpacity(0.07) : null,
                        border: Border(
                            bottom: BorderSide(color: AppColors.border.withOpacity(0.5), width: 0.6)),
                      ),
                      child: Row(children: [
                        SymbolBadge(s.code, size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.code,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: sel ? AppColors.gold : AppColors.text)),
                            Text(s.name,
                                style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          ]),
                        ),
                        Tag(categoryAr[s.category] ?? ''),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: fav ? AppColors.gold : AppColors.muted),
                          onPressed: () => st.toggleFavorite(s.code),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}


/// خط سعر مصغّر بتعبئة متدرجة (Sparkline).
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  const Sparkline(this.values, {super.key, required this.color, this.height = 70});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, color)));
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final Color c;
  _SparkPainter(this.v, this.c);
  @override
  void paint(Canvas cv, Size sz) {
    if (v.length < 2) return;
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final rng = hi - lo == 0 ? 1.0 : hi - lo;
    Offset pt(int i) => Offset(i / (v.length - 1) * sz.width, sz.height - 4 - (v[i] - lo) / rng * (sz.height - 8));
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(sz.width, sz.height)
      ..lineTo(0, sz.height)
      ..close();
    cv.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.withOpacity(0.35), c.withOpacity(0.0)],
          ).createShader(Offset.zero & sz));
    cv.drawPath(
        line,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    final last = pt(v.length - 1);
    cv.drawCircle(last, 6, Paint()..color = c.withOpacity(0.25));
    cv.drawCircle(last, 3, Paint()..color = c);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.v != v || o.c != c;
}

/// حلقة قياس دائرية (قوة الإشارة).
class GaugeRing extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final Widget child;
  final double size;
  const GaugeRing({super.key, required this.value, required this.color, required this.child, this.size = 120});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0, 1).toDouble(), color),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color c;
  _RingPainter(this.v, this.c);
  @override
  void paint(Canvas cv, Size sz) {
    final r = Rect.fromLTWH(7, 7, sz.width - 14, sz.height - 14);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    cv.drawArc(r, start, sweep, false,
        Paint()
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round);
    if (v > 0) {
      cv.drawArc(r, start, sweep * v, false,
          Paint()
            ..shader = SweepGradient(
              startAngle: start,
              endAngle: start + sweep,
              colors: [c.withOpacity(0.5), c],
              transform: const GradientRotation(0),
            ).createShader(r)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.c != c;
}

/// شريط الأسواق السريع (المفضلة أو أشهر الرموز).
class WatchStrip extends StatelessWidget {
  const WatchStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final codes = <String>{
      st.symbol.code,
      ...st.favorites,
      'XAU/USD', 'BTC/USD', 'EUR/USD', 'GBP/USD', 'XAG/USD', 'USD/JPY', 'ETH/USD',
    }.where((c) => allSymbols.any((s) => s.code == c)).toList();
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in codes)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => st.setSymbol(symbolByCode(c)),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                  decoration: BoxDecoration(
                    gradient: c == st.symbol.code ? AppColors.goldGrad : null,
                    color: c == st.symbol.code ? null : AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: c == st.symbol.code
                        ? null
                        : Border.all(color: AppColors.border.withOpacity(0.7), width: 0.8),
                  ),
                  child: Row(children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c == st.symbol.code
                            ? AppColors.onAccent.withOpacity(0.15)
                            : AppColors.accent.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(c.replaceAll('/', '').substring(0, 2),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: c == st.symbol.code ? AppColors.onAccent : AppColors.gold)),
                    ),
                    const SizedBox(width: 8),
                    Text(c,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c == st.symbol.code ? AppColors.onAccent : AppColors.text)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
