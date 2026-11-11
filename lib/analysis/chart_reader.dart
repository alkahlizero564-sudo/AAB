import 'dart:math' as math;
import '../models.dart';
import 'indicator_panel.dart';
import 'indicators.dart';
import 'patterns.dart';
import 'pro.dart';
import 'smc.dart';

/// قسم من قراءة الشارت (اتجاه، هيكل، مناطق، شموع...).
class ReadSection {
  final String icon, title;
  final List<String> lines;
  final int bias; // +1 لصالح المشترين ، -1 لصالح البائعين ، 0 محايد
  const ReadSection(this.icon, this.title, this.lines, this.bias);
}

class ChartReading {
  final List<ReadSection> sections;
  final int bias; // الخلاصة: +1 / -1 / 0
  final String verdict;
  final List<String> scenarios;
  const ChartReading(this.sections, this.bias, this.verdict, this.scenarios);
}

/// معنى كل نموذج شموع كما يفهمه المتداول.
const patternMeaning = {
  'Hammer': 'البائعون دفعوا السعر للأسفل بقوة ثم عاد المشترون وأغلقوا قرب القمة — رفض واضح للأسعار المنخفضة.',
  'Inverted Hammer': 'محاولة شراء بعد هبوط؛ تحتاج شمعة تأكيد صاعدة لأن المشترين لم يحافظوا على القمة.',
  'Hanging Man': 'بعد صعود ظهر ضغط بيع قوي داخل الشمعة — تحذير من ضعف المشترين.',
  'Shooting Star': 'المشترون دفعوا السعر للأعلى ثم سيطر البائعون وأغلقوا قرب القاع — رفض للأسعار المرتفعة.',
  'Bullish Engulfing': 'شمعة صاعدة ابتلعت جسم الهابطة بالكامل — المشترون انتزعوا السيطرة.',
  'Bearish Engulfing': 'شمعة هابطة ابتلعت جسم الصاعدة بالكامل — البائعون انتزعوا السيطرة.',
  'Piercing Line': 'بعد شمعة هابطة افتتح السعر أدنى ثم أغلق فوق منتصفها — دخول مشترين أقوياء.',
  'Dark Cloud Cover': 'بعد شمعة صاعدة افتتح أعلى ثم أغلق تحت منتصفها — دخول بائعين أقوياء.',
  'Bullish Harami': 'شمعة صغيرة داخل جسم هابطة كبيرة — الهبوط فقد زخمه (تردد).',
  'Bearish Harami': 'شمعة صغيرة داخل جسم صاعدة كبيرة — الصعود فقد زخمه (تردد).',
  'Bullish Harami Cross': 'دوجي داخل شمعة هابطة كبيرة — توقف البيع وتوازن تام، احتمال انعكاس.',
  'Bearish Harami Cross': 'دوجي داخل شمعة صاعدة كبيرة — توقف الشراء وتوازن تام، احتمال انعكاس.',
  'Tweezer Bottom': 'قاعان متساويان متتاليان — السعر رُفض مرتين من نفس المستوى (دعم).',
  'Tweezer Top': 'قمتان متساويتان متتاليتان — السعر رُفض مرتين من نفس المستوى (مقاومة).',
  'Morning Star': 'هبوط قوي ثم شمعة تردد ثم صعود قوي — انعكاس صاعد من ثلاث مراحل.',
  'Evening Star': 'صعود قوي ثم شمعة تردد ثم هبوط قوي — انعكاس هابط من ثلاث مراحل.',
  'Three White Soldiers': 'ثلاث شموع صاعدة متتالية بإغلاقات أعلى — سيطرة شرائية مستمرة.',
  'Three Black Crows': 'ثلاث شموع هابطة متتالية بإغلاقات أدنى — سيطرة بيعية مستمرة.',
  'Three Inside Up': 'هارامي صاعد ثم شمعة تأكيد أغلقت فوق الشمعة الأولى — انعكاس مؤكد.',
  'Three Inside Down': 'هارامي هابط ثم شمعة تأكيد أغلقت تحت الشمعة الأولى — انعكاس مؤكد.',
  'Three Outside Up': 'ابتلاع صاعد ثم شمعة صاعدة تؤكده — انعكاس قوي.',
  'Three Outside Down': 'ابتلاع هابط ثم شمعة هابطة تؤكده — انعكاس قوي.',
  'Bullish Marubozu': 'شمعة صاعدة بلا ذيول تقريباً — المشترون سيطروا من الافتتاح للإغلاق.',
  'Bearish Marubozu': 'شمعة هابطة بلا ذيول تقريباً — البائعون سيطروا من الافتتاح للإغلاق.',
  'Dragonfly Doji': 'هبوط داخل الشمعة ثم عودة كاملة للافتتاح — رفض قوي للأسعار الدنيا.',
  'Gravestone Doji': 'صعود داخل الشمعة ثم عودة كاملة للافتتاح — رفض قوي للأسعار العليا.',
  'Long-legged Doji': 'حركة كبيرة في الاتجاهين وإغلاق عند الافتتاح — تردد شديد، انتظر الشمعة التالية.',
  'Doji': 'الافتتاح = الإغلاق تقريباً — توازن بين المشترين والبائعين.',
  'Spinning Top': 'جسم صغير وذيول متوازنة — تردد وضعف في الاتجاه الحالي.',
  'Bullish Outside Bar': 'شمعة صاعدة غطّت مدى السابقة كاملاً — توسع شرائي.',
  'Bearish Outside Bar': 'شمعة هابطة غطّت مدى السابقة كاملاً — توسع بيعي.',
  'Inside Bar': 'شمعة داخل مدى السابقة — ضغط وتجميع قبل حركة؛ الكسر يحدد الاتجاه.',
  'Rising Three Methods': 'تصحيح صغير داخل شمعة صاعدة كبيرة ثم استئناف — استمرار الصعود.',
  'Falling Three Methods': 'تصحيح صغير داخل شمعة هابطة كبيرة ثم استئناف — استمرار الهبوط.',
};

