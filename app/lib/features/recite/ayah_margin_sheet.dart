import 'package:flutter/material.dart';

import '../../billing/subscription.dart';
import '../../core/recitation_tracker.dart';
import '../../core/tajweed.dart';
import '../../ui/theme.dart';
import '../subscription/paywall_page.dart';
import 'recite_controller.dart';

/// The quiet note count shown beside an ayah. Mistakes never interrupt the
/// recitation; they collect here for the reader to look at when they choose.
class MarginMarker extends StatelessWidget {
  const MarginMarker({super.key, required this.notes, required this.onTap});

  final MarginNotes notes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WordColors.of(context);
    return Semantics(
      button: true,
      label: 'ملاحظات الآية',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notes.reading > 0) _Dot(count: notes.reading, color: colors.skipped),
            if (notes.tajweed > 0) ...[
              const SizedBox(height: 4),
              _Dot(count: notes.tajweed, color: colors.hinted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(arabicNumber(count), style: TextStyle(fontSize: 12, color: color, height: 1.2)),
      );
}

/// The margin of one ayah: reading notes, tajweed notes and the rulings in
/// the ayah, with actions to recite or listen from it.
class AyahMarginSheet extends StatelessWidget {
  const AyahMarginSheet({
    super.key,
    required this.controller,
    required this.ayah,
    required this.onReciteFrom,
    required this.onListen,
  });

  final ReciteController controller;
  final int ayah;
  final VoidCallback onReciteFrom;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final colors = WordColors.of(context);
    final tier = c.tier;
    final indices = c.wordsOfAyah(ayah).toList();
    final mistakes = [
      for (final i in indices)
        if (c.tracker.stateOf(i).status.isMistake) (word: c.words[i], state: c.tracker.stateOf(i)),
    ];
    final tajweedNotes = [
      for (final i in indices) for (final n in c.tajweedNotes[i] ?? const []) (word: c.words[i], note: n),
    ];
    final rules = <TajweedRule, Set<String>>{};
    for (final i in indices) {
      final w = c.words[i];
      for (final m in w.tajweed) {
        (rules[m.rule] ??= {}).add(w.text);
      }
    }

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );
    const quranStyle = TextStyle(fontFamily: 'AmiriQuran', fontSize: 22);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Text('هامش الآية ${arabicNumber(ayah)} · سورة ${c.surah.name}',
                style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (tier.detectsMistakes) ...[
              section('ملاحظات القراءة'),
              if (mistakes.isEmpty)
                const Text('لا ملاحظات على قراءتك في هذه الآية.')
              else
                for (final m in mistakes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.circle, size: 10, color: colors.forStatus(m.state.status)),
                    title: Text(m.word.text, style: quranStyle),
                    subtitle: Text(switch (m.state.status) {
                      WordStatus.wrong => 'سُمِعَت «${m.state.heard ?? ''}»',
                      WordStatus.skipped => 'لم تُقرأ',
                      WordStatus.hinted => 'بمساعدة تلميح',
                      _ => '',
                    }),
                  ),
            ],
            if (tier.detectsTajweed) ...[
              section('ملاحظات التجويد'),
              if (tajweedNotes.isEmpty)
                const Text('لا ملاحظات تجويد في هذه الآية.')
              else
                for (final t in tajweedNotes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.circle, size: 10, color: colors.hinted),
                    title: Text(t.word.text, style: quranStyle),
                    subtitle: Text(t.note.label),
                  ),
              if (rules.isNotEmpty) ...[
                section('أحكام التجويد في الآية'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in rules.entries)
                      Chip(
                        avatar: CircleAvatar(backgroundColor: tajweedColor(e.key, theme.brightness), radius: 6),
                        label: Text('${e.key.label} (${arabicNumber(e.value.length)})'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
            if (!tier.detectsTajweed) ...[
              const SizedBox(height: 16),
              _UpgradeCard(tier: tier),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.mic),
              label: const Text('سمّع من هذه الآية'),
              onPressed: onReciteFrom,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.headphones),
              label: const Text('استمع من هذه الآية'),
              onPressed: onListen,
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.tier});

  final Tier tier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = tier.detectsMistakes
        ? 'مع اشتراك بلس تظهر هنا أحكام التجويد في الآية، وملاحظات على المدود والحركات.'
        : 'مع اشتراك برو تظهر هنا ملاحظات قراءتك بهدوء دون مقاطعة، ومع بلس أحكام التجويد أيضًا.';
    return Card(
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      child: ListTile(
        leading: Icon(Icons.auto_awesome, color: scheme.primary),
        title: Text(text, style: const TextStyle(fontSize: 15)),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallPage())),
      ),
    );
  }
}
