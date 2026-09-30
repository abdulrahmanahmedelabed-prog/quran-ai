import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/data/mushaf_layout.dart';
import 'package:quran_ai/data/quran.dart';

void main() {
  final quran = Quran.fromJson(File('assets/quran/quran_uthmani.json').readAsStringSync());
  final layout = MushafLayout.fromJson(File('assets/quran/mushaf_madani.json').readAsStringSync());

  test('604 pages of 15 lines', () {
    expect(layout.pages, hasLength(MushafLayout.pageCount));
    for (final page in layout.pages) {
      expect(page, hasLength(MushafLayout.linesPerPage));
    }
  });

  test('every word of the Quran appears exactly once', () {
    final seen = <String, int>{};
    for (final page in layout.pages) {
      for (final line in page) {
        for (final s in line.segments.where((s) => s.hasWords)) {
          for (var w = s.first; w <= s.last; w++) {
            final key = '${s.surah}:${s.ayah}:$w';
            seen[key] = (seen[key] ?? 0) + 1;
          }
        }
      }
    }
    var words = 0;
    for (final s in quran.surahs) {
      for (var a = 1; a <= s.ayahCount; a++) {
        final n = quran.ayahWords(s.number, a, withTajweed: false).length;
        words += n;
        for (var w = 0; w < n; w++) {
          expect(seen['${s.number}:$a:$w'], 1, reason: '${s.number}:$a word $w');
        }
      }
    }
    expect(seen.length, words);
  });

  test('surah titles and basmala sit where the printed mushaf has them', () {
    // Page 604: al-Ikhlas, al-Falaq and an-Nas, each with title and basmala.
    final last = layout.pages[603];
    expect([for (final l in last) l.kind], [
      MushafLineKind.surahTitle, MushafLineKind.basmala, MushafLineKind.text, MushafLineKind.text,
      MushafLineKind.surahTitle, MushafLineKind.basmala, MushafLineKind.text, MushafLineKind.text, MushafLineKind.text,
      MushafLineKind.surahTitle, MushafLineKind.basmala, MushafLineKind.text, MushafLineKind.text, MushafLineKind.text,
      MushafLineKind.text,
    ]);
    expect(last[0].titleSurah, 112);
    // At-Tawba has a title but no basmala.
    final tawba = layout.pages[layout.pageOf(9, 1)];
    final title = tawba.indexWhere((l) => l.kind == MushafLineKind.surahTitle && l.titleSurah == 9);
    expect(tawba[title + 1].kind, MushafLineKind.text);
  });

  test('pages of well-known passages', () {
    expect(layout.pageOf(1, 1), 0);
    expect(layout.pageOf(2, 1), 1);
    expect(layout.pageOf(2, 255), 41); // Ayat al-Kursi, page 42
    expect(layout.pageOf(36, 1), 439); // Ya-Sin, page 440
    expect(layout.pageOf(67, 1), 561); // al-Mulk, page 562
  });
}
