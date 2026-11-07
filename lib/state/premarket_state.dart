import 'package:flutter/foundation.dart';
import '../services/premarket_service.dart';
import 'app_state.dart';

class PreMarketState extends ChangeNotifier {
  final _svc = PreMarketService();

  PreMarketPlan? plan;
  bool loading = false;
  bool aiLoading = false;
  String? error;
  String session = 'NY'; // NY | LDN

  void setSession(String s, AppState app) {
    if (s == session) return;
    session = s;
    plan = null;
    notifyListeners();
    run(app);
  }

  Future<void> run(AppState app) async {
    if (loading) return;
    if (!app.settings.hasTwelve && !app.settings.hasTiingo) {
      error = 'أضف مفاتيح البيانات من الإعدادات أولاً';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final p = await _svc.build(sym: app.symbol, session: session, s: app.settings);
      plan = p;
      loading = false;
      aiLoading = true;
      notifyListeners();
      await _svc.enrich(p, app.news, app.settings);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      aiLoading = false;
      notifyListeners();
    }
  }
}
