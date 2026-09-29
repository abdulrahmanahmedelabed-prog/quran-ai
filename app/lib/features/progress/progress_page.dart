import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/quran.dart';
import '../../ui/theme.dart';
import '../recite/recite_page.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final progress = services.progress;
    return Scaffold(
      appBar: AppBar(title: const Text('تقدّمي')),
      body: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final now = DateTime.now();
          final week = [for (var d = 6; d >= 0; d--) now.subtract(Duration(days: d))];
          final started = [
            for (final s in services.quran.surahs)
              if (progress.recitedAyahsIn(s.number) > 0) s,
          ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                _StatCard(icon: Icons.local_fire_department, label: 'أيام متتالية', value: progress.streak()),
                _StatCard(icon: Icons.menu_book, label: 'آيات سمّعتها', value: progress.recitedAyahs),
                _StatCard(icon: Icons.verified, label: 'آيات متقنة', value: progress.masteredAyahs),
              ]),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('آخر ٧ أيام', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _WeekChart(days: week, words: [for (final d in week) progress.wordsOn(d)]),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Text('ختمتي', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress.recitedAyahs / Quran.totalAyahs,
                minHeight: 10,
                borderRadius: BorderRadius.circular(6),
              ),
              Text('${arabicNumber(progress.recitedAyahs)} من ${arabicNumber(Quran.totalAyahs)} آية'),
              if (started.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('السور', style: Theme.of(context).textTheme.titleMedium),
                for (final s in started)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('سورة ${s.name}'),
                    subtitle: LinearProgressIndicator(
                      value: progress.recitedAyahsIn(s.number) / s.ayahCount,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    trailing: Text('${arabicNumber(progress.recitedAyahsIn(s.number))}/${arabicNumber(s.ayahCount)}'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecitePage(surah: s))),
                  ),
              ],
              if (progress.recentMistakes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('أخطاء للمراجعة', style: Theme.of(context).textTheme.titleMedium),
                for (final m in progress.recentMistakes.take(30))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.expected, style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 20)),
                    subtitle: Text('سورة ${services.quran.surah(m.surah).name} · الآية ${arabicNumber(m.ayah)}'
                        '${m.heard != null ? ' · سُمِعَت «${m.heard}»' : ''}'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RecitePage(surah: services.quran.surah(m.surah), fromAyah: m.ayah),
                    )),
                  ),
              ],
              if (progress.recitedAyahs == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Text('ابدأ بتسميع أي سورة ليظهر تقدمك هنا', textAlign: TextAlign.center),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(height: 4),
            Text(arabicNumber(value), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.words});

  final List<DateTime> days;
  final List<int> words;

  static const _dayNames = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = words.fold<int>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Tooltip(
                message: '${arabicNumber(words[i])} كلمة',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 4 + 80 * words[i] / max,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: words[i] > 0 ? scheme.primary : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_dayNames[days[i].weekday - 1], style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
