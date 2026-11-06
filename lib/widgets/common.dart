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
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: child,
    );
  }
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

class TfChips extends StatelessWidget {
  const TfChips({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in AppState.timeframes)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(t),
                selected: st.tf == t,
                onSelected: (_) => st.setTf(t),
                selectedColor: AppColors.accent,
                backgroundColor: AppColors.card,
                labelStyle: TextStyle(
                    color: st.tf == t ? Colors.white : AppColors.muted,
                    fontWeight: FontWeight.w600),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
        ],
      ),
    );
  }
}

class SymbolButton extends StatelessWidget {
  const SymbolButton({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showSymbolSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.currency_exchange, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(st.symbol.code,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down, color: AppColors.muted),
        ]),
      ),
    );
  }
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
      child: MarketsList(onPicked: () => Navigator.of(ctx).pop()),
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
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: cat == e.key,
                  onSelected: (_) => setState(() => cat = e.key),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppColors.card,
                  labelStyle: TextStyle(
                      color: cat == e.key ? Colors.white : AppColors.muted),
                  side: const BorderSide(color: AppColors.border),
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
                padding: const EdgeInsets.all(14),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final sel = s.code == st.symbol.code;
                  final fav = st.favorites.contains(s.code);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.accent.withOpacity(0.15) : AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: sel ? AppColors.accent : AppColors.border),
                    ),
                    child: ListTile(
                      onTap: () {
                        st.setSymbol(s);
                        st.setTab(0);
                        widget.onPicked?.call();
                      },
                      leading: CircleAvatar(
                        backgroundColor: AppColors.surface,
                        child: Text(
                          s.code.substring(0, s.code.length >= 2 ? 2 : 1),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.accent),
                        ),
                      ),
                      title: Text(s.code,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${s.name} • ${categoryAr[s.category]}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                      trailing: IconButton(
                        icon: Icon(fav ? Icons.star : Icons.star_border,
                            color: fav ? AppColors.gold : AppColors.muted),
                        onPressed: () => st.toggleFavorite(s.code),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
