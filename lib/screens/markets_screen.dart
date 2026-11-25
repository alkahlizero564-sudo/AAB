import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/symbols.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'scanner_screen.dart';
import '../widgets/common.dart';

/// شاشة الأسواق: ساعة الجلسات، السوق الحالي، المفضلة، وكل الأسواق مقسّمة حسب النوع مع حالة الفتح.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});
  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

/// هل السوق مفتوح الآن (تقريبي بتوقيت UTC).
bool marketOpen(MarketSymbol s, DateTime u) {
  if (s.category == 'crypto') return true;
  final wd = u.weekday, h = u.hour + u.minute / 60;
  if (s.category == 'stock' || s.category == 'index') {
    if (wd > 5) return false;
    final summer = u.month >= 3 && u.month <= 10;
    final o = summer ? 13.5 : 14.5, c = summer ? 20.0 : 21.0;
    return h >= o && h < c;
  }
  // عملات ومعادن: من مساء الأحد إلى مساء الجمعة
  if (wd == 6) return false;
  if (wd == 7) return h >= 21;
  if (wd == 5) return h < 21;
  return true;
}

class _Session {
  final String name;
  final double from, to; // UTC
  const _Session(this.name, this.from, this.to);
  bool open(DateTime u) {
    if (u.weekday == 6 || (u.weekday == 7 && u.hour < 21) || (u.weekday == 5 && u.hour >= 21)) return false;
    final h = u.hour + u.minute / 60;
    return from < to ? (h >= from && h < to) : (h >= from || h < to);
  }
}

const _sessions = [
  _Session('سيدني', 21, 6),
  _Session('طوكيو', 0, 9),
  _Session('لندن', 7, 16),
  _Session('نيويورك', 12.5, 21),
];

const _catIcon = {
  'all': Icons.apps_rounded,
  'fav': Icons.star_rounded,
  'metal': Icons.diamond_outlined,
  'crypto': Icons.currency_bitcoin_rounded,
  'major': Icons.currency_exchange_rounded,
  'minor': Icons.swap_horiz_rounded,
  'exotic': Icons.public_rounded,
  'index': Icons.show_chart_rounded,
  'stock': Icons.business_center_outlined,
};
const _catOrder = ['metal', 'crypto', 'index', 'major', 'minor', 'exotic', 'stock'];

class _MarketsScreenState extends State<MarketsScreen> {
  String q = '';
  String cat = 'all';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final now = DateTime.now().toUtc();
    final cats = <String, String>{'all': 'الكل', 'fav': 'المفضلة', for (final k in _catOrder) k: categoryAr[k]!};
    bool match(MarketSymbol s) {
      if (cat == 'fav' && !st.favorites.contains(s.code)) return false;
      if (cat != 'all' && cat != 'fav' && s.category != cat) return false;
      if (q.isEmpty) return true;
      return s.code.toLowerCase().contains(q.toLowerCase()) || s.name.contains(q);
    }

