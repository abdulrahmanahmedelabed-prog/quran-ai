import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../asr/engine.dart';
import '../../data/settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final s = services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          children: [
            const _Section('التعرّف على التلاوة'),
            RadioGroup<EngineKind>(
              groupValue: s.engine,
              onChanged: (v) => s.engine = v!,
              child: const Column(children: [
                RadioListTile(
                  value: EngineKind.server,
                  title: Text('عبر الخادم'),
                  subtitle: Text('أدق، ويتطلب اتصالاً بالإنترنت'),
                ),
                RadioListTile(
                  value: EngineKind.onDevice,
                  title: Text('على الجهاز'),
                  subtitle: Text('يعمل دون إنترنت ويحفظ خصوصيتك'),
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
              applicationName: 'تلاوة',
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
  double? _progress;
  bool _downloading = false;
  String? _error;
  String? _checkedUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _check();
  }

  Future<void> _check() async {
    final manager = AppScope.of(context).modelManager;
    if (_checkedUrl == manager.modelUrl) return;
    _checkedUrl = manager.modelUrl;
    final ready = await manager.isDownloaded();
    if (mounted) setState(() => _ready = ready);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
    });
    try {
      await AppScope.of(context).modelManager.ensure(onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      _ready = true;
    } catch (e) {
      _error = e is RecognitionException ? e.message : 'فشل التنزيل: $e';
    }
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    _check();
    return ListTile(
      leading: Icon(_ready == true ? Icons.check_circle : Icons.download_outlined),
      title: Text(_ready == true ? 'النموذج جاهز على الجهاز' : 'تنزيل النموذج'),
      subtitle: _downloading
          ? LinearProgressIndicator(value: _progress)
          : Text(_error ?? 'يُنزَّل مرة واحدة ثم يعمل دون إنترنت'),
      onTap: _downloading || _ready == true ? null : _download,
    );
  }
}