String _f(MarketSymbol s, double v) => s.fmt(v);
String _pct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

/// مستوى دعم/مقاومة مع مصدره.
class _Lvl {
  final double p;
  final String name;
  const _Lvl(this.p, this.name);
}

/// يقرأ الشارت كما هو عند الشمعة [upto] (افتراضياً آخر شمعة) — بدون النظر لما بعدها.
ChartReading readChart(List<Candle> all, MarketSymbol sym, {int? upto, List<Candle>? htf}) {
  final end = (upto ?? all.length - 1).clamp(0, all.length - 1);
  final c = all.sublist(0, end + 1);
  final n = c.length;
  if (n < 60) {
    return const ChartReading([], 0, 'بيانات غير كافية لقراءة الشارت (أقل من 60 شمعة).', []);
  }
  final i = n - 1;
  final cl = c.map((e) => e.close).toList();
  final price = cl[i];
  final at = atr(c, 14);
  final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
  final e20 = ema(cl, 20), e50 = ema(cl, 50), e200 = ema(cl, 200);
  final sections = <ReadSection>[];
  var score = 0.0;

  // ───── 1) الاتجاه
  {
    final lines = <String>[];
    var b = 0;
    if (!e200[i].isNaN) {
      final slope = (e200[i] - e200[math.max(0, i - 20)]) / a;
      lines.add(price > e200[i]
          ? 'السعر فوق EMA200 (${_f(sym, e200[i])}) — الاتجاه الكبير صاعد، والشراء هو الأفضلية.'
          : 'السعر تحت EMA200 (${_f(sym, e200[i])}) — الاتجاه الكبير هابط، والبيع هو الأفضلية.');
      if (slope.abs() < 0.3) lines.add('EMA200 شبه أفقي — الاتجاه الكبير ضعيف أو السوق عرضي.');
      b += price > e200[i] ? 1 : -1;
    }
    if (!e20[i].isNaN && !e50[i].isNaN) {
      if (price > e20[i] && e20[i] > e50[i]) {
        lines.add('ترتيب المتوسطات صاعد: السعر > EMA20 > EMA50 — زخم شرائي قصير المدى.');
        b++;
      } else if (price < e20[i] && e20[i] < e50[i]) {
        lines.add('ترتيب المتوسطات هابط: السعر < EMA20 < EMA50 — زخم بيعي قصير المدى.');
        b--;
      } else {
        lines.add('المتوسطات متشابكة — لا اتجاه واضح على المدى القصير (تذبذب أو تصحيح).');
      }
      final dist = (price - e20[i]) / a;
      if (dist.abs() > 2) {
        lines.add('السعر بعيد عن EMA20 بـ ${dist.abs().toStringAsFixed(1)} ATR — '
            'حركة ممتدة، والعودة نحو المتوسط واردة قبل الاستمرار.');
      }
    }
    final ad = adxCalc(c);
    final adx = ad.adx[i];
    if (!adx.isNaN) {
      lines.add(adx >= 25
          ? 'ADX = ${adx.toStringAsFixed(0)}: اتجاه قوي — استراتيجيات تتبع الاتجاه تعمل أفضل.'
          : adx >= 18
              ? 'ADX = ${adx.toStringAsFixed(0)}: اتجاه متوسط.'
              : 'ADX = ${adx.toStringAsFixed(0)}: لا يوجد اتجاه قوي — السوق عرضي غالباً، والارتداد من الحدود أفضل من الاختراقات.');
    }
    if (htf != null && htf.length >= 55 && upto == null) {
      final hc = htf.map((e) => e.close).toList();
      final h20 = ema(hc, 20).last, h50 = ema(hc, 50).last;
      if (!h20.isNaN && !h50.isNaN) {
        final hd = hc.last > h50 && h20 > h50 ? 1 : (hc.last < h50 && h20 < h50 ? -1 : 0);
        lines.add(hd == 1
            ? 'الإطار الأعلى صاعد — يدعم الشراء.'
            : hd == -1
                ? 'الإطار الأعلى هابط — يدعم البيع.'
                : 'الإطار الأعلى بدون اتجاه واضح.');
      }
    }
    final bias = b > 0 ? 1 : (b < 0 ? -1 : 0);
    score += b * 1.0;
    sections.add(ReadSection('📈', 'الاتجاه', lines, bias));
  }

  // ───── 2) هيكل السوق
  final st = marketStructure(c);
  {
    final lines = <String>[st.label];
    if (st.choch) {
      lines.add(st.breakDir < 0
          ? 'كان الاتجاه صاعداً (قمم وقيعان أعلى) لكن السعر أغلق تحت آخر قاع — المشترون فقدوا السيطرة.'
          : 'كان الاتجاه هابطاً (قمم وقيعان أدنى) لكن السعر أغلق فوق آخر قمة — البائعون فقدوا السيطرة.');
    } else if (st.trend == 1) {
      lines.add('القمم والقيعان ترتفع — هذا تعريف الاتجاه الصاعد عند محترفي Price Action.');
    } else if (st.trend == -1) {
      lines.add('القمم والقيعان تنخفض — هذا تعريف الاتجاه الهابط.');
    } else {
      lines.add('لا تتابع واضح للقمم والقيعان — السوق في نطاق أو في مرحلة انتقال.');
    }
    if (st.swingLow != null) {
      lines.add('آخر قاع مهم: ${_f(sym, st.swingLow!)} — كسره بإغلاق يُضعف المشترين.');
    }
    if (st.swingHigh != null) {
      lines.add('آخر قمة مهمة: ${_f(sym, st.swingHigh!)} — اختراقها بإغلاق يُضعف البائعين.');
    }
    if (st.choch) {
      lines.add('⚠️ CHoCH: السعر كسر هيكل الاتجاه السابق — أول علامة على احتمال انعكاسه.');
    }
    score += st.trend * 1.5 + (st.choch ? st.breakDir * 1.0 : 0);
    sections.add(ReadSection('🏗️', 'هيكل السوق', lines, st.choch ? st.breakDir : st.trend));
  }

  // ───── 3) الدعوم والمقاومات
  final sup = <_Lvl>[], res = <_Lvl>[];
  {
    void add(double p, String name) {
      if (p.isNaN) return;
      if (p < price) sup.add(_Lvl(p, name));
      if (p > price) res.add(_Lvl(p, name));
    }

    final ph = pivotHighs(c, 5, 3), pl = pivotLows(c, 5, 3);
    for (final p in ph.where((p) => p.i >= n - 150)) {
      add(p.p, p.p > price ? 'قمة سابقة' : 'قمة سابقة تحولت لدعم');
    }
    for (final p in pl.where((p) => p.i >= n - 150)) {
      add(p.p, p.p < price ? 'قاع سابق' : 'قاع سابق تحول لمقاومة');
    }
    for (final z in orderBlocks(c)) {
      add(z.bias > 0 ? z.top : z.bottom, z.bias > 0 ? 'Order Block شرائي' : 'Order Block بيعي');
    }
    for (final z in fairValueGaps(c, at)) {
      add(z.bias > 0 ? z.top : z.bottom, 'فجوة سعرية FVG');
    }
    add(e50[i], 'EMA50');
    add(e200[i], 'EMA200');
    final (rb, ra) = roundBand(sym, price);
    add(rb, 'رقم مستدير');
    add(ra, 'رقم مستدير');
    sup.sort((x, y) => y.p.compareTo(x.p));
    res.sort((x, y) => x.p.compareTo(y.p));
    // دمج المستويات المتقاربة (أقل من 0.6 ATR) في مستوى واحد يجمع أسماءها
    List<_Lvl> merge(List<_Lvl> l) {
      final out = <_Lvl>[];
      for (final x in l) {
        if (out.isNotEmpty && (x.p - out.last.p).abs() < 0.6 * a) {
          final last = out.removeLast();
          final names = {...last.name.split(' + '), x.name}.take(3).join(' + ');
          out.add(_Lvl(last.p, names));
        } else {
          out.add(x);
        }
      }
      return out;
    }

    final ms = merge(sup), mr = merge(res);
    sup
      ..clear()
      ..addAll(ms);
    res
      ..clear()
      ..addAll(mr);

    final lines = <String>[];
    String desc(_Lvl l) {
      final d = (l.p - price).abs() / a;
      return '${_f(sym, l.p)} (${l.name}) — على بعد ${d.toStringAsFixed(1)} ATR';
    }

    if (res.isNotEmpty) lines.add('أقرب مقاومة: ${desc(res.first)}');
    if (res.length > 1) lines.add('المقاومة التالية: ${desc(res[1])}');
    if (sup.isNotEmpty) lines.add('أقرب دعم: ${desc(sup.first)}');
    if (sup.length > 1) lines.add('الدعم التالي: ${desc(sup[1])}');
    var b = 0;
    if (sup.isNotEmpty && res.isNotEmpty) {
      final ds = price - sup.first.p, dr = res.first.p - price;
      if (ds < 0.5 * a) {
        lines.add('السعر ملاصق للدعم — منطقة يبحث فيها المحترفون عن شموع رفض للشراء، '
            'والإغلاق تحته يعني كسر الدعم.');
        b = 1;
      } else if (dr < 0.5 * a) {
        lines.add('السعر ملاصق للمقاومة — منطقة يبحث فيها المحترفون عن شموع رفض للبيع، '
            'والإغلاق فوقها يعني اختراق.');
        b = -1;
      } else {
        lines.add(dr > 2 * ds
            ? 'المسافة للمقاومة أكبر بكثير من المسافة للدعم — مساحة جيدة للصعود مقابل مخاطرة صغيرة.'
            : ds > 2 * dr
                ? 'المسافة للدعم أكبر بكثير من المسافة للمقاومة — مساحة جيدة للهبوط.'
                : 'السعر في منتصف المسافة بين الدعم والمقاومة — موقع غير مثالي للدخول.');
      }
    }
    score += b * 0.8;
    sections.add(ReadSection('🧱', 'الدعوم والمقاومات', lines, b));
  }

  // ───── 4) الشموع والنماذج
  {
    final lines = <String>[];
    var b = 0.0;
    final hits = detectPatterns(c);
    for (final h in hits) {
      final atSup = sup.isNotEmpty && (price - sup.first.p) < 1.0 * a;
      final atRes = res.isNotEmpty && (res.first.p - price) < 1.0 * a;
      var ctx = '';
      if (h.bias > 0) {
        ctx = atSup
            ? ' • تكوّنت عند دعم ← إشارتها أقوى.'
            : ' • ليست عند دعم واضح ← إشارتها أضعف، تحتاج تأكيداً.';
      } else if (h.bias < 0) {
        ctx = atRes
            ? ' • تكوّنت عند مقاومة ← إشارتها أقوى.'
            : ' • ليست عند مقاومة واضحة ← إشارتها أضعف، تحتاج تأكيداً.';
      }
      lines.add('${h.ar}: ${patternMeaning[h.en] ?? ''}$ctx');
      b += h.bias * h.weight * (ctx.contains('أقوى') ? 1.5 : 0.7);
    }
    if (hits.isEmpty) lines.add('لا يوجد نموذج شموع واضح على آخر الشموع.');
    final last = c[i];
    final rng = last.high - last.low;
    if (rng > 0) {
      final body = (last.close - last.open).abs();
      final uw = last.high - math.max(last.open, last.close);
      final lw = math.min(last.open, last.close) - last.low;
      final size = rng / a;
      lines.add('آخر شمعة ${last.close >= last.open ? 'صاعدة' : 'هابطة'}، '
          'حجمها ${size.toStringAsFixed(1)}× المعتاد، الجسم ${(body / rng * 100).toStringAsFixed(0)}% من مداها'
          '${uw > 0.5 * rng ? '، ذيل علوي طويل (رفض للأعلى)' : ''}'
          '${lw > 0.5 * rng ? '، ذيل سفلي طويل (رفض للأسفل)' : ''}.');
    }
    for (final p in chartPatterns(c, a)) {
      lines.add('نموذج فني: ${p.name} (${p.bias > 0 ? 'صاعد' : 'هابط'}) — مؤكد بإغلاق بعد خط العنق/الترند.');
      b += p.bias * 2;
    }
    final bias = b > 0.3 ? 1 : (b < -0.3 ? -1 : 0);
    score += b.clamp(-3.0, 3.0);
    sections.add(ReadSection('🕯️', 'الشموع والنماذج', lines, bias));
  }

  // ───── 5) الزخم
  {
    final lines = <String>[];
    var b = 0;
    final r = rsi(cl, 14);
    final rv = r[i];
    if (!rv.isNaN) {
      lines.add(rv >= 70
          ? 'RSI = ${rv.toStringAsFixed(0)}: تشبع شرائي — الصعود قوي لكن الدخول شراءً الآن متأخر.'
          : rv <= 30
              ? 'RSI = ${rv.toStringAsFixed(0)}: تشبع بيعي — الهبوط قوي لكن البيع الآن متأخر.'
              : rv > 50
                  ? 'RSI = ${rv.toStringAsFixed(0)}: فوق 50 — الزخم لصالح المشترين.'
                  : 'RSI = ${rv.toStringAsFixed(0)}: تحت 50 — الزخم لصالح البائعين.');
      b += rv > 50 ? 1 : -1;
      // انحراف بين آخر قاعين/قمتين
      final pl = pivotLows(c, 3, 2).where((p) => p.i >= n - 50).toList();
      final ph = pivotHighs(c, 3, 2).where((p) => p.i >= n - 50).toList();
      if (pl.length >= 2) {
        final p2 = pl.last, p1 = pl[pl.length - 2];
        if (p2.p < p1.p && !r[p2.i].isNaN && !r[p1.i].isNaN && r[p2.i] > r[p1.i] + 2) {
          lines.add('انحراف إيجابي: السعر صنع قاعاً أدنى لكن RSI صنع قاعاً أعلى — البائعون يضعفون.');
          b += 2;
        }
      }
      if (ph.length >= 2) {
        final p2 = ph.last, p1 = ph[ph.length - 2];
        if (p2.p > p1.p && !r[p2.i].isNaN && !r[p1.i].isNaN && r[p2.i] < r[p1.i] - 2) {
          lines.add('انحراف سلبي: السعر صنع قمة أعلى لكن RSI صنع قمة أدنى — المشترون يضعفون.');
          b -= 2;
        }
      }
    }
    final m = macd(cl);
    final h = m.hist[i], hp = m.hist[i - 1];
    if (!h.isNaN && !hp.isNaN) {
      final grow = h.abs() > hp.abs();
      lines.add('MACD ${h > 0 ? 'إيجابي' : 'سلبي'} و${grow ? 'يتسارع' : 'يتباطأ'} — '
          '${h > 0 ? (grow ? 'المشترون يزدادون قوة' : 'المشترون يفقدون الزخم') : (grow ? 'البائعون يزدادون قوة' : 'البائعون يفقدون الزخم')}.');
      b += h > 0 ? 1 : -1;
    }
    final bias = b > 0 ? 1 : (b < 0 ? -1 : 0);
    score += b * 0.6;
    sections.add(ReadSection('⚡', 'الزخم', lines, bias));
  }

  // ───── 6) التقلب والحجم
  {
    final lines = <String>[];
    final reg = volRegime(at);
    lines.add(reg == 'quiet'
        ? 'التقلب منخفض جداً (هدوء) — غالباً يسبق حركة قوية؛ انتظر كسر النطاق.'
        : reg == 'hot'
            ? 'التقلب مرتفع جداً — الحركات حادة، كبّر الوقف أو قلّل حجم الصفقة.'
            : 'التقلب طبيعي — متوسط حركة الشمعة ${_f(sym, a)}.');
    final hasVol = c.sublist(n - 20).every((e) => e.volume > 0);
    var b = 0;
    if (hasVol) {
      var avg = 0.0;
      for (var j = n - 21; j < n - 1; j++) {
        avg += c[j].volume;
      }
      avg /= 20;
      final vr = avg > 0 ? c[i].volume / avg : 1.0;
      final up = c[i].close >= c[i].open;
      if (vr > 1.8) {
        lines.add('حجم آخر شمعة ${vr.toStringAsFixed(1)}× المتوسط — دخول سيولة كبيرة '
            '${up ? 'شرائية' : 'بيعية'}، الحركة موثوقة.');
        b = up ? 1 : -1;
      } else if (vr < 0.6) {
        lines.add('حجم آخر شمعة ضعيف (${vr.toStringAsFixed(1)}× المتوسط) — الحركة بدون مشاركة قوية، لا تثق بها كثيراً.');
      } else {
        lines.add('الحجم طبيعي (${vr.toStringAsFixed(1)}× المتوسط).');
      }
    } else {
      lines.add('لا تتوفر بيانات حجم حقيقية لهذا السوق (شائع في الفوركس).');
    }
    score += b * 0.8;
    sections.add(ReadSection('🌊', 'التقلب والحجم', lines, b));
  }

  // ───── 7) لوحة المؤشرات
  {
    final panel = buildPanel(c, at);
    final ups = <String>[], dns = <String>[], fired = <String>[];
    for (final p in panel) {
      if (p.bias[i] > 0) ups.add(p.name);
      if (p.bias[i] < 0) dns.add(p.name);
      for (var j = math.max(0, i - 2); j <= i; j++) {
        if (p.trig[j] != 0) {
          fired.add('${p.name} (${p.trig[j] > 0 ? 'شراء' : 'بيع'})');
          break;
        }
      }
    }
    final tot = ups.length + dns.length;
    final lines = <String>[
      '${ups.length} من $tot مؤشر صاعد • ${dns.length} هابط.',
      if (ups.isNotEmpty) 'الصاعدة: ${ups.join('، ')}',
      if (dns.isNotEmpty) 'الهابطة: ${dns.join('، ')}',
      if (fired.isNotEmpty) 'إشارات جديدة في آخر 3 شموع: ${fired.join('، ')}',
      if (tot > 0 && (ups.length / tot >= 0.9 || dns.length / tot >= 0.9))
        'توافق شبه كامل — غالباً الحركة متقدمة والدخول الآن متأخر.',
    ];
    final b = tot == 0 ? 0 : (ups.length > dns.length ? 1 : (dns.length > ups.length ? -1 : 0));
    score += tot == 0 ? 0 : (ups.length - dns.length) / tot * 2;
    sections.add(ReadSection('🧭', 'المؤشرات', lines, b));
  }

  // ───── الخلاصة والسيناريوهات
  final bias = score > 1.5 ? 1 : (score < -1.5 ? -1 : 0);
  final verdict = bias == 1
      ? 'المشترون يسيطرون على الشارت حالياً (${score.toStringAsFixed(1)}+).'
      : bias == -1
          ? 'البائعون يسيطرون على الشارت حالياً (${score.toStringAsFixed(1)}).'
          : 'توازن بين المشترين والبائعين (${score.toStringAsFixed(1)}) — السوق ينتظر محفزاً، والأفضل الانتظار.';
  final scen = <String>[];
  if (res.isNotEmpty) {
    final nxt = res.length > 1 ? res[1].p : res.first.p + 2 * a;
    scen.add('🟢 سيناريو الصعود: إغلاق فوق ${_f(sym, res.first.p)} (${res.first.name}) '
        '← الهدف التالي ${_f(sym, nxt)}.');
  }
  if (sup.isNotEmpty) {
    final nxt = sup.length > 1 ? sup[1].p : sup.first.p - 2 * a;
    scen.add('🔴 سيناريو الهبوط: إغلاق تحت ${_f(sym, sup.first.p)} (${sup.first.name}) '
        '← الهدف التالي ${_f(sym, nxt)}.');
  }
  scen.add(bias == 1
      ? 'الأرجح الآن: سيناريو الصعود، بشرط ألا يكسر الدعم.'
      : bias == -1
          ? 'الأرجح الآن: سيناريو الهبوط، بشرط ألا يخترق المقاومة.'
          : 'لا أرجحية واضحة — انتظر أي السيناريوهين يتحقق بإغلاق شمعة.');
  return ChartReading(sections, bias, verdict, scen);
}

