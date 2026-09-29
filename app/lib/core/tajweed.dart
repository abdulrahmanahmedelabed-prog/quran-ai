/// Tajweed rules read from the Uthmani text.
///
/// The Madani mushaf encodes most rulings in its marks: a noon or meem
/// written without sukun is hidden or merged, open tanween (ٗ ٞ ٖ) is
/// followed by ikhfa or idgham, a small meem (ۢ) marks iqlab, and the maddah
/// (ٓ) marks every madd longer than two counts. This module turns those marks
/// into rule spans for coloring and into length requirements that recordings
/// can be checked against.
library;

enum TajweedRule {
  /// Noon or meem with shadda: two counts of nasalization.
  ghunnah('غنة'),

  /// Noon sakinah or tanween hidden before one of fifteen letters.
  ikhfa('إخفاء'),

  /// Noon sakinah or tanween merged into the next letter (يرملون).
  idgham('إدغام'),

  /// Noon sakinah or tanween turned into meem before ب.
  iqlab('إقلاب'),

  /// Meem sakinah hidden before ب.
  ikhfaShafawi('إخفاء شفوي'),

  /// Meem sakinah merged into a following meem.
  idghamShafawi('إدغام شفوي'),

  /// ق ط ب ج د with sukun (or at a stop): an echoing release.
  qalqalah('قلقلة'),

  /// Six counts: madd followed by a shadda or sukun in the same word, and the
  /// letter names of the muqatta'at.
  maddLazim('مد لازم'),

  /// Four to five counts: madd followed by hamza in the same word.
  maddMuttasil('مد متصل'),

  /// Four to five counts in Hafs (via ash-Shatibiyyah): madd at a word's end
  /// followed by hamza.
  maddMunfasil('مد منفصل'),

  /// Other maddah-marked madd.
  madd('مد');

  const TajweedRule(this.label);

  final String label;

  bool get isMadd => this == maddLazim || this == maddMuttasil || this == maddMunfasil || this == madd;

  /// Minimum counts a recitation must hold for rules that are checked by
  /// duration, or null when the rule isn't checked. Munfasil is left out
  /// because shortening it is a valid reading via at-Tayyibah.
  int? get minimumCounts => switch (this) {
        maddLazim => 6,
        maddMuttasil => 4,
        _ => null,
      };
}

/// A rule applying to `[start, end)` (UTF-16 offsets) of one word's text.
class TajweedMark {
  const TajweedMark(this.rule, this.start, this.end);

  final TajweedRule rule;
  final int start;
  final int end;

  @override
  String toString() => '${rule.name}[$start,$end)';
}

// Marks that attach to a letter.
const _fatha = 0x064E, _damma = 0x064F, _kasra = 0x0650, _shadda = 0x0651, _sukunRound = 0x0652;
const _maddah = 0x0653;
const _daggerAlef = 0x0670;
const _smallHighMeemIqlab = 0x06E2, _smallLowMeemIqlab = 0x06ED;
const _sukun = 0x06E1;
const _smallWaw = 0x06E5, _smallYeh = 0x06E6;
const _tanweenClear = {0x064B, 0x064C, 0x064D};

/// Open tanween, written when ikhfa or idgham follows: the standard code
/// points and the legacy ones older Tanzil files use.
const _tanweenOpen = {0x08F0, 0x08F1, 0x08F2, 0x0657, 0x065E, 0x0656};

bool _isMark(int c) =>
    (c >= 0x0610 && c <= 0x061A) ||
    (c >= 0x064B && c <= 0x065F) ||
    c == _daggerAlef ||
    (c >= 0x06D6 && c <= 0x06ED) ||
    (c >= 0x08D3 && c <= 0x08FF);

const _hamzas = {0x0621, 0x0623, 0x0625, 0x0624, 0x0626};
const _throatLetters = {0x0621, 0x0623, 0x0625, 0x0647, 0x0639, 0x062D, 0x063A, 0x062E}; // ء ه ع ح غ خ
const _idghamGhunnahLetters = {0x064A, 0x0646, 0x0645, 0x0648}; // ي ن م و
const _idghamPlainLetters = {0x0644, 0x0631}; // ل ر
const _qalqalahLetters = {0x0642, 0x0637, 0x0628, 0x062C, 0x062F}; // ق ط ب ج د
const _maddLetters = {0x0627, 0x0648, 0x064A, 0x0649, 0x0640}; // ا و ي ى and tatweel carrying ٰ

class _Cluster {
  _Cluster(this.base, this.start);

  final int base;
  final int start;
  int end = 0;
  final Set<int> marks = {};

  bool has(int m) => marks.contains(m);

  /// Carries a vowel, sukun or shadda (i.e. is not a bare sakin letter).
  bool get isVoweled =>
      has(_fatha) || has(_damma) || has(_kasra) || has(_shadda) || has(_sukun) || has(_sukunRound) ||
      marks.any(_tanweenClear.contains) || marks.any(_tanweenOpen.contains);

  bool get hasOpenTanween => marks.any(_tanweenOpen.contains);
}

List<_Cluster> _clusters(String word) {
  final out = <_Cluster>[];
  for (var i = 0; i < word.length; i++) {
    final c = word.codeUnitAt(i);
    if (_isMark(c) && out.isNotEmpty) {
      out.last.marks.add(c);
      out.last.end = i + 1;
    } else if (!_isMark(c)) {
      out.add(_Cluster(c, i)..end = i + 1);
    }
  }
  return out;
}

