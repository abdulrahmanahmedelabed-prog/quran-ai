/// Arabic text normalization and fuzzy word comparison.
///
/// The mushaf text is in Uthmani script (with tashkeel, small letters and
/// pause marks) while speech recognizers emit plain imla'i spelling, so both
/// sides are reduced to a common letter skeleton before comparison.
library;

import 'dart:math' as math;

const _daggerAlef = '\u0670';
const _alefMaksura = '\u0649';

final RegExp _tashkeelAndMarks = RegExp(
  // Harakat, shadda, sukun, maddah, hamza above/below, etc.
  '[ؐ-ًؚ-ٟ'
  // Quranic annotation signs: small letters, pause marks, rub el hizb, sajda.
  'ۖ-ۭ'
  // Extended Arabic marks (open tanween and other Quranic marks).
  '࣓-ࣿ'
  // Tatweel.
  'ـ]',
);
final RegExp _nonArabic = RegExp('[^ء-غف-ي ]');
final RegExp _spaces = RegExp(r'\s+');

/// Reduces [text] to bare Arabic letters separated by single spaces.
///
/// Hamza carriers, alef variants, taa marbuta and alef maksura are unified so
/// that Uthmani and imla'i spellings of the same word converge.
String normalizeArabic(String text) {
  var s = text
      // Uthmani writes some long alefs as waw/yaa + dagger alef (ٱلصَّلَوٰةَ, مُوسَىٰ).
      .replaceAll('و$_daggerAlef', 'ا')
      .replaceAll('$_alefMaksura$_daggerAlef', _alefMaksura)
      .replaceAll(_daggerAlef, 'ا')
      .replaceAll(_tashkeelAndMarks, '');
  final buf = StringBuffer();
  for (final rune in s.runes) {
    buf.write(switch (rune) {
      0x0622 || 0x0623 || 0x0625 || 0x0671 || 0x0672 || 0x0673 => 'ا',
      0x0624 => 'و',
      0x0626 || 0x0649 || 0x06CC => 'ي',
      0x0629 => 'ه',
      0x06A9 => 'ك',
      _ => String.fromCharCode(rune),
    });
  }
  s = buf.toString().replaceAll(_nonArabic, ' ');
  return s.replaceAll(_spaces, ' ').trim();
}

/// Splits already-normalized text into words.
List<String> splitWords(String normalized) =>
    normalized.isEmpty ? const [] : normalized.split(' ');

/// Normalizes and tokenizes in one step.
List<String> normalizeWords(String text) => splitWords(normalizeArabic(text));

/// The word with every alef removed. Long vowels are the most frequent
/// Uthmani/imla'i spelling difference (ٱلۡعَٰلَمِينَ vs العالمين), so
/// comparing skeletons makes matching robust to them.
String skeleton(String normalizedWord) => normalizedWord.replaceAll('ا', '');

/// Levenshtein distance between two strings (by UTF-16 unit; all normalized
/// Arabic letters are single units).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

double _ratio(String a, String b) {
  final longest = math.max(a.length, b.length);
  if (longest == 0) return 1;
  return 1 - levenshtein(a, b) / longest;
}

/// Similarity in [0, 1] between two normalized words.
double wordSimilarity(String a, String b) {
  if (a == b) return 1;
  final full = _ratio(a, b);
  final bare = _ratio(skeleton(a), skeleton(b));
  return math.max(full, bare);
}
