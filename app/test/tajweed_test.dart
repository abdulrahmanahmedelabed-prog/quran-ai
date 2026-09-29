import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/core/recitation_review.dart';
import 'package:quran_ai/core/tajweed.dart';
import 'package:quran_ai/data/quran.dart';

void main() {
  final quran = Quran.fromJson(File('assets/quran/quran_uthmani.json').readAsStringSync());

  /// Rules found in word [index] of an ayah, with the letters they cover.
  Map<String, TajweedRule> rulesOf(int surah, int ayah, int index) {
    final w = quran.ayahWords(surah, ayah)[index];
    return {for (final m in w.tajweed) w.text.substring(m.start, m.end): m.rule};
  }

  Set<TajweedRule> rulesIn(int surah, int ayah, int index) => rulesOf(surah, ayah, index).values.toSet();

  group('annotateAyah', () {
    test('madd lengths', () {
      expect(rulesIn(1, 7, 8), {TajweedRule.maddLazim}); // ٱلضَّآلِّينَ
      expect(rulesIn(2, 19, 3), {TajweedRule.maddMuttasil}); // ٱلسَّمَآءِ
      expect(rulesIn(2, 19, 10).contains(TajweedRule.maddMunfasil), isTrue); // فِيٓ ءَاذَانِهِم
      // Letter names of الٓمٓ: laam and meem are six counts, alif is not a madd.
      expect(rulesOf(2, 1, 0).values.where((r) => r == TajweedRule.maddLazim), hasLength(2));
    });

    test('noon sakinah and tanween', () {
      expect(rulesIn(2, 3, 7), contains(TajweedRule.ikhfa)); // يُنفِقُونَ
      expect(rulesIn(2, 2, 5), {TajweedRule.idgham}); // هُدٗى before لِّلۡمُتَّقِينَ
      expect(rulesIn(2, 10, 8), {TajweedRule.iqlab}); // أَلِيمُۢ بِمَا
      expect(rulesIn(2, 5, 3), contains(TajweedRule.idgham)); // مِّن رَّبِّهِمۡ
      expect(rulesIn(2, 5, 3), contains(TajweedRule.ghunnah)); // the doubled meem of مِّن
      expect(rulesIn(2, 7, 10), isEmpty); // عَذَابٌ before عَظِيمٞ: clear (izhar)
    });

    test('meem sakinah', () {
      expect(rulesIn(2, 10, 1), {TajweedRule.idghamShafawi}); // قُلُوبِهِم مَّرَضٞ
      expect(rulesIn(1, 7, 3), isEmpty); // عَلَيۡهِمۡ غَيۡرِ: clear
    });

    test('qalqalah', () {
      expect(rulesIn(112, 1, 3), {TajweedRule.qalqalah}); // أَحَدٌ at the stop
      expect(rulesIn(2, 19, 8), contains(TajweedRule.qalqalah)); // يَجۡعَلُونَ
    });

    test('annotates the whole Quran without errors', () {
      var marks = 0;
      for (final w in quran.allWords()) {
        for (final m in w.tajweed) {
          expect(m.end, greaterThan(m.start));
          expect(m.end, lessThanOrEqualTo(w.text.length));
          marks++;
        }
      }
      expect(marks, greaterThan(20000));
    });
  });

  group('finalVowel', () {
    test('reads case endings', () {
      expect(finalVowel('ٱلۡحَمۡدُ'), 'u');
      expect(finalVowel('عَذَابٌ'), 'un');
      expect(finalVowel('مَرَضٗا'), 'an');
      expect(finalVowel('كَانُواْ'), 'u');
      expect(finalVowel('الحمدَ'), 'a');
      expect(finalVowel('الحمد'), isNull);
    });
  });

  group('reviewRecitation', () {
    final words = quran.wordsOf(1);
    final passage = ReviewPassage(
      texts: [for (final w in words) w.text],
      forms: [for (final w in words) w.forms],
      marks: [for (final w in words) w.tajweed],
      ayahEnds: {for (var i = 0; i < words.length; i++) if (words[i].endsAyah) i},
    );
    const perLetter = 0.12;

    /// Fatiha heard at an even pace; [madd] seconds are added to الضالين.
    List<TimedWord> timed({double madd = 0, Map<int, String> spelled = const {}}) {
      var t = 0.0;
      return [
        for (var i = 0; i < words.length; i++)
          () {
            final d = words[i].normalized.length * perLetter + (i == words.length - 1 ? madd : 0);
            final w = TimedWord(spelled[i] ?? words[i].normalized, t, t + d);
            t += d + 0.05;
            return w;
          }(),
      ];
    }

    test('accepts a madd held six counts', () {
      final notes = reviewRecitation(passage: passage, from: 0, to: words.length, heard: timed(madd: 4 * perLetter));
      expect(notes, isEmpty);
    });

    test('flags a madd lazim cut short', () {
      final notes = reviewRecitation(passage: passage, from: 0, to: words.length, heard: timed());
      expect(notes.single.kind, ReviewKind.shortMadd);
      expect(notes.single.rule, TajweedRule.maddLazim);
      expect(notes.single.wordIndex, words.length - 1);
    });

    test('flags a wrong case ending when diacritics are heard', () {
      // الحمدَ instead of ٱلۡحَمۡدُ (word 4 of the surah, after the basmala).
      final notes = reviewRecitation(
        passage: passage,
        from: 0,
        to: words.length,
        heard: timed(madd: 4 * perLetter, spelled: {4: 'الحمدَ', 5: 'لِلَّهِ'}),
      );
      expect(notes.single.kind, ReviewKind.endingVowel);
      expect(notes.single.wordIndex, 4);
      expect(notes.single.expectedVowel, 'u');
    });
  });
}
