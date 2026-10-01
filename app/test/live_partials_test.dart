// Replays the live partials the on-device recognizer produced on an Android
// emulator for al-Minshawi reciting al-Ikhlas (including two decoding loops
// it later corrected) and checks the mushaf tracker marks every word read
// without a false note.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/asr/engine.dart';
import 'package:quran_ai/core/recitation_tracker.dart';
import 'package:quran_ai/data/quran.dart';

const partials = [
  'قُلْ هُوَ اللَّهُ',
  'قُلْ هُوَ اللَّهُ أَحَدٌ',
  'قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الَّذَا الْمَأْوَى الْمَأْوَى الْمَأْو',
  'قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ',
  'قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ لَمْ يَلِدْ وَلَا لَمْ يَلِدْ وَلَا لَمْ يَلِدْ وَلَا لَمْ يَلِدْ وَلَا لَمْ يَلِدْ وَلَا لَمْ يَلِدلَمْ يَلِدْ وَلَمْ يَلِدْ وَلَمْ يَلِدْ وَلَمْ يَلِدْ وَل',
  'قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ لَمْ يَلِدْ وَلَمْ يُولَدْ',
  'قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ لَمْ يَلِدْ وَلَمْ يُولَدْ وَلَمْ يَقْتَرُوا لَمْ يَقْتَرُوا لَمْ يَقْت',
  'قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ لَمْ يَلِدْ وَلَمْ يُولَدْ وَلَمْ يَكُنْ لَهُ كُفُرٌ وَلَمْ يَكُنْ لَهُ كُفُرٌ وَلَمْ يَكُنْ لَهُ كُفُرٌ و',
  'قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ لَمْ يَلِدْ وَلَمْ يُولَدْ وَلَمْ يَكُنْ لَهُ كُفِوًا أَحَدٌ',
];

void main() {
  test('live partials of al-Ikhlas leave no false notes', () {
    final quran = Quran.fromJson(File('assets/quran/quran_uthmani.json').readAsStringSync());
    final words = quran.wordsOf(112);
    final tracker = RecitationTracker([for (final w in words) w.forms]);
    for (final p in partials) {
      tracker.update(cleanTranscript(p));
    }
    tracker.finish(cleanTranscript(partials.last));
    final stats = tracker.stats;
    expect(stats.correct, words.length, reason: '$stats');
    expect(stats.wrong + stats.skipped + stats.hinted, 0);
  });
}
