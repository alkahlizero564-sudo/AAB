import 'dart:math' as math;
import '../analysis/indicators.dart';
import '../analysis/levels.dart';
import '../analysis/signal_engine.dart';
import '../models.dart';
import 'gemini_service.dart';
import 'market_data_service.dart';
import 'settings_service.dart';

class PlanLevel {
  final String name;
  final double price;
  final String kind; // day, session, vp, vwap, fib, or
  const PlanLevel(this.name, this.price, this.kind);
}

/// A live-checked entry condition (like the "VWAP condition" in the video).
class Cond {
  final String text;
  final String kind; // above | below | flag
  final double level;
  final bool ok;
  const Cond(this.text, this.kind, {this.level = 0, this.ok = false});
  bool eval(double price) =>
      kind == 'above' ? price > level : (kind == 'below' ? price < level : ok);
}

class Scenario {
  final bool bull;
  final String trigger;
  final double triggerPrice, sl, tp1, tp2, tp3;
  final List<Cond> conds;
  const Scenario(this.bull, this.trigger, this.triggerPrice, this.sl, this.tp1,
      this.tp2, this.tp3, this.conds);
}

class PreMarketPlan {
  final MarketSymbol sym;
  final String session; // NY | LDN
  final DateTime openUtc, builtAt;
  final double price;
  final int bias; // +1 / 0 / -1
  final double confidence;
  final List<PlanLevel> levels;
  final OpeningRange? opening;
  final Scenario bull, bear;
  final List<String> notes;
  final int htfTrend;
  final double techScore;
  // AI part (filled after the numeric plan)
  String? newsSentiment; // bullish | bearish | neutral
  String? newsSummary;
  List<String> newsRisks = [];
  String? aiVerdict;
  List<String> headlines = [];

  PreMarketPlan({
    required this.sym,
    required this.session,
    required this.openUtc,
    required this.builtAt,
    required this.price,
    required this.bias,
    required this.confidence,
    required this.levels,
    required this.opening,
    required this.bull,
    required this.bear,
    required this.notes,
    required this.htfTrend,
    required this.techScore,
  });
}

class PreMarketService {
  final _market = MarketDataService();
  final _gemini = GeminiService();

  double _lastValid(List<double> v) {
    for (var i = v.length - 1; i >= 0; i--) {
      if (!v[i].isNaN) return v[i];
    }
    return double.nan;
  }

