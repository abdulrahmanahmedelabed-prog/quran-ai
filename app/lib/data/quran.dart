import 'dart:convert';

import '../core/arabic.dart';

class Surah {
  const Surah({
    required this.number,
    required this.name,
    required this.englishName,
    required this.revelation,
    required this.ayahs,
  });

  final int number;
  final String name;
  final String englishName;

  /// `meccan` or `medinan`.
  final String revelation;
  final List<String> ayahs;

  int get ayahCount => ayahs.length;

  /// Whether reciters open this surah with the basmala without it being an
  /// ayah (every surah except al-Fatiha, where it is ayah 1, and at-Tawba).
  bool get hasSeparateBasmala => number != 1 && number != 9;
}

/// One word of the mushaf with the forms a recognizer may produce for it.
class QuranWord {
  QuranWord({
    required this.surah,
    required this.ayah,
    required this.indexInAyah,
    required this.text,
    required this.forms,
  });

  final int surah;
  final int ayah;
  final int indexInAyah;

  /// Original Uthmani text for display.
  final String text;

  /// Accepted normalized spellings; the first is the plain normalization.
  final List<String> forms;

  String get normalized => forms.first;
}

/// Muqatta'at (disjoined letters) are recited by letter name.
const Map<String, String> _muqattaat = {
  'الم': 'الف لام ميم',
  'المص': 'الف لام ميم صاد',
  'الر': 'الف لام را',
  'المر': 'الف لام ميم را',
  'كهيعص': 'كاف ها يا عين صاد',
  'طه': 'طا ها',
  'طسم': 'طا سين ميم',
  'طس': 'طا سين',
  'يس': 'يا سين',
  'ص': 'صاد',
  'حم': 'حا ميم',
  'عسق': 'عين سين قاف',
  'ق': 'قاف',
  'ن': 'نون',
};

List<String> _formsFor(String text, {required bool mayBeMuqattaat}) {
  // Uthmani sometimes glues what is spoken as two words (يَٰٓأَيُّهَا); the
  // aligner handles that by merging heard words, so one form suffices here.
  final normalized = normalizeArabic(text).replaceAll(' ', '');
  final forms = [normalized];
  if (mayBeMuqattaat && text.contains('ٓ')) {
    final spelled = _muqattaat[normalized];
    if (spelled != null) {
      forms
        ..add(spelled.replaceAll(' ', ''))
        // Recognizers often drop the long vowel of letter names.
        ..add(skeleton(spelled.replaceAll(' ', '')));
    }
  }
  return forms;
}

class Quran {
  Quran(this.surahs);

  final List<Surah> surahs;

  static const int totalAyahs = 6236;

  factory Quran.fromJson(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final surahs = [
      for (final s in data['surahs'] as List)
        Surah(
          number: s['n'] as int,
          name: s['name'] as String,
          englishName: s['en'] as String,
          revelation: s['type'] as String,
          ayahs: List<String>.from(s['ayahs'] as List),
        ),
    ];
    return Quran(surahs);
  }

  Surah surah(int number) => surahs[number - 1];

  String ayahText(int surah, int ayah) => surahs[surah - 1].ayahs[ayah - 1];

  /// Words of one ayah.
  List<QuranWord> ayahWords(int surah, int ayah) {
    final tokens = ayahText(surah, ayah).split(' ');
    // Disjoined letters open ayah 1 of their surahs, plus 42:2 (عٓسٓقٓ).
    final muqattaatAyah = ayah == 1 || (surah == 42 && ayah == 2);
    return [
      for (var i = 0; i < tokens.length; i++)
        QuranWord(
          surah: surah,
          ayah: ayah,
          indexInAyah: i,
          text: tokens[i],
          forms: _formsFor(tokens[i], mayBeMuqattaat: muqattaatAyah && i == 0),
        ),
    ];
  }

  /// Words of [surah] from [fromAyah] to [toAyah] inclusive.
  List<QuranWord> wordsOf(int surah, {int fromAyah = 1, int? toAyah}) {
    final last = toAyah ?? this.surah(surah).ayahCount;
    return [
      for (var a = fromAyah; a <= last; a++) ...ayahWords(surah, a),
    ];
  }

  /// Every word of the Quran in order (used to build the search index).
  Iterable<QuranWord> allWords() sync* {
    for (final s in surahs) {
      for (var a = 1; a <= s.ayahCount; a++) {
        yield* ayahWords(s.number, a);
      }
    }
  }
}
