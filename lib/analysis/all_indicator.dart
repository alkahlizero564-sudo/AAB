import '../models.dart';
import 'forecast.dart';
import 'indicators.dart';
import 'market_state.dart';

/// مؤشر ALL: يجمع إشارات AAB و Alka، ويقبل فقط إشارات "الشمعة الصغيرة"
/// (مدى شمعة الإشارة ≤ 0.94 × ATR)، مع صفقة واحدة في كل مرة.
/// مقاس على 25 سوقاً حقيقياً: الدقة بهدف 1R من 54.5% إلى 57.2% (نفس الرقم في القديم والجديد)،
/// وبهدف 0.35R مع الوقف المتحرك 81% — والأدق والأربح لكل صفقة على الذهب والبيتكوين.
class AllResult {
  final List<PastSignal> signals;
  final List<String> sources; // مصدر كل إشارة: 'AAB' أو 'Alka' أو '0.1'
  final List<PendingSetup> pending;
  final List<String> pendingSrc;
  final String tag; // اسم المؤشر في النصوص: 'ALL' أو 'Mp'
  const AllResult(this.signals, this.sources, this.pending, this.pendingSrc, [this.tag = 'ALL']);
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
              ? '$tag $side مفتوح — تحقق TP1: أغلق النصف، والوقف المتحرك الآن عند هذا السعر'
              : '$tag $side — صفقة مفتوحة',
          'من ${sources.last}: ${sg.why}', (sg.entry - sg.sl).abs());
    }
    if (pending.isNotEmpty) {
      final p = pending.first;
      return Decision(2, p.dir, p.trigger, p.sl, p.tp1, p.tp2,
          '$tag ${p.dir > 0 ? 'شراء' : 'بيع'} ينتظر التأكيد — ادخل عند ${p.dir > 0 ? 'اختراق' : 'كسر'} السعر المحدد خلال 3 شموع، وألغِ لو انكسر الطرف الآخر',
          'من ${pendingSrc.first}: ${p.cond}', (p.trigger - p.sl).abs());
    }
    return Decision(0, 0, double.nan, double.nan, double.nan, double.nan, '$tag: لا توجد إشارة', '');
  }
}

/// يدمج إشارات AAB و Alka (المحسوبة مسبقاً بنفس الإدارة) في مؤشر ALL.
/// مع [zero] (إشارات 0.1، بدون فلتر الشمعة الصغيرة ولها الأولوية) يصبح مؤشر Mp.
AllResult combineAll(List<Candle> c, List<PastSignal> aab, List<PendingSetup> aabPending,
    List<PastSignal> alka, List<PendingSetup> alkaPending,
    {double maxCandle = 0.94,
    List<PastSignal> zero = const [],
    List<PendingSetup> zeroPending = const [],
    String tag = 'ALL',
    double maxVol = double.infinity}) {
  final n = c.length;
  if (n < 20) return AllResult.empty;
  final at = atr(c, 14);
  // Mp الذكي: لا إشارات في السوق العاصف (تذبذب ≥ maxVol × المعتاد)
  final vr = maxVol.isFinite ? volRatios(c) : const <double>[];
  bool calm(int i) => !maxVol.isFinite || i < 0 || i >= n || vr[i].isNaN || vr[i] < maxVol;
  bool small(int i) {
    if (i < 0 || i >= n) return false;
    final a = at[i].isNaN ? (c[i].high - c[i].low) : at[i];
    return a > 0 && (c[i].high - c[i].low) / a <= maxCandle;
  }

  const prio = {'0.1': 0, 'AAB': 1, 'Alka': 2};
  final cands = <(PastSignal, String)>[
    for (final s in zero)
      if (calm(s.i)) (s, '0.1'),
    for (final s in aab)
      if (small(s.i) && calm(s.i)) (s, 'AAB'),
    for (final s in alka)
      if (small(s.i) && calm(s.i)) (s, 'Alka'),
  ]..sort((x, y) => x.$1.i != y.$1.i ? x.$1.i.compareTo(y.$1.i) : prio[x.$2]!.compareTo(prio[y.$2]!));
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
    for (final (l, from) in [(zeroPending, '0.1'), (aabPending, 'AAB'), (alkaPending, 'Alka')]) {
      for (final p in l) {
        if (pend.isEmpty && (from == '0.1' || small(p.i)) && calm(p.i) && p.i > busy) {
          pend.add(p);
          pendSrc.add(from);
        }
      }
    }
  }
  return AllResult(sigs, src, pend, pendSrc, tag);
}
