import '../models.dart';
import 'forecast.dart';
import 'indicators.dart';

/// مؤشر ALL: يجمع إشارات AAB و Alka، ويقبل فقط إشارات "الشمعة الصغيرة"
/// (مدى شمعة الإشارة ≤ 0.94 × ATR)، مع صفقة واحدة في كل مرة.
/// مقاس على 25 سوقاً حقيقياً: الدقة بهدف 1R من 54.5% إلى 57.2% (نفس الرقم في القديم والجديد)،
/// وبهدف 0.35R مع الوقف المتحرك 81% — والأدق والأربح لكل صفقة على الذهب والبيتكوين.
class AllResult {
  final List<PastSignal> signals;
  final List<String> sources; // مصدر كل إشارة: 'AAB' أو 'Alka'
  final List<PendingSetup> pending;
  final List<String> pendingSrc;
  const AllResult(this.signals, this.sources, this.pending, this.pendingSrc);
  static const empty = AllResult([], [], [], []);

  int get wins => signals.where((s) => s.result > 0).length;
  int get losses => signals.where((s) => s.result < 0).length;
  int get closed => wins + losses;
  double get winRate => closed == 0 ? 0 : wins / closed;

  /// القرار الموحّد: 1 صفقة مفتوحة ، 2 تنتظر التأكيد ، 0 لا شيء.
  Decision get decision {
    if (signals.isNotEmpty && signals.last.exitI < 0) {
      final sg = signals.last;
      final side = sg.dir > 0 ? 'شراء' : 'بيع';
      final st = sg.curStop.isNaN ? (sg.result >= 1 ? sg.entry : sg.sl) : sg.curStop;
      return Decision(1, sg.dir, sg.entry, st, sg.tp1, sg.tp2,
          sg.result >= 1
              ? 'ALL $side مفتوح — تحقق TP1: أغلق النصف، والوقف المتحرك الآن عند هذا السعر'
              : 'ALL $side — صفقة مفتوحة',
          'من ${sources.last}: ${sg.why}', (sg.entry - sg.sl).abs());
    }
    if (pending.isNotEmpty) {
      final p = pending.first;
      return Decision(2, p.dir, p.trigger, p.sl, p.tp1, p.tp2,
          'ALL ${p.dir > 0 ? 'شراء' : 'بيع'} ينتظر التأكيد — ادخل عند ${p.dir > 0 ? 'اختراق' : 'كسر'} السعر المحدد خلال 3 شموع، وألغِ لو انكسر الطرف الآخر',
          'من ${pendingSrc.first}: ${p.cond}', (p.trigger - p.sl).abs());
    }
    return const Decision(0, 0, double.nan, double.nan, double.nan, double.nan, 'ALL: لا توجد إشارة', '');
  }
}

/// يدمج إشارات AAB و Alka (المحسوبة مسبقاً بنفس الإدارة) في مؤشر ALL.
AllResult combineAll(List<Candle> c, List<PastSignal> aab, List<PendingSetup> aabPending,
    List<PastSignal> alka, List<PendingSetup> alkaPending, {double maxCandle = 0.94}) {
  final n = c.length;
  if (n < 20) return AllResult.empty;
  final at = atr(c, 14);
  bool small(int i) {
    if (i < 0 || i >= n) return false;
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    return a > 0 && (c[i].high - c[i].low) / a <= maxCandle;
  }

  final cands = <(PastSignal, String)>[
    for (final s in aab)
      if (small(s.i)) (s, 'AAB'),
    for (final s in alka)
      if (small(s.i)) (s, 'Alka'),
  ]..sort((x, y) => x.$1.i != y.$1.i ? x.$1.i.compareTo(y.$1.i) : (x.$2 == 'AAB' ? -1 : 1));
  final sigs = <PastSignal>[], src = <String>[];
  var busy = -1;
  for (final (s, from) in cands) {
    if (s.i <= busy) continue;
    sigs.add(s);
    src.add(from);
    busy = s.exitI < 0 ? n : s.exitI;
  }
  final pend = <PendingSetup>[], pendSrc = <String>[];
  if (busy < n) {
    for (final (l, from) in [(aabPending, 'AAB'), (alkaPending, 'Alka')]) {
      for (final p in l) {
        if (pend.isEmpty && small(p.i) && p.i > busy) {
          pend.add(p);
          pendSrc.add(from);
        }
      }
    }
  }
  return AllResult(sigs, src, pend, pendSrc);
}