/// شرح شمعة واحدة: شكلها، معناها، موقعها، وماذا حدث بعدها (إن كانت في الماضي).
List<String> explainCandle(List<Candle> c, int i, MarketSymbol sym) {
  if (i < 15 || i >= c.length) return const ['شمعة مبكرة — لا توجد شموع كافية قبلها لفهمها.'];
  final k = c[i];
  final at = atr(c.sublist(0, i + 1), 14);
  final a = at[i].isNaN ? (k.high - k.low) : at[i];
  final rng = k.high - k.low;
  final body = (k.close - k.open).abs();
  final uw = k.high - math.max(k.open, k.close);
  final lw = math.min(k.open, k.close) - k.low;
  final out = <String>[];
  final chg = k.open == 0 ? 0.0 : (k.close - k.open) / k.open * 100;
  out.add('${k.close >= k.open ? '🟢 شمعة صاعدة' : '🔴 شمعة هابطة'} ${_pct(chg)} • '
      'حجمها ${(rng / a).toStringAsFixed(1)}× المعتاد • الجسم ${rng == 0 ? 0 : (body / rng * 100).round()}% '
      '• ذيل علوي ${rng == 0 ? 0 : (uw / rng * 100).round()}% • سفلي ${rng == 0 ? 0 : (lw / rng * 100).round()}%');
  if (rng > 0) {
    if (lw > 0.55 * rng) out.add('الذيل السفلي الطويل يعني أن البائعين حاولوا ثم رُفضوا.');
    if (uw > 0.55 * rng) out.add('الذيل العلوي الطويل يعني أن المشترين حاولوا ثم رُفضوا.');
    if (body > 0.8 * rng && rng > a) out.add('جسم كبير بلا ذيول — طرف واحد سيطر بالكامل.');
  }
  final hits = detectPatterns(c.sublist(0, i + 1));
  for (final h in hits) {
    out.add('النموذج: ${h.ar} — ${patternMeaning[h.en] ?? ''}');
  }
  final cl = c.sublist(0, i + 1).map((e) => e.close).toList();
  final e20 = ema(cl, 20), e50 = ema(cl, 50);
  if (!e50[i].isNaN) {
    out.add('موقعها: ${k.close > e50[i] ? 'فوق' : 'تحت'} EMA50'
        '${(k.low <= e20[i] && k.high >= e20[i]) ? '، ولمست EMA20 (منطقة ارتداد شائعة)' : ''}.');
  }
  if (k.volume > 0 && i >= 21) {
    var avg = 0.0;
    for (var j = i - 20; j < i; j++) {
      avg += c[j].volume;
    }
    avg /= 20;
    if (avg > 0) out.add('حجمها ${(k.volume / avg).toStringAsFixed(1)}× متوسط آخر 20 شمعة.');
  }
  // ماذا حدث بعدها (للتعلم من الماضي)
  final after = c.length - 1 - i;
  if (after >= 3) {
    final h = math.min(10, after);
    var mx = -double.infinity, mn = double.infinity;
    for (var j = i + 1; j <= i + h; j++) {
      mx = math.max(mx, c[j].high);
      mn = math.min(mn, c[j].low);
    }
    final ch = (c[i + h].close - k.close) / k.close * 100;
    out.add('📚 بعدها بـ $h شموع: السعر ${ch >= 0 ? 'صعد' : 'هبط'} ${_pct(ch)} '
        '(أعلى ${_f(sym, mx)} / أدنى ${_f(sym, mn)}) — للتعلم فقط، لم يكن معروفاً وقتها.');
  } else {
    out.add('هذه من أحدث الشموع — ما بعدها لم يحدث بعد.');
  }
  return out;
}
