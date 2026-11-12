import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  String tiingoKey;
  List<String> twelveKeys; // 4 fields
  List<String> geminiKeys; // 4 fields
  int refreshSec; // REST resync interval
  int pollSec; // price polling interval when no WebSocket
  double atrMult;
  double rr1, rr2, rr3; // TP1/TP2/TP3 as R multiples (QNA style 1R/2R/3R)
  int cePeriod;
  double ceMult;
  bool liveWs;
  bool useAi;
  bool metalTp07; // الذهب والمعادن: الهدف الأول 0.7R تلقائياً (الأدق بالقياس)
  double alkaTp1; // هدف Alka الأول بوحدات R (0.35 ≈ دقة 79% مع الوقف المتحرك)
  String source; // auto | twelve | tiingo
  String geminiModel;

  AppSettings({
    this.tiingoKey = '',
    List<String>? twelveKeys,
    List<String>? geminiKeys,
    this.refreshSec = 60,
    this.pollSec = 10,
    this.atrMult = 1.5,
    this.rr1 = 1.0,
    this.rr2 = 2.0,
    this.rr3 = 3.0,
    this.cePeriod = 22,
    this.ceMult = 3.0,
    this.liveWs = true,
    this.useAi = true,
    this.metalTp07 = true,
    this.alkaTp1 = 0.35,
    this.source = 'auto',
    this.geminiModel = 'gemini-2.5-flash',
  })  : twelveKeys = twelveKeys ?? List.filled(4, ''),
        geminiKeys = geminiKeys ?? List.filled(4, '');

  static List<String> _four(List<String>? l) {
    final out = List<String>.filled(4, '');
    if (l != null) {
      for (var i = 0; i < 4 && i < l.length; i++) {
        out[i] = l[i];
      }
    }
    return out;
  }

  static Future<AppSettings> load() async {
    await EngineConfig.load();
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      tiingoKey: p.getString('tiingo') ?? '',
      twelveKeys: _four(p.getStringList('twelve')),
      geminiKeys: _four(p.getStringList('gemini')),
      refreshSec: p.getInt('refreshSec') ?? 60,
      pollSec: p.getInt('pollSec') ?? 10,
      atrMult: p.getDouble('atrMult') ?? 1.5,
      rr1: p.getDouble('r1') ?? 1.0,
      rr2: p.getDouble('r2') ?? 2.0,
      rr3: p.getDouble('r3') ?? 3.0,
      cePeriod: p.getInt('cePeriod') ?? 22,
      ceMult: p.getDouble('ceMult') ?? 3.0,
      liveWs: p.getBool('liveWs') ?? true,
      useAi: p.getBool('useAi') ?? true,
      metalTp07: p.getBool('metalTp07') ?? true,
      alkaTp1: p.getDouble('alkaTp1') ?? 0.35,
      source: p.getString('source') ?? 'auto',
      geminiModel: p.getString('geminiModel') ?? 'gemini-2.5-flash',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tiingo', tiingoKey.trim());
    await p.setStringList('twelve', twelveKeys.map((e) => e.trim()).toList());
    await p.setStringList('gemini', geminiKeys.map((e) => e.trim()).toList());
    await p.setInt('refreshSec', refreshSec);
    await p.setInt('pollSec', pollSec);
    await p.setDouble('atrMult', atrMult);
    await p.setDouble('r1', rr1);
    await p.setDouble('r2', rr2);
    await p.setDouble('r3', rr3);
    await p.setInt('cePeriod', cePeriod);
    await p.setDouble('ceMult', ceMult);
    await p.setBool('liveWs', liveWs);
    await p.setBool('useAi', useAi);
    await p.setBool('metalTp07', metalTp07);
    await p.setDouble('alkaTp1', alkaTp1);
    await p.setString('source', source);
    await p.setString('geminiModel', geminiModel.trim());
  }

  /// الهدف الأول الفعلي لسوق معيّن (فئة السوق من MarketSymbol.category).
  double rr1For(String category) => metalTp07 && category == 'metal' ? 0.7 : rr1;

  bool get hasTwelve => twelveKeys.any((k) => k.trim().isNotEmpty);
  bool get hasTiingo => tiingoKey.trim().isNotEmpty;
  bool get hasGemini => geminiKeys.any((k) => k.trim().isNotEmpty);
}

/// Signal-engine tuning (kept separate so Settings saves never reset it).
/// الوضع الاحترافي (pro) هو الأساسي دايمًا في التطبيق.
class EngineConfig {
  final String mode; // 'vote' = indicator voting, 'pro' = trader-style pipeline
  final bool lean; // vote mode: fewer, non-redundant indicators
  final int minAligned; // vote mode: min aligned core confluences
  final double minScore; // vote mode: min |score|
  final bool htfGate; // vote mode: trade only with the higher-timeframe trend
  final bool prune; // vote mode: drop indicators that tested negative
  final int minLoc; // pro mode: min number of confluence factors at the zone
  final bool sessionOnly; // pro mode: FX/metals only in London/NY killzones
  const EngineConfig({
    this.mode = 'pro',
    this.lean = true,
    this.minAligned = 4,
    this.minScore = 30,
    this.htfGate = false,
    this.prune = false,
    this.minLoc = 2,
    this.sessionOnly = false,
  });

  static EngineConfig current = const EngineConfig();

  EngineConfig copy({
    String? mode,
    bool? lean,
    int? minAligned,
    double? minScore,
    bool? htfGate,
    bool? prune,
    int? minLoc,
    bool? sessionOnly,
  }) =>
      EngineConfig(
        mode: mode ?? this.mode,
        lean: lean ?? this.lean,
        minAligned: minAligned ?? this.minAligned,
        minScore: minScore ?? this.minScore,
        htfGate: htfGate ?? this.htfGate,
        prune: prune ?? this.prune,
        minLoc: minLoc ?? this.minLoc,
        sessionOnly: sessionOnly ?? this.sessionOnly,
      );

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    current = EngineConfig(
      mode: 'pro', // دايمًا احترافي، حتى لو كان محفوظ غيره
      lean: p.getBool('eng_lean') ?? true,
      minAligned: p.getInt('eng_aligned') ?? 4,
      minScore: p.getDouble('eng_score') ?? 30,
      htfGate: p.getBool('eng_gate') ?? false,
      prune: p.getBool('eng_prune') ?? false,
      minLoc: p.getInt('eng_minloc') ?? 2,
      sessionOnly: p.getBool('eng_session') ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('eng_mode', 'pro');
    await p.setBool('eng_lean', lean);
    await p.setInt('eng_aligned', minAligned);
    await p.setDouble('eng_score', minScore);
    await p.setBool('eng_gate', htfGate);
    await p.setBool('eng_prune', prune);
    await p.setInt('eng_minloc', minLoc);
    await p.setBool('eng_session', sessionOnly);
    current = copy(mode: 'pro');
  }
}

/// Round-robin key pool with a cooldown for keys that hit rate limits.
class KeyPool {
  final List<String> keys;
  int _i = 0;
  final Map<String, DateTime> _cool = {};

  KeyPool(List<String> all)
      : keys = all.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  bool get isEmpty => keys.isEmpty;

  String? next() {
    if (keys.isEmpty) return null;
    for (var n = 0; n < keys.length; n++) {
      final k = keys[_i % keys.length];
      _i++;
      final until = _cool[k];
      if (until == null || DateTime.now().isAfter(until)) return k;
    }
    return null;
  }

  void penalize(String k, [Duration d = const Duration(seconds: 60)]) {
    _cool[k] = DateTime.now().add(d);
  }
} 
