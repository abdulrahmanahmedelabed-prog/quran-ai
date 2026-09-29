import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/core/arabic.dart';
import 'package:quran_ai/core/ayah_search.dart';
import 'package:quran_ai/core/recitation_tracker.dart';
import 'package:quran_ai/data/quran.dart';

void main() {
  final quran = Quran.fromJson(File('assets/quran/quran_uthmani.json').readAsStringSync());

  RecitationTracker trackerFor(int surah, {int fromAyah = 1, int? toAyah}) => RecitationTracker(
        [for (final w in quran.wordsOf(surah, fromAyah: fromAyah, toAyah: toAyah)) w.forms],
      );

  group('normalizeArabic', () {
    test('reduces Uthmani and imlaei spellings to the same letters', () {
      expect(normalizeArabic('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ'), 'بسم الله الرحمان الرحيم');
      expect(normalizeArabic('بسم الله الرحمن الرحيم'), 'بسم الله الرحمن الرحيم');
      expect(normalizeArabic('ٱلصَّلَوٰةَ'), 'الصلاه');
      expect(normalizeArabic('مُوسَىٰ'), 'موسي');
      expect(normalizeArabic('إِنَّهُۥ'), 'انه');
      expect(normalizeArabic('۞ إِنَّ'), 'ان');
    });

    test('similar spellings are judged the same word', () {
      expect(wordSimilarity(normalizeArabic('ٱلۡعَٰلَمِينَ'), normalizeArabic('العالمين')), 1);
      expect(wordSimilarity(normalizeArabic('ٱلرَّحۡمَٰنِ'), normalizeArabic('الرحمن')), 1);
      expect(wordSimilarity('من', 'ما'), lessThan(0.7));
    });
  });

  group('Quran data', () {
    test('has the full text', () {
      expect(quran.surahs, hasLength(114));
      expect(quran.surahs.fold<int>(0, (s, x) => s + x.ayahCount), Quran.totalAyahs);
      expect(quran.surah(2).ayahCount, 286);
    });

    test('muqattaat accept the spelled-out letter names', () {
      final alm = quran.ayahWords(2, 1).first;
      expect(alm.forms, contains('الفلامميم'));
      final ysn = quran.ayahWords(36, 1).first;
      expect(ysn.forms, contains('ياسين'));
    });
  });

  group('RecitationTracker', () {
    test('follows a correct recitation of al-Fatiha', () {
      final t = trackerFor(1);
      t.finish('بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين '
          'اياك نعبد واياك نستعين اهدنا الصراط المستقيم صراط الذين انعمت عليهم '
          'غير المغضوب عليهم ولا الضالين');
      expect(t.isComplete, isTrue);
      expect(t.stats.mistakes, 0);
      expect(t.stats.correct, t.expected.length);
    });

    test('flags a wrong word and keeps what was heard', () {
      final t = trackerFor(1, toAyah: 2);
      t.finish('بسم الله الرحمن الرحيم الحمد لله رب العلوم');
      expect(t.states.last.status, WordStatus.wrong);
      expect(t.states.last.heard, 'العلوم');
      expect(t.stats.wrong, 1);
    });

    test('flags a skipped word', () {
      final t = trackerFor(1, toAyah: 2);
      t.finish('بسم الله الرحيم الحمد لله رب العالمين');
      expect(t.states[2].status, WordStatus.skipped);
      expect(t.stats.skipped, 1);
      expect(t.isComplete, isTrue);
    });

    test('forgives repetition and self-correction', () {
      final t = trackerFor(1, toAyah: 2);
      t.finish('بسم الله بسم الله الرحمن الرحيم الحمد لله رب العالم العالمين');
      expect(t.stats.mistakes, 0);
      expect(t.isComplete, isTrue);
    });

    test('ignores isti\'adha and basmala before a surah', () {
      final t = trackerFor(2, toAyah: 2);
      t.finish('اعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم الف لام ميم '
          'ذلك الكتاب لا ريب فيه هدى للمتقين');
      expect(t.stats.mistakes, 0);
      expect(t.isComplete, isTrue);
    });

    test('ignores a closing formula after stopping mid-surah', () {
      final t = trackerFor(2, fromAyah: 1, toAyah: 3);
      t.finish('الم ذلك الكتاب لا ريب فيه هدى للمتقين صدق الله العظيم');
      expect(t.stats.mistakes, 0);
      expect(t.committedPosition, quran.wordsOf(2, toAyah: 2).length);
    });

    test('handles words Uthmani joins together', () {
      final t = trackerFor(2, fromAyah: 21, toAyah: 21);
      t.finish('يا ايها الناس اعبدوا ربكم الذي خلقكم والذين من قبلكم لعلكم تتقون');
      expect(t.stats.mistakes, 0);
      expect(t.isComplete, isTrue);
    });

    test('follows a reciter who skips a whole ayah', () {
      final t = trackerFor(112);
      t.finish('قل هو الله احد الله الصمد ولم يكن له كفوا احد');
      expect(t.isComplete, isTrue);
      final lyalid = quran.ayahWords(112, 3).length;
      expect(t.stats.skipped, lyalid);
    });

    test('streams: progress shows live, mistakes only once stable', () {
      final t = trackerFor(1, toAyah: 2);
      t.update('بسم الله');
      expect(t.position, 2);
      expect(t.committedPosition, 0);
      t.update('بسم الله الرحمن الرحيم الحمد');
      t.update('بسم الله الرحمن الرحيم الحمد لله رب');
      expect(t.committedPosition, greaterThan(0));
      expect(t.position, 7);
      t.finish('بسم الله الرحمن الرحيم الحمد لله رب العالمين');
      expect(t.isComplete, isTrue);
      expect(t.stats.mistakes, 0);
    });

    test('hint reveals the next word and counts it', () {
      final t = trackerFor(112);
      t.update('قل هو');
      expect(t.hint(), 2);
      expect(t.states[2].status, WordStatus.hinted);
      t.finish('قل هو احد الله الصمد');
      expect(t.states[3].status, WordStatus.correct);
      expect(t.stats.hinted, 1);
    });
  });

  group('AyahSearchIndex', () {
    final index = AyahSearchIndex([
      for (final w in quran.allWords()) IndexedWord(w.surah, w.ayah, w.indexInAyah, w.forms),
    ]);

    test('finds Ayat al-Kursi from a few words', () {
      final hits = index.search('الله لا اله الا هو الحي القيوم لا تاخذه سنه');
      expect(hits.first.surah, 2);
      expect(hits.first.ayah, 255);
    });

    test('finds a passage despite recognition errors', () {
      final hits = index.search('قل اعوذ برب الفلق من شر ما خلق ومن شر غاسق اذا وقب');
      expect(hits.first.surah, 113);
      expect(hits.first.ayah, 1);
    });

    test('finds the middle of an ayah', () {
      final hits = index.search('فبای الاء ربكما تكذبان');
      expect(hits.first.surah, 55);
    });

    test('returns nothing for unrelated speech', () {
      expect(index.search('مرحبا كيف حالك اليوم'), isEmpty);
    });
  });
}
