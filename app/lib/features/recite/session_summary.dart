import 'package:flutter/material.dart';

import '../../data/progress.dart';
import '../../ui/theme.dart';
import '../subscription/paywall_page.dart';
import 'recite_controller.dart';

Future<void> showSessionSummary(BuildContext context, SessionResult result) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _SessionSummary(result: result),
  );
}

/// End-of-session sheet. It encourages rather than grades: notes are called
/// notes, and the free tier sees its progress without any mistake count.
class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.result});

  final SessionResult result;

  @override
  Widget build(BuildContext context) {
    final s = result.stats;
    final colors = WordColors.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final withNotes = result.tier.detectsMistakes;
    final pct = (s.accuracy * 100).round();
    final message = !withNotes
        ? 'بارك الله فيك، واصل'
        : switch (pct) {
            100 => 'ما شاء الله! قراءة بلا ملاحظات',
            >= 90 => 'أحسنت! قراءة ممتازة',
            >= 70 => 'جيد، في الهامش مواضع للمراجعة',
            _ => 'راجع المواضع المسجلة في الهامش وأعد المحاولة',
          };
    const quranStyle = TextStyle(fontFamily: 'AmiriQuran', fontSize: 20);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            if (withNotes)
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
                        color: colors.correct,
                      ),
                      Center(
                        child: Text('${arabicNumber(pct)}٪',
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              )
            else
              Icon(Icons.auto_stories, size: 64, color: scheme.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Metric(label: 'كلمة قرأتها', value: s.recited, color: colors.correct),
                _Metric(label: 'آية أتممتها', value: result.ayahsCompleted, color: scheme.primary),
                if (withNotes) _Metric(label: 'ملاحظة قراءة', value: s.mistakes, color: colors.skipped),
                if (result.tier.detectsTajweed)
                  _Metric(label: 'ملاحظة تجويد', value: result.tajweedNotes.length, color: colors.hinted),
              ],
            ),
            if (result.mistakes.isNotEmpty) ...[
              const Divider(height: 32),
              Text('هامش القراءة', style: theme.textTheme.titleMedium),
              for (final m in result.mistakes.take(20)) _NoteTile(m: m, style: quranStyle),
            ],
            if (result.tajweedNotes.isNotEmpty) ...[
              const Divider(height: 32),
              Text('هامش التجويد', style: theme.textTheme.titleMedium),
              for (final m in result.tajweedNotes.take(20)) _NoteTile(m: m, style: quranStyle),
            ],
            if (!result.tier.detectsTajweed) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: Text(withNotes ? 'أضف ملاحظات التجويد مع بلس' : 'اعرف مواضع الخطأ مع برو'),
                onPressed: () => Navigator.of(context)
                  ..pop()
                  ..push(MaterialPageRoute(builder: (_) => const PaywallPage())),
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

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.m, required this.style});

  final MistakeRecord m;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Text('${arabicNumber(m.surah)}:${arabicNumber(m.ayah)}'),
        title: Text(m.expected, style: style),
        subtitle: Text(m.description),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  // Metrics share the row equally so four of them fit narrow screens and
  // large system fonts.
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(arabicNumber(value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
        ]),
      );
}
