import '../models.dart';
import 'all_indicator.dart';
import 'forecast.dart';

/// ذاكرة الإشارات: أي صفقة ظهرت على شمعة مغلقة تبقى على الشارت ولا تختفي عند إعادة الحساب
/// (تحديث بيانات الخادم يصحّح شموعاً بُنيت من التيك، أو انزلاق نافذة الشموع، أو تحرّك درجة الذكاء حول الحد).
/// الإشارة المحفوظة تُعاد بنفس مستوياتها (الدخول، الوقف، الأهداف)، ونتيجتها تُحسب من الشموع الحالية.
class SignalMemory {
  final Map<String, Map<String, (PastSignal, String, int)>> _m = {}; // مؤشر → (وقت|اتجاه) → (الإشارة، المصدر، وقت الشمعة)
  // بوابة الوقت: الإشارة التي لم تظهر خلال شمعة من إغلاق شمعتها لا تُعرض أبداً
  // (تظهر أحياناً على شمعة قديمة لأن نافذة الشموع تحركت وتغيّرت المتوسطات الطويلة في أولها).
  final Map<String, int> _t0 = {}, _prev = {}; // مؤشر → آخر شمعة مغلقة عند أول تحليل / عند التحليل السابق
  final Map<String, Map<String, bool>> _ok = {}; // مؤشر → (وقت|اتجاه) → مسموحة؟ (يُقرر مرة واحدة)
  void clear() {
    _m.clear();
    _t0.clear();
    _prev.clear();
    _ok.clear();
  }

  /// يحذف الإشارات المتأخرة: المسموح = ما كان على الشارت عند فتحه، أو ما ظهر قبل إغلاق الشمعة التي تليه.
  List<PastSignal> gate(String name, List<Candle> c, List<PastSignal> sigs) {
    final n = c.length;
    if (n < 3) return sigs;
    final last = c[n - 2].time.millisecondsSinceEpoch;
    final t0 = _t0.putIfAbsent(name, () => last);
    final prev = _prev[name] ?? last;
    final ok = _ok.putIfAbsent(name, () => {});
    var drop = false;
    final keep = <bool>[];
    for (final s in sigs) {
      if (s.i < 0 || s.i >= n) {
        keep.add(true);
        continue;
      }
      final t = c[s.i].time.millisecondsSinceEpoch;
      final v = ok.putIfAbsent('$t|${s.dir}', () => t <= t0 || t >= prev);
      keep.add(v);
      if (!v) drop = true;
    }
    _prev[name] = last;
    if (ok.length > 3000) ok.removeWhere((k, _) => int.parse(k.split('|').first) < c.first.time.millisecondsSinceEpoch);
    if (!drop) return sigs;
    return [for (final (q, s) in sigs.indexed) if (keep[q]) s];
  }

  AllResult gateAll(String name, List<Candle> c, AllResult r) {
    final g = gate(name, c, r.signals);
    if (identical(g, r.signals)) return r;
    final keepSet = {for (final s in g) (s.i, s.dir)};
    final src = [for (final (q, s) in r.signals.indexed) if (keepSet.contains((s.i, s.dir))) q < r.sources.length ? r.sources[q] : ''];
    return AllResult(g, src, r.pending, r.pendingSrc, r.tag, r.extra);
  }

