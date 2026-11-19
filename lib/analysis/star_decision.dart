import '../models.dart';
import 'health.dart';
import 'indicators.dart';
import 'star_indicator.dart';
import 'trade_check.dart';

/// قرار مؤشر النجوم بعد تحليل السوق الحالي. كل جزء مبني على ما ثبت في الاختبارات:
///  - صحة المؤشر على هذا السوق والفريم (آخر 5000 شمعة)
///  - إشارة النجوم الحالية وعدد نجومها (0★ ~54% ، 1★ ~56% ، 2★ ~59% ، 3★ ~64% بهدف 1R — ذهب 2021-2026)
///  - حالة الصفقة المفتوحة (زخم قوي / عادي / يضعف)
///  - السياق: اتجاهات 1H/4H/1D وهدوء السوق (معلومة مساعدة، أثرها صغير)
class StarDecision {
  final String action; // enter | ready | hold | secure | wait | avoid
  final String title;
  final int dir; // +1 شراء ، -1 بيع ، 0
  final int stars;
  final List<(int, String)> reasons; // (+1 إيجابي ، -1 سلبي ، 0 معلومة ، النص)
  final String plan; // ماذا تفعل الآن
  const StarDecision(this.action, this.title, this.dir, this.stars, this.reasons, this.plan);
}

const _acc = {0: 54, 1: 56, 2: 59, 3: 64};

StarDecision decideStars(List<Candle> c, StarResult sr, MarketSymbol sym,
    {IndHealth? health, Map<String, int> board = const {}}) {
  final n = c.length;
  final reasons = <(int, String)>[];
  String f(double v) => sym.fmt(v);

  // ── السياق
  if (n > 120) {
    final at = atr(c, 14);
    final am = sma(at.map((v) => v.isNaN ? 0.0 : v).toList(), 100);
    final i = n - 2;
    if (!at[i].isNaN && am[i] > 0) {
      final r = at[i] / am[i];
      reasons.add((0, r < 0.9 ? 'السوق هادئ الآن (التذبذب أقل من المعتاد) — الإشارات فيه أدق' : r > 1.5 ? 'السوق عنيف الآن (التذبذب أعلى من المعتاد بكثير)' : 'تذبذب السوق طبيعي'));
    }
  }
  final weak = health != null && health.light == 'red';
  if (health != null && health.trades >= 20) {
    reasons.add((
      health.light == 'green' ? 1 : (weak ? -1 : 0),
      'أداء الإشارات على هذا السوق والفريم مؤخراً: ${(health.winRate * 100).toStringAsFixed(0)}% من ${health.trades} صفقة (${health.label})'
    ));
  }

  // ── صفقة مفتوحة؟
  final r = sr.res;
  final oi = r.signals.lastIndexWhere((x) => x.exitI < 0);
  if (oi >= 0) {
    final s = r.signals[oi];
    final g = sr.of(s.i, s.dir);
    final tc = checkTrade(c, s);
    final side = s.dir > 0 ? 'شراء' : 'بيع';
    _trend(board, s.dir, reasons);
    if (tc == null) {
      return StarDecision('hold', 'صفقة $side مفتوحة', s.dir, g, reasons, 'التزم بالوقف والأهداف الظاهرة على الشارت.');
    }
    for (final (pos, t) in tc.reasons) {
      reasons.add((pos ? 1 : -1, t));
    }
    final secured = '${tc.securedR >= 0 ? '+' : ''}${tc.securedR.toStringAsFixed(2)}R';
    switch (tc.state) {
      case 'early':
        return StarDecision('hold', 'صفقة $side مفتوحة — قبل TP1', s.dir, g, reasons,
            'الوقف عند ${f(s.sl)} ، TP1 عند ${f(s.tp1)}. عند TP1 أغلق النصف وانقل الوقف لسعر الدخول.');
      case 'strong':
        return StarDecision('hold', '🟢 احتفظ — زخم قوي في اتجاه صفقة $side', s.dir, g, reasons,
            'خلّها تجري مع الوقف المتحرك. المضمون الآن $secured.');
      case 'weak':
        return StarDecision('secure', '🔴 الحركة تضعف — فكّر في تأمين الربح', s.dir, g, reasons,
            'المضمون الآن $secured. الوقف المتحرك يحميك، ويمكنك الإغلاق يدوياً لتأمين الربح.');
      default:
        return StarDecision('hold', '🟡 احتفظ — صفقة $side عادية', s.dir, g, reasons,
            'اترك الوقف المتحرك يعمل. المضمون الآن $secured.');
    }
  }

  // ── إشارة تنتظر التأكيد؟
  if (r.pending.isNotEmpty) {
    final p = r.pending.first;
    final g = sr.of(p.i, p.dir);
    final side = p.dir > 0 ? 'شراء' : 'بيع';
    _trend(board, p.dir, reasons);
    reasons.add((g >= 2 ? 1 : 0, 'الإشارة بـ $g نجوم — دقتها التاريخية ≈ ${_acc[g]}% بهدف 1R'));
    if (weak) {
      return StarDecision('avoid', '⚠️ إشارة $side لكن المؤشر ضعيف على هذا السوق الآن', p.dir, g, reasons,
          'الأفضل تجنّبها أو تقليل الحجم كثيراً، أو جرّب فريماً آخر حالته خضراء.');
    }
    return StarDecision('ready', '⏳ استعد: $side ${'★' * g}${'☆' * (3 - g)}', p.dir, g, reasons,
        'ادخل $side إذا ${p.dir > 0 ? 'اخترق السعر' : 'كسر السعر'} ${f(p.trigger)} خلال 3 شموع. الوقف ${f(p.sl)} ، TP1 ${f(p.tp1)} ، TP2 ${f(p.tp2)}.\n'
        'الحجم المقترح: ${g >= 3 ? '1%' : g >= 1 ? '0.75%' : '0.5%'} من الحساب.');
  }

  // ── لا إشارة
  if (weak) {
    return StarDecision('avoid', '🔴 لا تتداول هذا الفريم الآن', 0, 0, reasons,
        'أداء الإشارات ضعيف مؤخراً على هذا السوق والفريم. جرّب فريماً آخر لمبته خضراء، أو انتظر.');
  }
  return StarDecision('wait', '⏸ انتظر — لا توجد إشارة الآن', 0, 0, reasons,
      'لا تدخل بدون إشارة. أفضل الفرص: إشارة بنجمتين أو 3 في اتجاه الفريمات الكبيرة.');
}

void _trend(Map<String, int> board, int dir, List<(int, String)> reasons) {
  if (board.isEmpty) return;
  final w = board.entries.where((e) => e.value == dir).map((e) => e.key.toUpperCase()).toList();
  final a = board.entries.where((e) => e.value == -dir).map((e) => e.key.toUpperCase()).toList();
  if (w.isNotEmpty) reasons.add((1, 'الاتجاه مع الصفقة في: ${w.join('، ')}'));
  if (a.isNotEmpty) reasons.add((-1, 'الاتجاه ضد الصفقة في: ${a.join('، ')}'));
}
