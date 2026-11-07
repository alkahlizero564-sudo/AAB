import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'premarket_view.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  int tab = 0; // 0 = news, 1 = pre-market analysis

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('الأخبار'), icon: Icon(Icons.newspaper, size: 18)),
              ButtonSegment(
                  value: 1,
                  label: Text('تحليل قبل الافتتاح'),
                  icon: Icon(Icons.wb_twilight, size: 18)),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
      ),
      Expanded(
        child: tab == 0 ? const _NewsList() : const PreMarketView(),
      ),
    ]);
  }
}

class _NewsList extends StatelessWidget {
  const _NewsList();

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
    return 'منذ ${d.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return RefreshIndicator(
      onRefresh: st.loadNews,
      child: ListView(
        padding: const EdgeInsets.all(14),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            const Icon(Icons.circle, size: 9, color: AppColors.up),
            const SizedBox(width: 6),
            const Text('أخبار السوق لحظة بلحظة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (st.newsLoading)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 12),
          if (st.newsError != null && st.news.isEmpty) ErrorBanner(st.newsError!),
          for (final n in st.news)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => launchUrl(Uri.parse(n.url),
                  mode: LaunchMode.externalApplication),
              child: Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14, height: 1.4)),
                  if (n.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(n.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12, height: 1.4)),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(n.source,
                        style: const TextStyle(
                            color: AppColors.accent, fontSize: 11)),
                    const Spacer(),
                    Text(_ago(n.time),
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 11)),
                  ]),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
