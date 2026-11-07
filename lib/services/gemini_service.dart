import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import 'settings_service.dart';

class AiResult {
  final String verdict; // BUY | SELL | WAIT
  final String comment;
  AiResult(this.verdict, this.comment);
}

class GeminiService {
  final http.Client _c = http.Client();
  KeyPool? _pool;
  String _sig = '';

  KeyPool _poolFor(AppSettings s) {
    final sig = s.geminiKeys.join('|');
    if (_pool == null || sig != _sig) {
      _pool = KeyPool(s.geminiKeys);
      _sig = sig;
    }
    return _pool!;
  }

  /// Sends [prompt] and returns the decoded JSON object the model answers with.
  Future<Map<String, dynamic>> askJson(String prompt, AppSettings s) async {
    final pool = _poolFor(s);
    if (pool.isEmpty) throw Exception('لا توجد مفاتيح Gemini');
    String last = 'فشل الطلب';
    for (var a = 0; a < pool.keys.length; a++) {
      final key = pool.next();
      if (key == null) break;
      try {
        final uri = Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models/${s.geminiModel}:generateContent',
          {'key': key},
        );
        final r = await _c
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt}
                    ]
                  }
                ],
                'generationConfig': {
                  'temperature': 0.2,
                  'responseMimeType': 'application/json',
                },
              }),
            )
            .timeout(const Duration(seconds: 40));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j['error'] != null) {
          last = '${j['error']['message']}';
          pool.penalize(key);
          continue;
        }
        var text = j['candidates'][0]['content']['parts'][0]['text'] as String;
        text = text.replaceAll('```json', '').replaceAll('```', '').trim();
        final o = jsonDecode(text);
        if (o is Map<String, dynamic>) return o;
        last = 'رد غير متوقع';
      } catch (e) {
        last = e.toString();
        pool.penalize(key, const Duration(seconds: 20));
      }
    }
    throw Exception(last);
  }

  String _prompt(MarketSymbol sym, String tf, TradeSignal t) {
    final dirText = t.direction == Direction.buy
        ? 'BUY'
        : t.direction == Direction.sell
            ? 'SELL'
            : 'WAIT';
    final votes = t.votes
        .map((v) => '${v.name}: ${v.value} (${v.vote > 0 ? '+' : v.vote < 0 ? '-' : '0'})')
        .join('\n');
    final pats = t.patterns.isEmpty
        ? 'لا يوجد'
        : t.patterns.map((p) => '${p.en} (${p.bias > 0 ? 'bullish' : p.bias < 0 ? 'bearish' : 'neutral'})').join(', ');
    return '''أنت محلل فني محترف. راجع نتائج المؤشرات الآلية التالية وأعطِ رأيك المستقل.
الرمز: ${sym.code} | الإطار: $tf | السعر: ${sym.fmt(t.price)}
إشارة المحرك الآلي: $dirText | القوة: ${t.strength.toStringAsFixed(0)}/100
الدخول: ${sym.fmt(t.entry)} | وقف الخسارة: ${sym.fmt(t.stopLoss)} | الهدف 1: ${sym.fmt(t.tp1)} | الهدف 2: ${sym.fmt(t.tp2)}
المؤشرات:
$votes
الشموع: $pats

أجب بـ JSON فقط بدون أي نص آخر بهذا الشكل:
{"verdict":"BUY أو SELL أو WAIT","comment":"جملتان أو ثلاث بالعربية تشرح الرأي وأهم المخاطر"}''';
  }

  Future<AiResult> review(
      MarketSymbol sym, String tf, TradeSignal t, AppSettings s) async {
    final o = await askJson(_prompt(sym, tf, t), s);
    return AiResult('${o['verdict']}'.toUpperCase(), '${o['comment']}');
  }
}
