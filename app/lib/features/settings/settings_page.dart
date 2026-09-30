import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../asr/engine.dart';
import '../../asr/on_device_engine.dart';
import '../../data/settings.dart';
import '../../ui/theme.dart';
import '../subscription/paywall_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final s = services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, services.subscription]),
        builder: (context, _) => ListView(
          children: [
            const _OwnerTile(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text('باقتك: ${services.subscription.tier.label}'),
                  subtitle: const Text('برو: ملاحظات القراءة · بلس: والتجويد'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallPage())),
                ),
              ),
            ),
            const _Section('التعرّف على التلاوة'),
            RadioGroup<EngineKind>(
              groupValue: s.engine,
              onChanged: (v) => s.engine = v!,
              child: const Column(children: [
                RadioListTile(
                  value: EngineKind.server,
                  title: Text('عبر الخادم'),
                  subtitle: Text('يحتاج خادمًا خاصًا واتصالًا بالإنترنت'),
                ),
                RadioListTile(
                  value: EngineKind.onDevice,
                  title: Text('على الجهاز'),
                  subtitle: Text('يعمل دون إنترنت بعد تنزيل النموذج مرة واحدة، ويحفظ خصوصيتك'),
                ),
              ]),
            ),
            if (s.engine == EngineKind.server) ...[
              _TextSetting(
                label: 'عنوان الخادم',
                value: s.serverUrl,
                hint: 'https://asr.example.com',
                onSaved: (v) => s.serverUrl = v,
              ),
              _TextSetting(label: 'مفتاح الوصول (اختياري)', value: s.apiKey, onSaved: (v) => s.apiKey = v),
            ] else ...[
              _TextSetting(
                label: 'رابط نموذج ggml (اختياري)',
                value: s.modelUrl,
                hint: 'اتركه فارغاً لاستخدام نموذج Whisper العام',
                onSaved: (v) => s.modelUrl = v,
              ),
              const _ModelDownloadTile(),
            ],
            const _Section('دقة التصحيح'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<Strictness>(
                segments: [for (final v in Strictness.values) ButtonSegment(value: v, label: Text(v.label))],
                selected: {s.strictness},
                onSelectionChanged: (v) => s.strictness = v.first,
              ),
            ),
            const _Section('العرض'),
            ListTile(
              title: const Text('حجم خط المصحف'),
              subtitle: Slider(
                value: s.fontSize,
                min: 20,
                max: 44,
                divisions: 12,
                label: s.fontSize.round().toString(),
                onChanged: (v) => s.fontSize = v,
              ),
            ),
            if (services.mushaf != null)
              SwitchListTile(
                title: const Text('صفحات مصحف المدينة'),
                subtitle: const Text('١٥ سطرًا في الصفحة كالمصحف المطبوع، أو نص متصل عند إيقافه'),
                value: s.mushafPages,
                onChanged: (v) => s.mushafPages = v,
              ),
            SwitchListTile(
              title: const Text('إظهار الملاحظات على الكلمات أثناء القراءة'),
              subtitle: const Text('عند إيقافه تبقى الملاحظات في الهامش فقط حتى لا تقاطعك'),
              value: s.mistakesInText,
              onChanged: services.subscription.tier.detectsMistakes ? (v) => s.mistakesInText = v : null,
            ),
            SwitchListTile(
              title: const Text('تلوين أحكام التجويد'),
              subtitle: const Text('متاح في باقة بلس'),
              value: s.tajweedColors && services.subscription.tier.detectsTajweed,
              onChanged: services.subscription.tier.detectsTajweed ? (v) => s.tajweedColors = v : null,
            ),
            SwitchListTile(
              title: const Text('ابدأ في وضع الحفظ'),
              subtitle: const Text('إخفاء الآيات حتى تتلوها'),
              value: s.hideByDefault,
              onChanged: (v) => s.hideByDefault = v,
            ),
            const _Section('القارئ'),
            ListTile(
              title: const Text('صوت القارئ للاستماع'),
              trailing: DropdownButton<String>(
                value: s.reciterId,
                underline: const SizedBox(),
                items: [for (final r in reciters) DropdownMenuItem(value: r.id, child: Text(r.name))],
                onChanged: (v) => s.reciterId = v!,
              ),
            ),
            const _Section('البيانات'),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('مسح سجل التقدم'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('مسح سجل التقدم؟'),
                    content: const Text('سيتم حذف جميع الإحصائيات والأخطاء المحفوظة.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح')),
                    ],
                  ),
                );
                if (ok == true) services.progress.reset();
              },
            ),
            const AboutListTile(
              icon: Icon(Icons.info_outline),
              applicationName: 'قرآن AI',
              aboutBoxChildren: [
                Text('نص المصحف: مشروع تنزيل (tanzil.net). الخط: Amiri Quran (رخصة OFL). '
                    'التلاوات الصوتية: everyayah.com.'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(title,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
      );
}

class _TextSetting extends StatelessWidget {
  const _TextSetting({required this.label, required this.value, required this.onSaved, this.hint});

  final String label;
  final String value;
  final String? hint;
  final ValueChanged<String> onSaved;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value.isEmpty ? (hint ?? '—') : value, textDirection: TextDirection.ltr),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final controller = TextEditingController(text: value);
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(label),
            content: TextField(
              controller: controller,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(hintText: hint),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('حفظ')),
            ],
          ),
        );
        controller.dispose();
        if (result != null) onSaved(result);
      },
    );
  }
}

