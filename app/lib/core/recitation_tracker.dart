/// Follows a live recitation against the mushaf and records mistakes.
///
/// Recognizers deliver the whole transcript of the session so far and keep
/// revising its tail. The tracker commits the part that has stopped changing
/// (so mistakes are only reported once they are certain) and aligns the
/// still-changing tail tentatively, which is what drives the live highlight.
library;

import 'alignment.dart';
import 'arabic.dart';

enum WordStatus {
  /// Not recited yet.
  pending,

  /// Recited correctly.
  correct,

  /// Recited, but a different word was heard.
  wrong,

  /// Passed over without being recited.
  skipped,

  /// Revealed with a hint instead of being recited.
  hinted,
}

extension WordStatusX on WordStatus {
  bool get isMistake =>
      this == WordStatus.wrong || this == WordStatus.skipped || this == WordStatus.hinted;
}

class WordState {
  const WordState(this.status, {this.heard, this.tentative = false});

  static const pending = WordState(WordStatus.pending);

  final WordStatus status;

  /// What the recognizer heard in place of this word, for wrong words.
  final String? heard;

  /// True while the underlying transcript may still change.
  final bool tentative;
}

class SessionStats {
  const SessionStats({
    required this.correct,
    required this.wrong,
    required this.skipped,
    required this.hinted,
  });

  final int correct;
  final int wrong;
  final int skipped;
  final int hinted;

  int get recited => correct + wrong + skipped + hinted;
  int get mistakes => wrong + skipped + hinted;

  /// Share of recited words that were correct, in [0, 1].
  double get accuracy => recited == 0 ? 1 : correct / recited;
}

class RecitationTracker {
  RecitationTracker(
    this.expected, {
    this.config = const AlignerConfig(),
    this.unstableTail = 2,
    this.maxUncommittedExtras = 6,
    this.lookahead = 60,
  }) : _committed = List.filled(expected.length, WordState.pending);

  /// Accepted normalized forms for each expected word, in reading order.
  final List<List<String>> expected;
  final AlignerConfig config;

  /// Trailing words of a transcript treated as unstable even if unchanged.
  final int unstableTail;

  /// Stable heard words with no match that may wait for more context before
  /// they are committed as extra words.
  final int maxUncommittedExtras;

  /// How far past the cursor a reciter may jump (skipping words) and still be
  /// followed.
  final int lookahead;

  final List<WordState> _committed;
  int _cursor = 0;
  int _committedHeard = 0;
  List<String> _previousHeard = const [];

  // Tentative overlay from the latest transcript.
  Map<int, WordState> _tentative = const {};
  int _tentativeCursor = 0;

  /// Index of the next expected word, including tentative progress.
  int get position => _tentativeCursor > _cursor ? _tentativeCursor : _cursor;

  /// Index of the next expected word based on committed progress only.
  int get committedPosition => _cursor;

  bool get isComplete => _cursor >= expected.length;

  WordState stateOf(int index) => _tentative[index] ?? _committed[index];

  List<WordState> get states => [for (var i = 0; i < expected.length; i++) stateOf(i)];

  SessionStats get stats => statsFor();

  /// Statistics for committed words in `[start, end)`.
  SessionStats statsFor([int start = 0, int? end]) {
    var c = 0, w = 0, s = 0, h = 0;
    for (var i = start; i < (end ?? expected.length); i++) {
      switch (_committed[i].status) {
        case WordStatus.correct:
          c++;
        case WordStatus.wrong:
          w++;
        case WordStatus.skipped:
          s++;
        case WordStatus.hinted:
          h++;
        case WordStatus.pending:
          break;
      }
    }
    return SessionStats(correct: c, wrong: w, skipped: s, hinted: h);
  }

  /// Feeds the full transcript of the session so far.
  void update(String transcript) {
    final heard = normalizeWords(transcript);

    var stable = 0;
    final limit = heard.length < _previousHeard.length ? heard.length : _previousHeard.length;
    while (stable < limit && heard[stable] == _previousHeard[stable]) {
      stable++;
    }
    _previousHeard = heard;
    stable = stable - unstableTail;
    if (stable > _committedHeard) {
      _commit(heard.sublist(_committedHeard, stable), force: false);
    }
    _alignTentative(heard);
  }

