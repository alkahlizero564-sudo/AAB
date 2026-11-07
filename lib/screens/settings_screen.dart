import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
  late bool useAi, liveWs;
  late String source;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    tiingo = TextEditingController(text: s.tiingoKey);
    twelve = [for (final k in s.twelveKeys) TextEditingController(text: k)];
    gemini = [for (final k in s.geminiKeys) TextEditingController(text: k)];
    model = TextEditingController(text: s.geminiModel);
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
    final s = AppSettings(
      tiingoKey: tiingo.text,
      twelveKeys: twelve.map((e) => e.text).toList(),
      geminiKeys: gemini.map((e) => e.text).toList(),
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

  Widget _title(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(i, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
      );

  Widget _slider(String label, double v, double min, double max, int div,
      String Function(double) fmt, ValueChanged<double> on) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(fmt(v),
            style: const TextStyle(
                color: AppColors.accent, fontWeight: FontWeight.bold)),
      ]),
      Slider(value: v, min: min, max: max, divisions: div, onChanged: on),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.vpn_key, 'مفتاح Tiingo (فوركس + ذهب)'),
          KeyField(controller: tiingo, label: 'Tiingo API Key'),
        ]),
      ),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.vpn_key, 'مفاتيح Twelve Data (فوركس، ذهب، أسهم)'),
          const Text('أضف حتى 4 مفاتيح — يتم التبديل بينها تلقائياً لتفادي حد الطلبات.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 10),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KeyField(controller: twelve[i], label: 'Twelve Data ${i + 1}'),
            ),
        ]),
      ),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.auto_awesome, 'مفاتيح Gemini API'),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KeyField(controller: gemini[i], label: 'Gemini ${i + 1}'),
            ),
          const SizedBox(height: 4),
          TextField(
            controller: model,
            decoration: const InputDecoration(
                labelText: 'اسم نموذج Gemini', isDense: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('مراجعة الإشارات بواسطة Gemini',
                style: TextStyle(fontSize: 13)),
            value: useAi,
            onChanged: (v) => setState(() => useAi = v),
          ),
        ]),
      ),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.tune, 'إعدادات التداول والتحديث'),
          Row(children: [
            const Text('مصدر البيانات', style: TextStyle(fontSize: 13)),
            const Spacer(),
            DropdownButton<String>(
              value: source,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('تلقائي')),
                DropdownMenuItem(value: 'twelve', child: Text('Twelve Data')),
                DropdownMenuItem(value: 'tiingo', child: Text('Tiingo')),
              ],
              onChanged: (v) => setState(() => source = v ?? 'auto'),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('بث لحظي (ثانية بثانية)',
                style: TextStyle(fontSize: 13)),
            value: liveWs,
            onChanged: (v) => setState(() => liveWs = v),
          ),
          _slider('تحديث الشموع من الخادم كل', refresh.toDouble(), 15, 120, 21,
              (v) => '${v.round()} ث', (v) => setState(() => refresh = v.round())),
          _slider('فاصل جلب السعر (عند غياب WebSocket)', pollSec.toDouble(), 3, 60, 19,
              (v) => '${v.round()} ث', (v) => setState(() => pollSec = v.round())),
          _slider('مضاعف ATR لوقف الخسارة', atrMult, 1, 3, 20,
              (v) => v.toStringAsFixed(1), (v) => setState(() => atrMult = v)),
          _slider('الهدف 1 (R)', rr1, 0.5, 3, 25,
              (v) => '${v.toStringAsFixed(1)}R', (v) => setState(() => rr1 = v)),
          _slider('الهدف 2 (R)', rr2, 1, 5, 40,
              (v) => '${v.toStringAsFixed(1)}R', (v) => setState(() => rr2 = v)),
          _slider('الهدف 3 (R)', rr3, 1.5, 8, 65,
              (v) => '${v.toStringAsFixed(1)}R', (v) => setState(() => rr3 = v)),
          _slider('Chandelier Exit - فترة ATR', cePeriod.toDouble(), 1, 50, 49,
              (v) => '${v.round()}', (v) => setState(() => cePeriod = v.round())),
          _slider('Chandelier Exit - المضاعف', ceMult, 1, 5, 40,
              (v) => v.toStringAsFixed(1), (v) => setState(() => ceMult = v)),
        ]),
      ),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('حفظ الإعدادات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }
}

class KeyField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  const KeyField({super.key, required this.controller, required this.label});
  @override
  State<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<KeyField> {
  bool hide = true;
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
        suffixIcon: IconButton(
          icon: Icon(hide ? Icons.visibility : Icons.visibility_off, size: 20),
          onPressed: () => setState(() => hide = !hide),
        ),
      ),
    );
  }
}
