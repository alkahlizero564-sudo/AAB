import 'dart:convert';
import 'dart:io' show HttpDate;
import 'package:http/http.dart' as http;
import '../models.dart';

class NewsService {
  final http.Client _c = http.Client();

  static const _feeds = <String, String>{
    'FXStreet': 'https://www.fxstreet.com/rss/news',
    'Investing': 'https://www.investing.com/rss/news_1.rss',
    'Investing - سلع': 'https://www.investing.com/rss/news_11.rss',
  };

  Future<List<NewsItem>> fetch({String tiingoKey = ''}) async {
    final all = <NewsItem>[];
    final futures = <Future<List<NewsItem>>>[];
    _feeds.forEach((name, url) => futures.add(_rss(name, url)));
    if (tiingoKey.trim().isNotEmpty) futures.add(_tiingo(tiingoKey.trim()));
    final res = await Future.wait(futures.map((f) => f.catchError((_) => <NewsItem>[])));
    for (final r in res) {
      all.addAll(r);
    }
    final seen = <String>{};
    final out = all.where((n) => seen.add(n.title.toLowerCase())).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return out.take(80).toList();
  }

  String _clean(String s) {
    var t = s
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    return t.trim();
  }

  String? _tag(String block, String tag) {
    final m = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>').firstMatch(block);
    return m == null ? null : _clean(m.group(1)!);
  }

  Future<List<NewsItem>> _rss(String source, String url) async {
    final r = await _c
        .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 15));
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final items = RegExp(r'<item[\s>][\s\S]*?</item>').allMatches(body);
    final out = <NewsItem>[];
    for (final m in items) {
      final b = m.group(0)!;
      final title = _tag(b, 'title');
      final link = _tag(b, 'link');
      if (title == null || title.isEmpty || link == null) continue;
      var time = DateTime.now();
      final pd = _tag(b, 'pubDate');
      if (pd != null) {
        try {
          time = HttpDate.parse(pd);
        } catch (_) {
          try {
            time = DateTime.parse(pd);
          } catch (_) {}
        }
      }
      var desc = _tag(b, 'description') ?? '';
      if (desc.length > 220) desc = '${desc.substring(0, 220)}…';
      out.add(NewsItem(title, source, link, desc, time));
    }
    return out;
  }

  Future<List<NewsItem>> _tiingo(String key) async {
    final uri = Uri.https('api.tiingo.com', '/tiingo/news',
        {'limit': '40', 'token': key});
    final r = await _c.get(uri).timeout(const Duration(seconds: 15));
    final j = jsonDecode(r.body);
    if (j is! List) return [];
    return j.map<NewsItem>((e) {
      return NewsItem(
        '${e['title']}',
        'Tiingo • ${e['source'] ?? ''}',
        '${e['url']}',
        _clean('${e['description'] ?? ''}'),
        DateTime.tryParse('${e['publishedDate']}') ?? DateTime.now(),
      );
    }).toList();
  }
}
