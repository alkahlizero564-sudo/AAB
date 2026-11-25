import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../services/alert_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController tiingo;
  late final List<TextEditingController> twelve;
  late final List<TextEditingController> gemini;
  late final TextEditingController model;
  late int refresh;
  late double atrMult, rr1, rr2, rr3, ceMult;
  late int cePeriod, pollSec;
  late bool useAi, liveWs, metalTp07;
  late double alkaTp1;
  late bool autoHideWeak;
  late String source;

  bool _synced = false;
  // المفاتيح التي طلب المستخدم حذفها صراحةً (زر الحذف) — غير ذلك لا يُحذف أي مفتاح
  final _deleted = <String>{};

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    tiingo = TextEditingController();
    twelve = [for (var i = 0; i < 4; i++) TextEditingController()];
    gemini = [for (var i = 0; i < 4; i++) TextEditingController()];
    model = TextEditingController();
    _syncFrom(st.settings);
    _synced = st.settingsLoaded;
  }

  /// يملأ الحقول من الإعدادات المحفوظة
  void _syncFrom(AppSettings s) {
    tiingo.text = s.tiingoKey;
    for (var i = 0; i < 4; i++) {
      twelve[i].text = s.twelveKeys[i];
      gemini[i].text = s.geminiKeys[i];
    }
    model.text = s.geminiModel;
    refresh = s.refreshSec.clamp(15, 120).toInt();
    atrMult = s.atrMult;
    rr1 = s.rr1;
    rr2 = s.rr2;
    rr3 = s.rr3;
    ceMult = s.ceMult;
    cePeriod = s.cePeriod;
    pollSec = s.pollSec.clamp(3, 60).toInt();
    liveWs = s.liveWs;
    useAi = s.useAi;
    metalTp07 = s.metalTp07;
    alkaTp1 = s.alkaTp1;
    autoHideWeak = s.autoHideWeak;
    source = s.source;
  }

  @override
  void dispose() {
    tiingo.dispose();
    model.dispose();
    for (final c in [...twelve, ...gemini]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final st = context.read<AppState>();
    if (!st.settingsLoaded) return; // لا نحفظ قبل قراءة المفاتيح المحفوظة
    final old = st.settings;
    // حقل فارغ لا يحذف مفتاحاً محفوظاً — الحذف فقط بزر الحذف 🗑️
    String keep(String id, String now, String before) =>
        now.trim().isEmpty && !_deleted.contains(id) ? before : now;
    final s = AppSettings(
      tiingoKey: keep('tiingo', tiingo.text, old.tiingoKey),
      twelveKeys: [for (var i = 0; i < 4; i++) keep('twelve$i', twelve[i].text, old.twelveKeys[i])],
      geminiKeys: [for (var i = 0; i < 4; i++) keep('gemini$i', gemini[i].text, old.geminiKeys[i])],
      refreshSec: refresh,
      atrMult: atrMult,
      rr1: rr1,
      rr2: rr2,
      rr3: rr3,
      ceMult: ceMult,
      cePeriod: cePeriod,
      pollSec: pollSec,
      liveWs: liveWs,
      useAi: useAi,
      metalTp07: metalTp07,
      alkaTp1: alkaTp1,
      autoHideWeak: autoHideWeak,
      extraSameDir: old.extraSameDir,
      source: source,
      geminiModel: model.text.trim().isEmpty ? 'gemini-2.5-flash' : model.text,
    );
    await context.read<AppState>().saveSettings(s);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الإعدادات')),
    );
    context.read<AppState>().setTab(0);
  }

  Widget _slider(String label, double v, double min, double max, int div,
      String Function(double) fmt, ValueChanged<double> on) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(7)),
            child: Text(fmt(v), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.gold,
            inactiveTrackColor: AppColors.border,
            thumbColor: AppColors.gold,
            overlayColor: AppColors.gold.withOpacity(0.15),
            trackHeight: 3,
          ),
          child: Slider(value: v.clamp(min, max).toDouble(), min: min, max: max, divisions: div, onChanged: on),
        ),
      ]),
    );
  }

  Widget _switch(String title, String? sub, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeColor: AppColors.onAccent,
        activeTrackColor: AppColors.gold,
        title: Text(title, style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w600)),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
        value: v,
        onChanged: on,
      );

  Widget _section(IconData icon, String title, String sub, List<Widget> kids, {bool open = false}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: open,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            iconColor: AppColors.gold,
            collapsedIconColor: AppColors.muted,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.gold, size: 19),
            ),
            title: Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: Text(sub,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: kids,
          ),
        ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    if (!_synced && st.settingsLoaded) {
      _synced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _syncFrom(st.settings));
      });
    }
    final tw = twelve.where((c) => c.text.trim().isNotEmpty).length;
    final gm = gemini.where((c) => c.text.trim().isNotEmpty).length;
    final hasTi = tiingo.text.trim().isNotEmpty;
    final live = st.liveStatus == 'live';
    Widget stat(String k, String v, bool ok) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: (ok ? AppColors.up : AppColors.muted).withOpacity(0.10),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: (ok ? AppColors.up : AppColors.border).withOpacity(0.6), width: 0.8),
            ),
            child: Column(children: [
              Text(v, style: TextStyle(color: ok ? AppColors.up : AppColors.muted, fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 2),
              Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
            ]),
          ),
        );
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
        // بطاقة الحالة
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(colors: [Color(0xFF1C1912), AppColors.card], begin: Alignment.topRight, end: Alignment.bottomLeft),
            border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 0.8),
          ),
          child: Column(children: [
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: live ? AppColors.up : AppColors.gold,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: (live ? AppColors.up : AppColors.gold).withOpacity(0.6), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 8),
              Text(live ? 'متصل لحظياً' : (st.liveStatus == 'poll' ? 'تحديث دوري' : 'غير متصل لحظياً'),
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(width: 6),
              if (st.liveSource.isNotEmpty)
                Text('• ${st.liveSource}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const Spacer(),
              const Icon(Icons.settings_rounded, color: AppColors.gold, size: 20),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              stat('Tiingo', hasTi ? '✓' : '—', hasTi),
              stat('Twelve Data', '$tw/4', tw > 0),
              stat('Gemini', '$gm/4', gm > 0),
            ]),
          ]),
        ),
        const _AlertsSection(),
        _section(Icons.vpn_key_rounded, 'مفاتيح البيانات', 'Tiingo ${hasTi ? '✓' : '—'} • Twelve Data $tw/4', [
          const Text('Tiingo: فوركس وذهب. Twelve Data: فوركس وذهب وأسهم — أضف حتى 4 مفاتيح ويتم التبديل بينها تلقائياً.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 10),
          KeyField(controller: tiingo, label: 'Tiingo API Key', onDelete: () => _deleted.add('tiingo')),
          const SizedBox(height: 10),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KeyField(controller: twelve[i], label: 'Twelve Data ${i + 1}', onDelete: () => _deleted.add('twelve$i')),
            ),
        ], open: !hasTi && tw == 0),
        _section(Icons.auto_awesome_rounded, 'مراجعة Gemini', useAi ? 'مفعّلة • $gm مفاتيح' : 'مطفأة', [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KeyField(controller: gemini[i], label: 'Gemini ${i + 1}', onDelete: () => _deleted.add('gemini$i')),
            ),
          TextField(controller: model, decoration: const InputDecoration(labelText: 'اسم نموذج Gemini', isDense: true)),
          _switch('مراجعة الإشارات بواسطة Gemini', null, useAi, (v) => setState(() => useAi = v)),
        ]),
        _section(Icons.wifi_tethering_rounded, 'البيانات والتحديث',
            '${source == 'auto' ? 'تلقائي' : source == 'twelve' ? 'Twelve Data' : 'Tiingo'} • ${liveWs ? 'بث لحظي' : 'بدون بث'} • كل $refresh ث', [
          Row(children: [
            const Text('مصدر البيانات', style: TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w600)),
            const Spacer(),
            DropdownButton<String>(
              value: source,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.card,
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('تلقائي')),
                DropdownMenuItem(value: 'twelve', child: Text('Twelve Data')),
                DropdownMenuItem(value: 'tiingo', child: Text('Tiingo')),
              ],
              onChanged: (v) => setState(() => source = v ?? 'auto'),
            ),
          ]),
          _switch('بث لحظي (ثانية بثانية)', null, liveWs, (v) => setState(() => liveWs = v)),
          _slider('تحديث الشموع من الخادم كل', refresh.toDouble(), 15, 120, 21, (v) => '${v.round()} ث',
              (v) => setState(() => refresh = v.round())),
          _slider('فاصل جلب السعر (عند غياب البث)', pollSec.toDouble(), 3, 60, 19, (v) => '${v.round()} ث',
              (v) => setState(() => pollSec = v.round())),
        ]),
        _section(Icons.flag_rounded, 'الأهداف والوقف',
            'الهدف 1: ${rr1.toStringAsFixed(1)}R • الهدف 2: ${rr2.toStringAsFixed(1)}R • ATR ×${atrMult.toStringAsFixed(1)}', [
          _slider('مضاعف ATR لوقف الخسارة', atrMult, 1, 3, 20, (v) => v.toStringAsFixed(1), (v) => setState(() => atrMult = v)),
          _slider('الهدف 1 (R)', rr1, 0.5, 3, 25, (v) => '${v.toStringAsFixed(1)}R', (v) => setState(() => rr1 = v)),
          _switch('الذهب والمعادن: الهدف 1 = 0.7R تلقائياً', 'مقاس على ذهب حقيقي 2018–2019 (فريم الساعة): الدقة 68% بدل 54%',
              metalTp07, (v) => setState(() => metalTp07 = v)),
          _slider('Alka و ALL — الهدف الأول (R)', alkaTp1, 0.25, 1.0, 15,
              (v) => '${v.toStringAsFixed(2)}R (≈${v <= 0.3 ? 84 : v <= 0.4 ? 79 : v <= 0.6 ? 72 : v <= 0.8 ? 64 : 55}%)',
              (v) => setState(() => alkaTp1 = v)),
          _slider('الهدف 2 (R)', rr2, 1, 5, 40, (v) => '${v.toStringAsFixed(1)}R', (v) => setState(() => rr2 = v)),
          _slider('الهدف 3 (R)', rr3, 1.5, 8, 65, (v) => '${v.toStringAsFixed(1)}R', (v) => setState(() => rr3 = v)),
        ]),
        _section(Icons.visibility_rounded, 'عرض المؤشرات', autoHideWeak ? 'إخفاء الضعيف تلقائياً: مفعّل' : 'إخفاء الضعيف تلقائياً: مطفأ', [
          _switch('إخفاء المؤشر الضعيف حالياً تلقائياً',
              'إذا كان مؤشر ضعيفاً على السوق والفريم الحاليين (آخر 5000 شمعة، 30 صفقة فأكثر) تُخفى إشاراته مع زر لإظهارها',
              autoHideWeak, (v) => setState(() => autoHideWeak = v)),
        ]),
        _section(Icons.exit_to_app_rounded, 'Chandelier Exit (الوقف المتحرك)', 'الفترة $cePeriod • المضاعف ${ceMult.toStringAsFixed(1)}', [
          _slider('فترة ATR', cePeriod.toDouble(), 1, 50, 49, (v) => '${v.round()}', (v) => setState(() => cePeriod = v.round())),
          _slider('المضاعف', ceMult, 1, 5, 40, (v) => v.toStringAsFixed(1), (v) => setState(() => ceMult = v)),
        ]),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('المفاتيح تُحفظ على جهازك فقط.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ),
      ]),
      // زر الحفظ الثابت
      Positioned(
        left: 14,
        right: 14,
        bottom: 12,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: AppColors.goldGrad,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.35), blurRadius: 16)],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _save,
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.save_rounded, color: AppColors.onAccent),
                SizedBox(width: 8),
                Text('حفظ الإعدادات', style: TextStyle(color: AppColors.onAccent, fontSize: 16, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class KeyField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback? onDelete; // يُستدعى عندما يؤكد المستخدم حذف المفتاح
  const KeyField({super.key, required this.controller, required this.label, this.onDelete});
  @override
  State<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<KeyField> {
  bool hide = true;

  Future<void> _confirmDelete() async {
    if (widget.controller.text.trim().isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المفتاح؟'),
        content: Text('سيُحذف ${widget.label} بعد الضغط على "حفظ الإعدادات".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.down))),
        ],
      ),
    );
    if (ok == true) {
      widget.controller.clear();
      widget.onDelete?.call();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: hide,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'إظهار/إخفاء',
            icon: Icon(hide ? Icons.visibility : Icons.visibility_off, size: 20),
            onPressed: () => setState(() => hide = !hide),
          ),
          if (widget.onDelete != null)
            IconButton(
              tooltip: 'حذف المفتاح',
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.down),
              onPressed: _confirmDelete,
            ),
        ]),
      ),
    );
  }
}