class _ModelDownloadTile extends StatefulWidget {
  const _ModelDownloadTile();

  @override
  State<_ModelDownloadTile> createState() => _ModelDownloadTileState();
}

class _ModelDownloadTileState extends State<_ModelDownloadTile> {
  bool? _ready;
  String? _error;
  String? _checkedUrl;

  @override
  void initState() {
    super.initState();
    // A download started from the recitation screen shows here too, and the
    // tile turns ready when it finishes.
    ModelManager.progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    ModelManager.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    if (ModelManager.progress.value == null) {
      _checkedUrl = null; // finished: look at the disk again
      _check();
    }
    setState(() {});
  }

  Future<void> _check() async {
    final manager = AppScope.of(context).modelManager;
    if (_checkedUrl == manager.modelUrl) return;
    _checkedUrl = manager.modelUrl;
    final ready = await manager.isDownloaded();
    if (mounted) setState(() => _ready = ready);
  }

  Future<void> _download() async {
    setState(() => _error = null);
    final manager = AppScope.of(context).modelManager;
    try {
      await manager.ensure();
      _ready = true;
    } catch (e) {
      _error = e is RecognitionException ? e.message : 'فشل التنزيل: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _check();
    final manager = AppScope.of(context).modelManager;
    final downloading = manager.isDownloading;
    final progress = ModelManager.progress.value;
    final ready = _ready == true && !downloading;
    return ListTile(
      leading: Icon(ready ? Icons.check_circle : Icons.download_outlined,
          color: ready ? Theme.of(context).colorScheme.primary : null),
      title: Text(ready
          ? 'النموذج جاهز على الجهاز'
          : downloading
              ? 'جارٍ تنزيل النموذج…${progress != null && progress >= 0 ? ' ${arabicNumber((progress * 100).round())}٪' : ''}'
              : 'تنزيل النموذج'),
      subtitle: downloading
          ? LinearProgressIndicator(value: progress != null && progress >= 0 ? progress : null)
          : Text(_error ?? (ready ? 'محفوظ على جهازك، يعمل دون إنترنت' : 'يُنزَّل مرة واحدة ثم يعمل دون إنترنت')),
      // Nothing to do once it is on the device or while it is downloading.
      onTap: ready || downloading || _ready == null ? null : _download,
    );
  }
}

/// Owner sign-in: unlocks every feature (Pro and Plus) without a purchase.
class _OwnerTile extends StatelessWidget {
  const _OwnerTile();

  @override
  Widget build(BuildContext context) {
    final sub = AppScope.of(context).subscription;
    if (sub.isOwner) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: ListTile(
            leading: const Icon(Icons.verified_user),
            title: const Text('حساب المالك'),
            subtitle: const Text('كل الميزات والإعدادات مفعّلة (برو وبلس)'),
            trailing: TextButton(onPressed: sub.signOutOwner, child: const Text('خروج')),
          ),
        ),
      );
    }
    return ListTile(
      leading: const Icon(Icons.admin_panel_settings_outlined),
      title: const Text('دخول المالك'),
      onTap: () async {
        final controller = TextEditingController();
        final code = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('رمز المالك'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              obscureText: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('دخول')),
            ],
          ),
        );
        controller.dispose();
        if (code == null || !context.mounted) return;
        final ok = sub.unlockOwner(code);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'أهلًا بك، تم تفعيل حساب المالك' : 'الرمز غير صحيح')),
        );
      },
    );
  }
}
