import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/arabic.dart';
import '../../data/quran.dart';
import '../../ui/theme.dart';
import '../recite/recite_page.dart';

class SurahListPage extends StatefulWidget {
  const SurahListPage({super.key});

  @override
  State<SurahListPage> createState() => _SurahListPageState();
}

class _SurahListPageState extends State<SurahListPage> {
  String _query = '';

  bool _matches(Surah s) {
    if (_query.isEmpty) return true;
    final q = _query.trim();
    if (int.tryParse(q) == s.number) return true;
    return normalizeArabic(s.name).contains(normalizeArabic(q)) ||
        s.englishName.toLowerCase().contains(q.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final surahs = services.quran.surahs.where(_matches).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('قرآن AI')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'ابحث عن سورة',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: services.progress,
              builder: (context, _) => ListView.builder(
                itemCount: surahs.length,
                itemBuilder: (context, i) => _SurahTile(surah: surahs[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurahTile extends StatelessWidget {
  const _SurahTile({required this.surah});

  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final done = services.progress.recitedAyahsIn(surah.number);
    return ListTile(
      leading: _NumberBadge(surah.number),
      title: Text('سورة ${surah.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${surah.revelation == 'meccan' ? 'مكية' : 'مدنية'} · ${arabicNumber(surah.ayahCount)} آية'),
          if (done > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: done / surah.ayahCount,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ],
      ),
      trailing: Text(surah.englishName, style: TextStyle(color: scheme.outline, fontFamily: 'Roboto')),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RecitePage(surah: surah)),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.number);

  final int number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        arabicNumber(number),
        style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}
