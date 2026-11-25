import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../analysis/scan.dart';
import '../data/symbols.dart';
import '../models.dart';
import 'market_data_service.dart';
import 'settings_service.dart';

/// تنبيهات والتطبيق مقفول: كل 15 دقيقة (أقل مدة يسمح بها أندرويد) يفحص المفضلة على الفريمات المختارة،
/// وينبّه بأي إشارة جديدة من AK أو King أو النجوم.
class AlertService {
  static const _task = 'aab-scan';
  static const kOn = 'alerts_on', kTfs = 'alerts_tfs', kSent = 'alerts_sent';
  static final _n = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> _initPlugin() async {
    if (_ready) return;
    await _n.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/launcher_icon')));
    _ready = true;
  }

  /// يُستدعى عند فتح التطبيق: يجهّز الإشعارات ويعيد تسجيل الفحص الدوري إن كان مفعّلاً.
  static Future<void> boot() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _initPlugin();
      await Workmanager().initialize(alertDispatcher);
      final p = await SharedPreferences.getInstance();
      if (p.getBool(kOn) ?? false) await _register();
    } catch (_) {}
  }

  static Future<bool> isOn() async => (await SharedPreferences.getInstance()).getBool(kOn) ?? false;
  static Future<List<String>> tfs() async => (await SharedPreferences.getInstance()).getStringList(kTfs) ?? const ['15m', '1h'];

  static Future<void> setTfs(List<String> t) async => (await SharedPreferences.getInstance()).setStringList(kTfs, t);

  /// تفعيل/إيقاف. يرجع false لو رفض المستخدم إذن الإشعارات.
  static Future<bool> setOn(bool on) async {
    final p = await SharedPreferences.getInstance();
    if (!on) {
      await p.setBool(kOn, false);
      try {
        await Workmanager().cancelByUniqueName(_task);
      } catch (_) {}
      return true;
    }
    await _initPlugin();
    final ok = await _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? true;
    if (!ok) return false;
    await p.setBool(kOn, true);
    await _register();
    return true;
  }

  static Future<void> _register() => Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );

  /// تنبيه تجريبي من الإعدادات.
  static Future<void> test() async {
    await _initPlugin();
    await _show(1, 'تنبيهات AAB تعمل ✅', 'سيصلك تنبيه عند أي إشارة جديدة من AK أو King أو النجوم في المفضلة.');
  }

  static Future<void> _show(int id, String title, String body) => _n.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails('aab_signals', 'إشارات AAB',
              channelDescription: 'إشارات شراء وبيع قوية', importance: Importance.high, priority: Priority.high),
        ),
      );

  /// الفحص نفسه (يعمل في الخلفية). يرجع عدد التنبيهات المرسلة.
  static Future<int> runScan() async {
    await _initPlugin();
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(kOn) ?? false)) return 0;
    final s = await AppSettings.load();
    final favs = p.getStringList('favs') ?? const [];
    final syms = [for (final x in allSymbols) if (favs.contains(x.code)) x];
    if (syms.isEmpty) syms.add(symbolByCode('XAU/USD'));
    final tfl = p.getStringList(kTfs) ?? const ['15m', '1h'];
    final sent = (p.getStringList(kSent) ?? <String>[]).toList();
    final md = MarketDataService();
    var count = 0;
    var lastApi = DateTime.fromMillisecondsSinceEpoch(0);
    for (final sym in syms.take(8)) {
      for (final tf in tfl) {
        try {
          if (!sym.isCrypto) {
            final wait = const Duration(seconds: 8) - DateTime.now().difference(lastApi);
            if (wait > Duration.zero) await Future.delayed(wait);
            lastApi = DateTime.now();
          }
          final List<Candle> c = await md.fetch(sym, tf, s, count: 500);
          final hits = scanCandles(c, sym, rr1: s.rr1For(sym.category), rr2: s.rr2, alkaTp1: s.alkaTp1, maxAge: tf == '5m' ? 3 : 1);
          for (final h in hits) {
            final key = '${sym.code}|$tf|${h.key}';
            if (sent.contains(key)) continue;
            sent.add(key);
            final side = h.dir > 0 ? 'شراء 🟢' : 'بيع 🔴';
            await _show(key.hashCode & 0x7fffffff, '${h.ind}: $side ${sym.code} • ${tf.toUpperCase()}',
                'دخول ${sym.fmt(h.entry)} • وقف ${sym.fmt(h.sl)} • هدف ${sym.fmt(h.tp1)} (دقة ~${(scanAcc[h.ind] ?? 0).toStringAsFixed(0)}%)');
            count++;
          }
        } catch (_) {}
      }
    }
    while (sent.length > 300) {
      sent.removeAt(0);
    }
    await p.setStringList(kSent, sent);
    return count;
  }
}

@pragma('vm:entry-point')
void alertDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await AlertService.runScan();
    } catch (_) {}
    return true;
  });
}