/// First pronounced letter of a word (hamzat al-wasl is skipped).
int? _firstLetter(String? word) {
  if (word == null) return null;
  final cs = _clusters(word);
  for (final c in cs) {
    if (c.base == 0x0671 || c.base == 0x06DE) continue; // ٱ, ۞
    return c.base;
  }
  return null;
}

TajweedRule? _noonRule(int? next) {
  if (next == null) return null;
  if (next == 0x0628) return TajweedRule.iqlab;
  if (_throatLetters.contains(next)) return null; // izhar
  if (_idghamGhunnahLetters.contains(next) || _idghamPlainLetters.contains(next)) return TajweedRule.idgham;
  return TajweedRule.ikhfa;
}

/// Tajweed marks for every word of one ayah.
///
/// [words] are the ayah's Uthmani words. The last word is treated as a stop
/// (qalqalah applies to its final letter).
List<List<TajweedMark>> annotateAyah(List<String> words) {
  final result = <List<TajweedMark>>[];
  for (var w = 0; w < words.length; w++) {
    final cs = _clusters(words[w]);
    final nextWord = w + 1 < words.length ? words[w + 1] : null;
    final marks = <TajweedMark>[];
    void add(TajweedRule r, _Cluster c) => marks.add(TajweedMark(r, c.start, c.end));

    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      final next = i + 1 < cs.length ? cs[i + 1] : null;
      final nextBase = next?.base ?? _firstLetter(nextWord);
      final isLast = next == null;

      // Ghunnah on a doubled noon or meem.
      if ((c.base == 0x0646 || c.base == 0x0645) && c.has(_shadda)) {
        add(TajweedRule.ghunnah, c);
        continue;
      }

      // Iqlab is written explicitly with a small meem.
      if (c.has(_smallHighMeemIqlab) || c.has(_smallLowMeemIqlab)) {
        add(TajweedRule.iqlab, c);
        continue;
      }

      // Noon sakinah written bare (no sukun): hidden or merged.
      // (A maddah instead marks a muqatta'at letter name, handled below.)
      if (c.base == 0x0646 && !c.isVoweled && !c.has(_maddah)) {
        final r = _noonRule(nextBase);
        if (r != null) add(r, c);
        continue;
      }

      // Open tanween at the end of a word.
      if (c.hasOpenTanween) {
        final r = _noonRule(_firstLetter(nextWord));
        if (r != null) add(r, c);
      }

      // Meem sakinah written bare.
      if (c.base == 0x0645 && !c.isVoweled && !c.has(_maddah)) {
        if (nextBase == 0x0628) add(TajweedRule.ikhfaShafawi, c);
        if (nextBase == 0x0645) add(TajweedRule.idghamShafawi, c);
        continue;
      }

      // Qalqalah: with sukun, or on the last letter when stopping.
      if (_qalqalahLetters.contains(c.base) &&
          (c.has(_sukun) || (w == words.length - 1 && isLast))) {
        add(TajweedRule.qalqalah, c);
        continue;
      }

      // Madd marked with a maddah.
      if (c.has(_maddah)) {
        final isMaddLetter = _maddLetters.contains(c.base) ||
            c.has(_daggerAlef) ||
            c.has(_smallWaw) ||
            c.has(_smallYeh);
        TajweedRule rule;
        if (!isMaddLetter) {
          rule = TajweedRule.maddLazim; // letter name of the muqatta'at
        } else if (isLast) {
          rule = _hamzas.contains(_firstLetter(nextWord)) ? TajweedRule.maddMunfasil : TajweedRule.madd;
        } else if (_hamzas.contains(next.base)) {
          rule = TajweedRule.maddMuttasil;
        } else if (next.has(_shadda) || next.has(_sukun)) {
          rule = TajweedRule.maddLazim;
        } else {
          rule = TajweedRule.madd;
        }
        add(rule, c);
      }
    }
    result.add(marks);
  }
  return result;
}

/// Short vowel on a word's last pronounced letter (its case ending), as one
/// of `a u i an un in` or `0` for sukun; null when the word carries no
/// diacritics there.
String? finalVowel(String word) {
  final cs = _clusters(word);
  for (var i = cs.length - 1; i >= 0; i--) {
    final c = cs[i];
    final m = c.marks;
    if (m.contains(0x064B) || m.contains(0x08F0) || m.contains(0x0657)) return 'an';
    if (m.contains(0x064C) || m.contains(0x08F1) || m.contains(0x065E)) return 'un';
    if (m.contains(0x064D) || m.contains(0x08F2) || m.contains(0x0656)) return 'in';
    if (m.contains(_fatha)) return 'a';
    if (m.contains(_damma)) return 'u';
    if (m.contains(_kasra)) return 'i';
    if (m.contains(_sukun) || m.contains(_sukunRound)) {
      // A silent alef (كَانُواْ) says nothing about the ending.
      if (c.base == 0x0627) continue;
      return '0';
    }
    // Unmarked trailing letters (the alef after fathatan, alef maksura) are
    // skipped; anything else unmarked means the word isn't diacritized.
    if (c.base == 0x0627 || c.base == 0x0649 || c.base == 0x064A || c.base == 0x0648) continue;
    return null;
  }
  return null;
}

/// Whether [word] ends with a pause sign, where a reciter may stop (and so
/// drop the case ending or lengthen the last syllable).
bool hasPauseSign(String word) => word.runes.any((c) => c >= 0x06D6 && c <= 0x06DC);