  /// Commits everything heard so far; call when the reciter stops.
  void finish(String transcript) {
    final heard = normalizeWords(transcript);
    if (heard.length > _committedHeard) {
      _commit(heard.sublist(_committedHeard), force: true);
    }
    _previousHeard = heard;
    _tentative = const {};
    _tentativeCursor = _cursor;
  }

  /// Reveals the next word as a hint (memorization mode). Returns its index,
  /// or null when the passage is complete.
  int? hint() {
    final i = position;
    if (i >= expected.length) return null;
    // Anything tentatively recited before the hint is accepted as is.
    _tentative.forEach((k, v) {
      if (k < i && _committed[k].status == WordStatus.pending) {
        _committed[k] = WordState(v.status, heard: v.heard);
      }
    });
    _committed[i] = const WordState(WordStatus.hinted);
    _cursor = i + 1;
    _committedHeard = _previousHeard.length;
    _tentative = const {};
    _tentativeCursor = _cursor;
    return i;
  }

  /// Prepares for a new recognition session whose transcript starts empty,
  /// keeping everything recited so far.
  void newTranscript() {
    _previousHeard = const [];
    _committedHeard = 0;
    _tentative = const {};
    _tentativeCursor = _cursor;
  }

  /// Starts over from [index] (e.g. when the user picks another ayah),
  /// clearing marks from there on.
  void restartFrom(int index) {
    _cursor = index.clamp(0, expected.length);
    for (var i = _cursor; i < expected.length; i++) {
      _committed[i] = WordState.pending;
    }
    newTranscript();
  }

  AlignmentResult _align(List<String> heard) {
    final end = (_cursor + heard.length * 2 + lookahead).clamp(0, expected.length);
    return alignWords(expected.sublist(_cursor, end), heard, config: config);
  }

  void _commit(List<String> heard, {required bool force}) {
    final result = _align(heard);
    var heardUsed = result.heardConsumedByMatches;
    if (force || heard.length - heardUsed > maxUncommittedExtras) {
      heardUsed = heard.length;
    }
    if (heardUsed == 0) return;
    for (final op in result.ops) {
      if (op.kind != AlignOpKind.extra && op.expected >= result.expectedConsumed) break;
      switch (op.kind) {
        case AlignOpKind.match:
          final ok = op.similarity >= config.threshold;
          _committed[_cursor + op.expected] = ok
              ? const WordState(WordStatus.correct)
              : WordState(WordStatus.wrong, heard: heard.sublist(op.heardStart, op.heardEnd).join(' '));
        case AlignOpKind.skip:
          _committed[_cursor + op.expected] = const WordState(WordStatus.skipped);
        case AlignOpKind.extra:
          break;
      }
    }
    _cursor += result.expectedConsumed;
    _committedHeard += heardUsed;
    if (force) _pairTrailingExtras(heard.sublist(result.heardConsumedByMatches));
  }

  /// When recitation stops, the aligner prefers calling a mispronounced last
  /// word "extra" over "wrong" since nothing follows it. Pair a short tail of
  /// extras with the next expected words when they resemble them, so that
  /// mistake is still reported; unrelated closing words (صدق الله العظيم)
  /// stay ignored.
  void _pairTrailingExtras(List<String> tail) {
    if (tail.isEmpty || tail.length > 2) return;
    for (final word in tail) {
      if (_cursor >= expected.length) return;
      if (bestSimilarity(word, expected[_cursor]) < 0.4) return;
      _committed[_cursor] = WordState(WordStatus.wrong, heard: word);
      _cursor++;
    }
  }

  void _alignTentative(List<String> heard) {
    final tail = heard.length > _committedHeard ? heard.sublist(_committedHeard) : const <String>[];
    if (tail.isEmpty || _cursor >= expected.length) {
      _tentative = const {};
      _tentativeCursor = _cursor;
      return;
    }
    final result = _align(tail);
    final overlay = <int, WordState>{};
    for (final op in result.matches) {
      // Only show confident progress live; mistakes wait for the commit.
      if (op.similarity >= config.threshold) {
        overlay[_cursor + op.expected] = const WordState(WordStatus.correct, tentative: true);
      }
    }
    _tentative = overlay;
    _tentativeCursor = _cursor + result.expectedConsumed;
  }
}