  Future<PreMarketPlan> build({
    required MarketSymbol sym,
    required String session,
    required AppSettings s,
  }) async {
    final now = DateTime.now().toUtc();
    final c1h = await _market.fetch(sym, '1h', s, count: 300);
    List<Candle>? c1d;
    try {
      c1d = await _market.fetch(sym, '1d', s, count: 90);
    } catch (_) {}
    var c5 = <Candle>[];
    try {
      c5 = await _market.fetch(sym, '5m', s, count: 300);
    } catch (_) {}

    final base = c5.length > 40 ? c5 : c1h;
    final price = base.last.close;
    final sig = SignalEngine.analyze(c1h, htf: c1d, s: s, sym: sym);

    final day = dayLevels(base, c1h, now);
    final vp = buildVp(c1h, look: 120);
    final fib = fibonacci(c1h, look: 120);
    final vw = vwapSeries(base, vwapAnchorTs(sym, now));
    final vwap = _lastValid(vw);
    final openUtc = sessionOpenUtc(session, now);
    final opening = (c5.isNotEmpty && !openUtc.isAfter(now))
        ? openingRange(c5, openUtc.millisecondsSinceEpoch ~/ 1000)
        : null;

    var a5 = _lastValid(atr(base, 14));
    if (a5.isNaN || a5 <= 0) a5 = price * 0.001;

    // ── levels ladder
    final lv = <PlanLevel>[];
    for (final k in buildKeyLevels(day, vp, vwap)) {
      lv.add(PlanLevel(k.name, k.price, k.kind));
    }
    if (fib != null) {
      for (final f in fib.levels) {
        if (f.ratio == 0.382 || f.ratio == 0.5 || f.ratio == 0.618 ||
            f.ratio == 0.786 || f.ratio == 1.272 || f.ratio == 1.618) {
          lv.add(PlanLevel('Fib ${f.ratio}', f.price, 'fib'));
        }
      }
    }
    if (opening != null) {
      lv.add(PlanLevel('OR High', opening.hi, 'or'));
      lv.add(PlanLevel('OR Low', opening.lo, 'or'));
    }

    // ── bias
    var pts = sig.score / 100 * 40;
    if (!day.dayOpen.isNaN) pts += price > day.dayOpen ? 10 : -10;
    if (!vwap.isNaN) pts += price > vwap ? 10 : -10;
    if (vp != null) pts += price > vp.poc ? 8 : -8;
    if (!day.pdc.isNaN) pts += price > day.pdc ? 8 : -8;
    pts += sig.htfTrend * 12;
    final bias = pts >= 15 ? 1 : (pts <= -15 ? -1 : 0);
    final conf = math.min(95.0, pts.abs());

    // ── scenarios
    Scenario scen(bool bull) {
      double trigger;
      String tText;
      if (opening != null && opening.complete) {
        trigger = bull ? opening.hi : opening.lo;
        tText = bull
            ? 'كسر أعلى نطاق الافتتاح بإغلاق شمعة 5 دقائق'
            : 'كسر أدنى نطاق الافتتاح بإغلاق شمعة 5 دقائق';
      } else {
        PlanLevel? near;
        for (final l in lv) {
          if (l.kind == 'vwap') continue;
          if (bull && l.price > price && (near == null || l.price < near.price)) near = l;
          if (!bull && l.price < price && (near == null || l.price > near.price)) near = l;
        }
        trigger = near?.price ?? (bull ? price + a5 : price - a5);
        tText = near == null
            ? 'كسر السعر الحالي بزخم'
            : 'كسر ${near.name} بإغلاق شمعة 5 دقائق';
      }
      // stop: nearest level on the other side with sensible distance
      double? sl;
      for (final l in lv) {
        final d = bull ? trigger - l.price : l.price - trigger;
        if (d >= a5 * 1.5 && d <= a5 * 6 && (sl == null || d < (bull ? trigger - sl : sl - trigger))) {
          sl = l.price;
        }
      }
      sl ??= bull ? trigger - a5 * 3 : trigger + a5 * 3;
      final risk = (trigger - sl).abs();
      final sg = bull ? 1 : -1;
      final conds = <Cond>[
        if (!vwap.isNaN)
          Cond(bull ? 'السعر فوق VWAP' : 'السعر تحت VWAP', bull ? 'above' : 'below',
              level: vwap),
        Cond(bull ? 'السعر فوق ${sym.fmt(trigger)}' : 'السعر تحت ${sym.fmt(trigger)}',
            bull ? 'above' : 'below', level: trigger),
        if (!day.dayOpen.isNaN)
          Cond(bull ? 'فوق افتتاح اليوم' : 'تحت افتتاح اليوم', bull ? 'above' : 'below',
              level: day.dayOpen),
        Cond(bull ? 'الإطار الأعلى صاعد' : 'الإطار الأعلى هابط', 'flag',
            ok: sig.htfTrend == sg),
        Cond(bull ? 'المحرك الفني يميل للصعود' : 'المحرك الفني يميل للهبوط', 'flag',
            ok: sig.score * sg > 10),
      ];
      return Scenario(bull, tText, trigger, sl, trigger + sg * risk * s.rr1,
          trigger + sg * risk * s.rr2, trigger + sg * risk * s.rr3, conds);
    }

    final notes = <String>[];
    if (bias == 0) notes.add('الاتجاه غير واضح — لا دخول قبل تأكيد الكسر.');
    if (opening != null && !opening.complete) {
      notes.add('نطاق الافتتاح ما اكتمل بعد — انتظر 30 دقيقة من الافتتاح.');
    }
    if (opening != null && opening.complete && price < opening.hi && price > opening.lo) {
      notes.add('السعر داخل نطاق الافتتاح — لا صفقة قبل الكسر (زي حالة 0 ENTRY بالفيديو).');
    }
    if (openUtc.isAfter(now)) {
      notes.add('السوق لم يفتح بعد — المستويات أدناه للتحضير فقط.');
    }

    return PreMarketPlan(
      sym: sym,
      session: session,
      openUtc: openUtc,
      builtAt: now,
      price: price,
      bias: bias,
      confidence: conf,
      levels: lv,
      opening: opening,
      bull: scen(true),
      bear: scen(false),
      notes: notes,
      htfTrend: sig.htfTrend,
      techScore: sig.score,
    );
  }

