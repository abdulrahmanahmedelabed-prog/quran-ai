import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/asr/engine.dart';
import 'package:quran_ai/data/quran.dart';

void main() {
  test('a decoding loop is cut back to one occurrence', () {
    expect(
      collapseLoops('قُلْ هُوَ اللَّهُ أَحَدٌ لَمْ يَلِدْ وَلَا لَمْ يَلِدْ وَلَا لَمْ يَلِدْ وَلَا لَمْ يَلِد'),
      'قُلْ هُوَ اللَّهُ أَحَدٌ لَمْ يَلِدْ وَلَا',
    );
    expect(collapseLoops('اللَّهُ الْمَأْوَى الْمَأْوَى الْمَأْو'), 'اللَّهُ الْمَأْوَى الْمَأْوَى الْمَأْو');
    expect(cleanTranscript(' [موسيقى] الحمد  لله '), 'الحمد لله');
  });

  test('no surah is changed by loop collapsing', () {
    final quran = Quran.fromJson(File('assets/quran/quran_uthmani.json').readAsStringSync());
    for (var s = 1; s <= 114; s++) {
      final text = quran.wordsOf(s).map((w) => w.text).join(' ');
      expect(collapseLoops(text), text, reason: 'surah $s');
    }
  });
}