    final list = allSymbols.where(match).toList();
    final favs = [for (final s in allSymbols) if (st.favorites.contains(s.code)) s];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _SessionsBar(now: now),
        const SizedBox(height: 12),
        _ScannerButton(),
        const SizedBox(height: 12),
        _CurrentCard(st: st),
        const SizedBox(height: 12),
        // البحث
        TextField(
          onChanged: (v) => setState(() => q = v.trim()),
          decoration: InputDecoration(
            hintText: 'ابحث: ذهب، EUR/USD، بيتكوين، AAPL',
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.gold),
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.gold)),
          ),
        ),
        const SizedBox(height: 10),
        // الفئات
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in cats.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => cat = e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: cat == e.key ? AppColors.goldGrad : null,
                        color: cat == e.key ? null : AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: cat == e.key ? null : Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_catIcon[e.key], size: 15, color: cat == e.key ? AppColors.onAccent : AppColors.gold),
                        const SizedBox(width: 5),
                        Text(e.value,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: cat == e.key ? AppColors.onAccent : AppColors.text)),
                        const SizedBox(width: 5),
                        Text(
                            '${e.key == 'all' ? allSymbols.length : e.key == 'fav' ? favs.length : allSymbols.where((s) => s.category == e.key).length}',
                            style: TextStyle(fontSize: 10.5, color: cat == e.key ? AppColors.onAccent.withOpacity(0.7) : AppColors.muted)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // المفضلة كبطاقات
        if (favs.isNotEmpty && cat == 'all' && q.isEmpty) ...[
          const SizedBox(height: 14),
          const _Head('المفضلة', Icons.star_rounded),
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [for (final s in favs) _FavCard(s: s, st: st, open: marketOpen(s, now))],
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: Text('لا نتائج', style: TextStyle(color: AppColors.muted))),
          )
        else
          for (final c in _catOrder)
            if (list.any((s) => s.category == c)) ...[
              const SizedBox(height: 10),
              _Head('${categoryAr[c]}', _catIcon[c]!,
                  trailing: '${list.where((s) => s.category == c && marketOpen(s, now)).length} مفتوح'),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Column(children: [
                  for (final (k, s) in list.where((s) => s.category == c).indexed)
                    _Row(s: s, st: st, open: marketOpen(s, now), first: k == 0),
                ]),
              ),
            ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  final String t;
  final IconData i;
  final String? trailing;
  const _Head(this.t, this.i, {this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7, right: 2, left: 2),
        child: Row(children: [
          Icon(i, size: 17, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      );
}

/// ساعة الجلسات: أي الأسواق العالمية مفتوحة الآن.
class _SessionsBar extends StatelessWidget {
  final DateTime now;
  const _SessionsBar({required this.now});
  @override
  Widget build(BuildContext context) {
    final openCount = _sessions.where((s) => s.open(now)).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [Color(0xFF1A1710), AppColors.card], begin: Alignment.topRight, end: Alignment.bottomLeft),
        border: Border.all(color: AppColors.accent.withOpacity(0.35), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 17, color: AppColors.gold),
          const SizedBox(width: 6),
          const Text('جلسات التداول', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13.5)),
          const Spacer(),
          Text(
              openCount == 0
                  ? 'عطلة نهاية الأسبوع'
                  : _sessions.where((s) => s.open(now)).length >= 2
                      ? 'تداخل جلسات — حركة أقوى'
                      : 'جلسة واحدة مفتوحة',
              style: TextStyle(color: openCount >= 2 ? AppColors.up : AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (final s in _sessions)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: s.open(now) ? AppColors.up.withOpacity(0.13) : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: s.open(now) ? AppColors.up.withOpacity(0.7) : AppColors.border, width: 0.8),
                ),
                child: Column(children: [
                  Text(s.name,
                      style: TextStyle(
                          color: s.open(now) ? AppColors.text : AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: s.open(now) ? AppColors.up : AppColors.muted, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(s.open(now) ? 'مفتوحة' : 'مغلقة',
                        style: TextStyle(color: s.open(now) ? AppColors.up : AppColors.muted, fontSize: 10)),
                  ]),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// بطاقة السوق الحالي: السعر، تغيّر اليوم، خط السعر، وزر الشارت.
class _CurrentCard extends StatelessWidget {
  final AppState st;
  const _CurrentCard({required this.st});
  @override
  Widget build(BuildContext context) {
    final c = st.candles;
    final px = c.isEmpty ? double.nan : c.last.close;
    double chg = 0;
    if (c.length > 2) {
      final ds = c.lastIndexWhere((k) => k.time.day != c.last.time.day);
      final ref = c[ds < 0 ? 0 : ds].close;
      chg = (c.last.close - ref) / ref * 100;
    }
    final col = chg >= 0 ? AppColors.up : AppColors.down;
    final closes = [for (final k in c.skip(math.max(0, c.length - 80))) k.close];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(children: [
        SymbolBadge(st.symbol.code, size: 40),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('السوق الحالي', style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
            Text(st.symbol.code, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 15)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(px.isNaN ? '—' : st.symbol.fmt(px),
                    style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(width: 5),
                Text('${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%', style: TextStyle(color: col, fontSize: 11)),
              ]),
            ),
          ]),
        ),
        Expanded(flex: 4, child: Sparkline(closes, color: col, height: 44)),
        const SizedBox(width: 8),
        Material(
          color: AppColors.surface,
          shape: const CircleBorder(side: BorderSide(color: AppColors.gold, width: 0.8)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => st.setTab(1),
            child: const Padding(
              padding: EdgeInsets.all(9),
              child: Icon(Icons.candlestick_chart_rounded, color: AppColors.gold, size: 19),
            ),
          ),
        ),
      ]),
    );
  }
}