  List<String> _keywords(MarketSymbol sym) {
    const map = {
      'USD': ['dollar', 'usd', 'fed', 'powell', 'inflation', 'cpi', 'nfp', 'payroll', 'treasury', 'yields'],
      'EUR': ['euro', 'eur', 'ecb', 'lagarde'],
      'GBP': ['pound', 'sterling', 'gbp', 'boe', 'bailey'],
      'JPY': ['yen', 'jpy', 'boj'],
      'CHF': ['franc', 'chf', 'snb'],
      'AUD': ['aussie', 'aud', 'rba'],
      'CAD': ['loonie', 'cad', 'boc', 'oil'],
      'NZD': ['kiwi', 'nzd', 'rbnz'],
      'XAU': ['gold', 'xau', 'bullion'],
      'XAG': ['silver', 'xag'],
      'BTC': ['bitcoin', 'btc', 'crypto'],
      'ETH': ['ethereum', 'eth', 'crypto'],
    };
    final parts = sym.code.split('/');
    final out = <String>[];
    for (final p in parts) {
      out.addAll(map[p] ?? [p.toLowerCase()]);
    }
    if (sym.category == 'stock') out.add(sym.code.toLowerCase());
    return out;
  }

  /// Adds the news/AI layer (Gemini). Failures are non-fatal.
  Future<void> enrich(PreMarketPlan plan, List<NewsItem> news, AppSettings s) async {
    final kw = _keywords(plan.sym);
    final picked = <NewsItem>[
      ...news.where((n) {
        final t = '${n.title} ${n.summary}'.toLowerCase();
        return kw.any(t.contains);
      }).take(8),
    ];
    if (picked.length < 4) {
      for (final n in news) {
        if (picked.length >= 6) break;
        if (!picked.contains(n)) picked.add(n);
      }
    }
    plan.headlines = picked.map((n) => n.title).toList();
    if (!s.hasGemini || picked.isEmpty) return;

    final sym = plan.sym;
    String f(double v) => sym.fmt(v);
    final levels = (plan.levels.toList()..sort((a, b) => b.price.compareTo(a.price)))
        .map((l) => '${l.name}: ${f(l.price)}')
        .join(' | ');
    final prompt = '''أنت محلل أسواق. حلّل الوضع قبل افتتاح السوق وأعطِ خلاصة قصيرة وعملية.
الرمز: ${sym.code} | السعر الحالي: ${f(plan.price)}
الانحياز الفني الآلي: ${plan.bias > 0 ? 'صاعد' : plan.bias < 0 ? 'هابط' : 'محايد'} (ثقة ${plan.confidence.toStringAsFixed(0)}%)
المستويات: $levels
سيناريو الصعود: كسر ${f(plan.bull.triggerPrice)} | وقف ${f(plan.bull.sl)} | هدف ${f(plan.bull.tp1)}
سيناريو الهبوط: كسر ${f(plan.bear.triggerPrice)} | وقف ${f(plan.bear.sl)} | هدف ${f(plan.bear.tp1)}
عناوين الأخبار الأخيرة:
${picked.map((n) => '- ${n.title}').join('\n')}

مهم: لا تخترع أرقاماً غير المذكورة أعلاه.
أجب بـ JSON فقط:
{"sentiment":"bullish أو bearish أو neutral","summary":"ثلاث جمل بالعربية عن أثر الأخبار على الرمز","risks":["خطر 1","خطر 2"],"verdict":"BUY أو SELL أو WAIT"}''';
    try {
      final o = await _gemini.askJson(prompt, s);
      plan.newsSentiment = '${o['sentiment']}'.toLowerCase();
      plan.newsSummary = '${o['summary']}';
      plan.aiVerdict = '${o['verdict']}'.toUpperCase();
      final r = o['risks'];
      if (r is List) plan.newsRisks = r.map((e) => '$e').toList();
    } catch (_) {}
  }
}
