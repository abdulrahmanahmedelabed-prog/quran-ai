/// After-session review of how words were pronounced (Plus): madd lengths
/// from word timings, and case-ending vowels when the recognizer outputs
/// diacritics.
///
/// Findings are deliberately conservative. They are shown quietly in the
/// margin, so a missed finding costs little while a false one would nag the
/// reciter about something they did right.
library;

import 'alignment.dart';
import 'arabic.dart';
import 'tajweed.dart';

/// A recognized word with its time span in seconds.
class TimedWord {
  const TimedWord(this.text, this.start, this.end);

  factory TimedWord.fromJson(Map<String, dynamic> j) =>
      TimedWord(j['text'] as String, (j['start'] as num).toDouble(), (j['end'] as num).toDouble());

  /// Raw recognizer text, possibly with diacritics.
  final String text;
  final double start;
  final double end;

  double get duration => end - start;
}

enum ReviewKind {
  /// A madd held noticeably shorter than its required length.
  shortMadd,

  /// A different case-ending vowel than the mushaf's.
  endingVowel,
}

class ReviewNote {
  const ReviewNote({required this.wordIndex, required this.kind, this.rule, this.heard, this.expectedVowel});

  /// Index into the expected word list.
  final int wordIndex;
  final ReviewKind kind;

  /// The madd rule, for [ReviewKind.shortMadd].
  final TajweedRule? rule;

  /// What was heard, for [ReviewKind.endingVowel].
  final String? heard;
  final String? expectedVowel;

  String get label => switch (kind) {
        ReviewKind.shortMadd => '${rule!.label}: ${_lengthOf(rule!)}، وبدا أقصر',
        ReviewKind.endingVowel => 'الحركة الأخيرة: ${_vowelName(expectedVowel)}',
      };
}

String _lengthOf(TajweedRule r) => switch (r) {
      TajweedRule.maddLazim => 'يُمَدّ ست حركات',
      TajweedRule.maddMuttasil => 'يُمَدّ أربع أو خمس حركات',
      _ => 'يُمَدّ',
    };

String _vowelName(String? v) => switch (v) {
      'a' => 'فتحة',
      'u' => 'ضمة',
      'i' => 'كسرة',
      'an' => 'تنوين فتح',
      'un' => 'تنوين ضم',
      'in' => 'تنوين كسر',
      '0' => 'سكون',
      _ => '',
    };

/// Expected words of the passage being reviewed.
class ReviewPassage {
  const ReviewPassage({required this.texts, required this.forms, required this.marks, required this.ayahEnds});

  /// Uthmani text of each word.
  final List<String> texts;

  /// Accepted normalized forms of each word.
  final List<List<String>> forms;

  /// Tajweed marks of each word.
  final List<List<TajweedMark>> marks;

  /// Indices of words that end an ayah.
  final Set<int> ayahEnds;
}

class ReviewConfig {
  const ReviewConfig({
    this.aligner = const AlignerConfig(),
    this.minPaceSamples = 6,
    this.maxRatio = 0.65,
    this.minDeficitCounts = 2,
  });

  final AlignerConfig aligner;

  /// Words needed to estimate the reciter's pace before judging any madd.
  final int minPaceSamples;

  /// A madd is flagged when the word lasts less than this share of its
  /// expected duration...
  final double maxRatio;

  /// ...and falls short by at least this many counts.
  final double minDeficitCounts;
}

/// Extra counts a checked madd adds beyond a plain letter.
double _extraCounts(TajweedRule r) => switch (r) {
      TajweedRule.maddLazim => 4,
      TajweedRule.maddMuttasil => 2.5,
      _ => 0,
    };

/// Reviews expected words `[from, to)` against what was heard.
List<ReviewNote> reviewRecitation({
  required ReviewPassage passage,
  required int from,
  required int to,
  required List<TimedWord> heard,
  ReviewConfig config = const ReviewConfig(),
}) {
  if (heard.isEmpty || from >= to) return const [];

  // Normalized heard tokens, remembering which timed word each came from and
  // whether that timed word produced exactly one token (so its duration
  // belongs to it alone).
  final tokens = <String>[];
  final source = <int>[];
  final single = <bool>[];
  for (var k = 0; k < heard.length; k++) {
    final ws = normalizeWords(heard[k].text);
    for (final w in ws) {
      tokens.add(w);
      source.add(k);
      single.add(ws.length == 1);
    }
  }
  if (tokens.isEmpty) return const [];

  final end = (to + 10).clamp(0, passage.forms.length);
  final result = alignWords(passage.forms.sublist(from, end), tokens, config: config.aligner);

  // Confidently matched one-to-one words.
  final matched = <int, TimedWord>{};
  for (final op in result.matches) {
    if (op.similarity < config.aligner.threshold || op.heardEnd - op.heardStart != 1) continue;
    if (!single[op.heardStart]) continue;
    final e = from + op.expected;
    if (e >= to) continue;
    matched[e] = heard[source[op.heardStart]];
  }

  final notes = <ReviewNote>[];

  // Case endings, where the recognizer gives diacritics. Words where a
  // reciter may stop are skipped: stopping drops the ending.
  matched.forEach((e, w) {
    if (passage.ayahEnds.contains(e) || hasPauseSign(passage.texts[e])) return;
    final said = finalVowel(w.text);
    final want = finalVowel(passage.texts[e]);
    if (said == null || want == null || said == want) return;
    notes.add(ReviewNote(wordIndex: e, kind: ReviewKind.endingVowel, heard: w.text, expectedVowel: want));
  });

  // Madd lengths, relative to the reciter's own pace per letter.
  int letters(int e) => passage.forms[e].first.length;
  final paces = <double>[];
  matched.forEach((e, w) {
    if (w.duration <= 0) return;
    if (passage.marks[e].any((m) => m.rule.isMadd)) return;
    if (passage.ayahEnds.contains(e) || hasPauseSign(passage.texts[e])) return;
    paces.add(w.duration / letters(e));
  });
  if (paces.length >= config.minPaceSamples) {
    paces.sort();
    final pace = paces[paces.length ~/ 2];
    matched.forEach((e, w) {
      if (w.duration <= 0) return;
      final checked = passage.marks[e].where((m) => m.rule.minimumCounts != null).map((m) => m.rule).toList();
      if (checked.isEmpty) return;
      final extra = checked.fold<double>(0, (s, r) => s + _extraCounts(r));
      final expected = (letters(e) + extra) * pace;
      final deficit = expected - w.duration;
      if (w.duration / expected < config.maxRatio && deficit >= config.minDeficitCounts * pace) {
        notes.add(ReviewNote(wordIndex: e, kind: ReviewKind.shortMadd, rule: checked.first));
      }
    });
  }

  notes.sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
  return notes;
}