  static int _find(List<Candle> c, int t) {
    var lo = 0, hi = c.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = c[mid].time.millisecondsSinceEpoch;
      if (v == t) return mid;
      if (v < t) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  /// نتيجة صفقة محفوظة على الشموع الحالية: الوقف، أو TP1 (والوقف للدخول) ثم TP2.
  static PastSignal _resim(List<Candle> c, int i, PastSignal s) {
    final d = s.dir;
    var stop = s.sl, got = false;
    for (var j = i + 1; j < c.length; j++) {
      final k = c[j];
      if (d > 0 ? k.low <= stop : k.high >= stop) {
        return PastSignal(i, d, s.entry, s.sl, s.tp1, s.tp2, got ? 1 : -1, j, s.why, s.strong, s.agree, s.total, stop);
      }
      if (!got && (d > 0 ? k.high >= s.tp1 : k.low <= s.tp1)) {
        got = true;
        stop = s.entry;
      }
      if (got && (d > 0 ? k.high >= s.tp2 : k.low <= s.tp2)) {
        return PastSignal(i, d, s.entry, s.sl, s.tp1, s.tp2, 2, j, s.why, s.strong, s.agree, s.total, s.tp2);
      }
    }
    return PastSignal(i, d, s.entry, s.sl, s.tp1, s.tp2, got ? 1 : 0, -1, s.why, s.strong, s.agree, s.total, double.nan, stop);
  }

  /// يُرجع [sigs] مع الإشارات المحفوظة التي اختفت (آخر [window] شمعة فقط).
  (List<PastSignal>, List<String>) _hold(String name, List<Candle> c, List<PastSignal> sigs0, List<String> src0, int window) {
    final n = c.length;
    if (n < 3) return (sigs0, src0);
    final sigs = gate(name, c, sigs0);
    final kept = identical(sigs, sigs0) ? null : {for (final s in sigs) (s.i, s.dir)};
    final src = kept == null || src0.isEmpty ? src0 : [for (final (q, s) in sigs0.indexed) if (kept.contains((s.i, s.dir))) q < src0.length ? src0[q] : ''];
    final mem = _m.putIfAbsent(name, () => {});
    final cur = <String>{};
    for (final (q, s) in sigs.indexed) {
      if (s.i < 0 || s.i >= n - 1) continue;
      final t = c[s.i].time.millisecondsSinceEpoch;
      final k = '$t|${s.dir}';
      cur.add(k);
      mem[k] = (s, q < src.length ? src[q] : '', t);
    }
    final add = <(PastSignal, String)>[];
    final minT = c[n - 1 - window < 0 ? 0 : n - 1 - window].time.millisecondsSinceEpoch;
    mem.removeWhere((k, v) => v.$3 < minT);
    for (final e in mem.entries) {
      if (cur.contains(e.key)) continue;
      final idx = _find(c, e.value.$3);
      if (idx < 0 || idx >= n - 1) continue;
      add.add((_resim(c, idx, e.value.$1), e.value.$2));
    }
    if (add.isEmpty) return (sigs, src);
    final all = <(PastSignal, String)>[
      for (final (q, s) in sigs.indexed) (s, q < src.length ? src[q] : ''),
      ...add,
    ]..sort((a, b) => a.$1.i.compareTo(b.$1.i));
    return ([for (final x in all) x.$1], [for (final x in all) x.$2]);
  }

  AllResult hold(String name, List<Candle> c, AllResult r, {int window = 200}) {
    final (s, src) = _hold(name, c, r.signals, r.sources, window);
    if (identical(s, r.signals)) return r;
    final open = {for (final x in s) if (x.exitI < 0) x.dir};
    final keep = [for (var q = 0; q < r.pending.length; q++) if (!open.contains(r.pending[q].dir)) q];
    return AllResult(s, src, [for (final q in keep) r.pending[q]], [for (final q in keep) r.pendingSrc[q]], r.tag, r.extra);
  }

  /// للمؤشرات ذات القائمة البسيطة (Alka و 0.1): الإشارات + الانتظار بعد حذف المتعارض مع صفقة مفتوحة.
  (List<PastSignal>, List<PendingSetup>) holdList(String name, List<Candle> c, List<PastSignal> sigs, List<PendingSetup> pend,
      {int window = 200}) {
    final (s, _) = _hold(name, c, sigs, const [], window);
    if (identical(s, sigs)) return (sigs, pend);
    final open = {for (final x in s) if (x.exitI < 0) x.dir};
    return (s, [for (final p in pend) if (!open.contains(p.dir)) p]);
  }

  Forecast holdForecast(String name, List<Candle> c, Forecast f, {int window = 200}) {
    final (s, _) = _hold(name, c, f.signals, const [], window);
    if (identical(s, f.signals)) return f;
    final open = {for (final x in s) if (x.exitI < 0) x.dir};
    return Forecast(
      patterns: f.patterns,
      signals: s,
      predHits: f.predHits,
      predN: f.predN,
      predOk: f.predOk,
      next: f.next,
      pending: [for (final p in f.pending) if (!open.contains(p.dir)) p],
      ema20: f.ema20,
      ema50: f.ema50,
      ema200: f.ema200,
      liveSignal: f.liveSignal,
      indicators: f.indicators,
      liveDir: f.liveDir,
    );
  }
}
