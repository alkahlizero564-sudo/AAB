import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'backtest_screen.dart';
import 'chart_screen.dart';
import 'dashboard_screen.dart';
import 'markets_screen.dart';
import 'news_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _titles = ['التوصيات', 'الشارت', 'الأسواق', 'الأخبار', 'الإعدادات'];
  static const _icons = [
    Icons.insights_outlined,
    Icons.candlestick_chart_outlined,
    Icons.public_outlined,
    Icons.article_outlined,
    Icons.tune_outlined,
  ];
  static const _iconsOn = [
    Icons.insights,
    Icons.candlestick_chart,
    Icons.public,
    Icons.article,
    Icons.tune,
  ];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 4,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.goldGrad,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('A',
                style: TextStyle(
                    color: AppColors.onAccent, fontWeight: FontWeight.w900, fontSize: 17, height: 1.1)),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_titles[st.tab],
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.text, height: 1.15)),
            const Text('AAB PRO',
                style: TextStyle(
                    fontSize: 9.5, letterSpacing: 2, color: AppColors.accent, fontWeight: FontWeight.w700, height: 1.1)),
          ]),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.7, color: AppColors.border),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Material(
              color: AppColors.card,
              shape: const CircleBorder(side: BorderSide(color: AppColors.border, width: 0.8)),
              child: IconButton(
                tooltip: 'تحديث',
                visualDensity: VisualDensity.compact,
                icon: st.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 20, color: AppColors.gold),
                onPressed: st.refresh,
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2B2310), AppColors.surface],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.candlestick_chart, size: 40, color: AppColors.gold),
                SizedBox(height: 10),
                Text('AAB',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                Text('توصيات فوركس • ذهب • أسهم • كريبتو',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
            for (var i = 0; i < _titles.length; i++)
              ListTile(
                leading: Icon(st.tab == i ? _iconsOn[i] : _icons[i],
                    color: st.tab == i ? AppColors.accent : AppColors.muted),
                title: Text(_titles[i]),
                selected: st.tab == i,
                onTap: () {
                  st.setTab(i);
                  Navigator.of(context).pop();
                },
              ),
            ListTile(
              leading: const Icon(Icons.science, color: AppColors.muted),
              title: const Text('اختبار المحرك (Backtest)'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BacktestScreen()));
              },
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'التحليل الفني احتمالي ولا يضمن الربح — ليس نصيحة مالية.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
          ]),
        ),
      ),
      body: IndexedStack(
        index: st.tab,
        children: const [
          DashboardScreen(),
          ChartScreen(),
          MarketsScreen(),
          NewsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 66,
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border, width: 0.8),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Row(children: [
            for (final i in const [0, 2, 1, 3, 4])
              Expanded(
                child: i == 1
                    // زر الشارت في المنتصف: دائرة ذهبية بارزة
                    ? Center(
                        child: GestureDetector(
                          onTap: () => st.setTab(1),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: AppColors.goldGrad,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: st.tab == 1 ? AppColors.text : Colors.transparent, width: 1.5),
                              boxShadow: [
                                BoxShadow(color: AppColors.accent.withOpacity(0.45), blurRadius: 14),
                              ],
                            ),
                            child: const Icon(Icons.candlestick_chart, color: AppColors.onAccent, size: 26),
                          ),
                        ),
                      )
                    : InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => st.setTab(i),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                            decoration: BoxDecoration(
                              color: st.tab == i ? AppColors.accent.withOpacity(0.16) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(st.tab == i ? _iconsOn[i] : _icons[i],
                                size: 22, color: st.tab == i ? AppColors.gold : AppColors.muted),
                          ),
                          const SizedBox(height: 2),
                          Text(_titles[i],
                              style: TextStyle(
                                  fontSize: 10,
                                  height: 1.1,
                                  fontWeight: st.tab == i ? FontWeight.w700 : FontWeight.w500,
                                  color: st.tab == i ? AppColors.gold : AppColors.muted)),
                        ]),
                      ),
              ),
          ]),
        ),
      ),
    );
  }
}