class _FavCard extends StatelessWidget {
  final MarketSymbol s;
  final AppState st;
  final bool open;
  const _FavCard({required this.s, required this.st, required this.open});
  @override
  Widget build(BuildContext context) {
    final sel = s.code == st.symbol.code;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          st.setSymbol(s);
          st.setTab(0);
        },
        child: Container(
          width: 132,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: sel ? AppColors.goldGrad : null,
            color: sel ? null : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: sel ? null : Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Row(children: [
            SymbolBadge(s.code, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(s.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: sel ? AppColors.onAccent : AppColors.text)),
                Row(children: [
                  Container(
                      width: 6, height: 6, decoration: BoxDecoration(color: open ? AppColors.up : AppColors.muted, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(open ? 'مفتوح' : 'مغلق',
                      style: TextStyle(fontSize: 10, color: sel ? AppColors.onAccent.withOpacity(0.75) : AppColors.muted)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final MarketSymbol s;
  final AppState st;
  final bool open, first;
  const _Row({required this.s, required this.st, required this.open, required this.first});
  @override
  Widget build(BuildContext context) {
    final sel = s.code == st.symbol.code;
    final fav = st.favorites.contains(s.code);
    return InkWell(
      onTap: () {
        st.setSymbol(s);
        st.setTab(0);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
        decoration: BoxDecoration(
          color: sel ? AppColors.accent.withOpacity(0.08) : null,
          border: first ? null : Border(top: BorderSide(color: AppColors.border.withOpacity(0.5), width: 0.6)),
        ),
        child: Row(children: [
          SymbolBadge(s.code, size: 34),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(s.code,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: sel ? AppColors.gold : AppColors.text)),
                if (sel) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.18), borderRadius: BorderRadius.circular(6)),
                    child: const Text('الحالي', style: TextStyle(color: AppColors.gold, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              Text(s.name, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: (open ? AppColors.up : AppColors.muted).withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: open ? AppColors.up : AppColors.muted, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(open ? 'مفتوح' : 'مغلق',
                  style: TextStyle(color: open ? AppColors.up : AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'افتح الشارت',
            icon: const Icon(Icons.candlestick_chart_outlined, color: AppColors.muted, size: 20),
            onPressed: () {
              st.setSymbol(s);
              st.setTab(1);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded, color: fav ? AppColors.gold : AppColors.muted),
            onPressed: () => st.toggleFavorite(s.code),
          ),
        ]),
      ),
    );
  }
}


/// زر ماسح الأسواق: يفتح شاشة تفحص كل الأسواق وتعرض الإشارات القوية الآن.
class _ScannerButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScannerScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppColors.goldGrad,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(children: [
            Icon(Icons.radar_rounded, color: AppColors.onAccent),
            SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ماسح الأسواق', style: TextStyle(color: AppColors.onAccent, fontWeight: FontWeight.w800, fontSize: 15)),
                Text('أين توجد إشارة قوية الآن؟ (AK • King • النجوم)', style: TextStyle(color: AppColors.onAccent, fontSize: 11.5)),
              ]),
            ),
            Icon(Icons.chevron_left_rounded, color: AppColors.onAccent),
          ]),
        ),
      );
}
