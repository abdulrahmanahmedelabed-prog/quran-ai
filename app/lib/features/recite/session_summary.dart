import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import 'recite_controller.dart';

Future<void> showSessionSummary(BuildContext context, SessionResult result) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _SessionSummary(result: result),
  );
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.result});

  final SessionResult result;

  @override
  Widget build(BuildContext context) {
    final s = result.stats;
    final colors = WordColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pct = (s.accuracy * 100).round();
    final message = switch (pct) {
      100 => 'ما شاء الله! تلاوة بلا أخطاء',
      >= 90 => 'أحسنت! تلاوة ممتازة',
      >= 70 => 'جيد، راجع المواضع المظللة',
      _ => 'تحتاج إلى مزيد من المراجعة',
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: s.accuracy,
                      strokeWidth: 10,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: pct >= 90 ? colors.correct : (pct >= 70 ? colors.skipped : colors.wrong),
                    ),
                    Center(
                      child: Text('${arabicNumber(pct)}٪',
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Metric(label: 'كلمات صحيحة', value: s.correct, color: colors.correct),
                _Metric(label: 'أخطاء', value: s.wrong, color: colors.wrong),
                _Metric(label: 'كلمات فائتة', value: s.skipped, color: colors.skipped),
                if (s.hinted > 0) _Metric(label: 'تلميحات', value: s.hinted, color: colors.hinted),
              ],
            ),
            if (result.ayahsCompleted > 0) ...[
              const SizedBox(height: 12),
              Text('الآيات المكتملة: ${arabicNumber(result.ayahsCompleted)}', textAlign: TextAlign.center),
            ],
            if (result.mistakes.isNotEmpty) ...[
              const Divider(height: 32),
              Text('المواضع التي تحتاج مراجعة', style: Theme.of(context).textTheme.titleMedium),
              for (final m in result.mistakes.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text('${arabicNumber(m.surah)}:${arabicNumber(m.ayah)}'),
                  title: Text(m.expected, style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 20)),
                  subtitle: Text(switch (m.kind) {
                    'wrong' => 'سُمِعَت: «${m.heard ?? ''}»',
                    'skipped' => 'لم تُقرأ',
                    _ => 'استُعين بتلميح',
                  }),
                ),
            ],
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('متابعة')),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(arabicNumber(value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
        Text(label),
      ]);
}