/// تنبيهات والتطبيق مقفول (AK • King • النجوم على المفضلة).
class _AlertsSection extends StatefulWidget {
  const _AlertsSection();
  @override
  State<_AlertsSection> createState() => _AlertsSectionState();
}

class _AlertsSectionState extends State<_AlertsSection> {
  bool on = false, busy = false;
  List<String> tfs = const ['15m', '1h'];

  @override
  void initState() {
    super.initState();
    () async {
      final o = await AlertService.isOn(), t = await AlertService.tfs();
      if (mounted) setState(() { on = o; tfs = t; });
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? AppColors.gold : AppColors.border, width: 0.8),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.onAccent,
          activeTrackColor: AppColors.gold,
          secondary: const Icon(Icons.notifications_active_rounded, color: AppColors.gold),
          title: const Text('تنبيهات والتطبيق مقفول', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          subtitle: const Text('كل 15 دقيقة يفحص المفضلة وينبّهك بأي إشارة جديدة من AK أو King أو النجوم',
              style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          value: on,
          onChanged: busy
              ? null
              : (v) async {
                  setState(() => busy = true);
                  final ok = await AlertService.setOn(v);
                  if (!mounted) return;
                  setState(() { busy = false; if (ok) on = v; });
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسمح للتطبيق بالإشعارات من إعدادات الهاتف')));
                  }
                },
        ),
        if (on) ...[
          const Text('الفريمات', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final t in const ['5m', '15m', '1h', '4h'])
              ChoiceChip(
                label: Text(t.toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tfs.contains(t) ? AppColors.onAccent : AppColors.text)),
                selected: tfs.contains(t),
                selectedColor: AppColors.gold,
                backgroundColor: AppColors.surface,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  final n = [...tfs];
                  n.contains(t) ? (n.length > 1 ? n.remove(t) : null) : n.add(t);
                  setState(() => tfs = n);
                  AlertService.setTfs(n);
                },
              ),
          ]),
          const SizedBox(height: 6),
          const Text('الأسواق: المفضلة (حتى 8). أندرويد قد يؤخر الفحص قليلاً لتوفير البطارية.',
              style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: AlertService.test,
            icon: const Icon(Icons.notifications_rounded, size: 18, color: AppColors.gold),
            label: const Text('تنبيه تجريبي', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ]),
      ),
    );
  }
}
