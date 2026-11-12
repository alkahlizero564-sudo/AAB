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
    Icons.insights,
    Icons.candlestick_chart,
    Icons.currency_exchange,
    Icons.newspaper,
    Icons.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[st.tab],
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.gold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                AppColors.accent.withOpacity(0.7),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: st.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: st.refresh,
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
                leading: Icon(_icons[i],
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: st.tab,
        onDestinationSelected: st.setTab,
        destinations: [
          for (var i = 0; i < _titles.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _titles[i]),
        ],
      ),
    );
  }
}
