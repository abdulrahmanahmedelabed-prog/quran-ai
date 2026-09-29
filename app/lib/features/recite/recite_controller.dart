import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_scope.dart';
import '../../asr/engine.dart';
import '../../billing/subscription.dart';
import '../../core/recitation_review.dart';
import '../../core/recitation_tracker.dart';
import '../../data/progress.dart';
import '../../data/quran.dart';

enum ReciteStatus { idle, starting, listening, stopping }

/// Summary of a finished session, shown to the user and saved to progress.
class SessionResult {
  const SessionResult({
    required this.tier,
    required this.stats,
    required this.mistakes,
    required this.tajweedNotes,
    required this.ayahsCompleted,
  });

  /// Subscription level the session ran with (decides what is shown).
  final Tier tier;
  final SessionStats stats;

  /// Word mistakes (Pro and Plus).
  final List<MistakeRecord> mistakes;

  /// Tajweed notes (Plus).
  final List<MistakeRecord> tajweedNotes;
  final int ayahsCompleted;
}

/// Notes shown in an ayah's margin.
class MarginNotes {
  const MarginNotes(this.reading, this.tajweed);

  /// Word mistakes: wrong, skipped or hinted words.
  final int reading;

  /// Tajweed notes: short madd, case ending.
  final int tajweed;

  bool get isEmpty => reading == 0 && tajweed == 0;
}

/// Drives one recitation screen: microphone → recognizer → tracker → UI.
class ReciteController extends ChangeNotifier {
  ReciteController({required this.services, required this.surah, int fromAyah = 1})
      : hidden = services.settings.hideByDefault {
    words = services.quran.wordsOf(surah.number);
    _tracker = RecitationTracker(
      [for (final w in words) w.forms],
      config: services.settings.alignerConfig,
    );
    _passage = ReviewPassage(
      texts: [for (final w in words) w.text],
      forms: [for (final w in words) w.forms],
      marks: [for (final w in words) w.tajweed],
      ayahEnds: {for (var i = 0; i < words.length; i++) if (words[i].endsAyah) i},
    );
    if (fromAyah > 1) _tracker.restartFrom(firstWordOf(fromAyah));
    _sessionStart = _tracker.committedPosition;
  }

  final AppServices services;
  final Surah surah;
  late final List<QuranWord> words;
  late final RecitationTracker _tracker;
  late final ReviewPassage _passage;
  late int _sessionStart;

  RecognitionEngine? _engine;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<double>? _levelSub;

  ReciteStatus status = ReciteStatus.idle;
  String? error;
  /// Microphone level in [0, 1]. Separate from [notifyListeners] so the mic
  /// animation doesn't rebuild the whole page many times a second.
  final ValueNotifier<double> level = ValueNotifier(0);
  String lastTranscript = '';

  /// Memorization mode: words not yet recited are hidden.
  bool hidden;

  /// Words revealed by long-pressing in memorization mode.
  final Set<int> peeked = {};

  /// Tajweed notes from finished sessions, by word index (Plus).
  final Map<int, List<ReviewNote>> tajweedNotes = {};

  RecitationTracker get tracker => _tracker;
  Tier get tier => services.subscription.tier;
  bool get isListening => status == ReciteStatus.listening;
  int get position => _tracker.position;

  int firstWordOf(int ayah) => words.indexWhere((w) => w.ayah == ayah);

  /// Word indices of [ayah].
  Iterable<int> wordsOfAyah(int ayah) sync* {
    for (var i = firstWordOf(ayah); i < words.length && words[i].ayah == ayah; i++) {
      yield i;
    }
  }

  /// Ayah the reciter is currently on.
  int get currentAyah => position < words.length ? words[position].ayah : surah.ayahCount;

  /// What the margin shows for [ayah], limited to what the tier includes.
  MarginNotes marginNotes(int ayah) {
    if (!tier.detectsMistakes) return const MarginNotes(0, 0);
    var reading = 0, tajweed = 0;
    for (final i in wordsOfAyah(ayah)) {
      if (_tracker.stateOf(i).status.isMistake) reading++;
      if (tier.detectsTajweed) tajweed += tajweedNotes[i]?.length ?? 0;
    }
    return MarginNotes(reading, tajweed);
  }

  Future<void> start() async {
    if (status != ReciteStatus.idle) return;
    error = null;
    status = ReciteStatus.starting;
    notifyListeners();
    final engine = _engine = services.createEngine();
    _transcriptSub = engine.transcripts.listen((text) {
      lastTranscript = text;
      _tracker.update(text);
      notifyListeners();
    });
    _levelSub = engine.levels.listen((v) => level.value = v);
    try {
      await engine.start();
      status = ReciteStatus.listening;
    } catch (e) {
      error = e is RecognitionException ? e.message : 'حدث خطأ: $e';
      await _teardown();
      status = ReciteStatus.idle;
    }
    notifyListeners();
  }

  /// Stops listening, finalizes mistakes, reviews tajweed and saves progress.
  Future<SessionResult?> stop() async {
    final engine = _engine;
    if (engine == null || status != ReciteStatus.listening) return null;
    status = ReciteStatus.stopping;
    notifyListeners();
    final transcript = await engine.stop();
    final timed = engine.timedWords;
    _tracker.finish(transcript);
    await _teardown();
    if (tier.detectsTajweed && timed.isNotEmpty) {
      final notes = reviewRecitation(
        passage: _passage,
        from: _sessionStart,
        to: _tracker.committedPosition,
        heard: timed,
        config: ReviewConfig(aligner: services.settings.alignerConfig),
      );
      for (final n in notes) {
        (tajweedNotes[n.wordIndex] ??= []).add(n);
      }
    }
    status = ReciteStatus.idle;
    level.value = 0;
    final result = _saveSession();
    // The next session continues from here with a fresh transcript.
    _tracker.newTranscript();
    _sessionStart = _tracker.committedPosition;
    lastTranscript = '';
    notifyListeners();
    return result;
  }

  void toggleHidden() {
    hidden = !hidden;
    peeked.clear();
    notifyListeners();
  }

  void peek(int wordIndex) {
    peeked.add(wordIndex);
    notifyListeners();
  }

  /// Reveals the next word as a hint; it is counted as a mistake.
  void hint() {
    _tracker.hint();
    notifyListeners();
  }

  /// Restarts recitation from the start of [ayah], clearing marks after it.
  Future<void> restartFrom(int ayah) async {
    if (isListening) await stop();
    final from = firstWordOf(ayah);
    _tracker.restartFrom(from);
    tajweedNotes.removeWhere((i, _) => i >= from);
    _sessionStart = _tracker.committedPosition;
    lastTranscript = '';
    peeked.clear();
    notifyListeners();
  }

  SessionResult _saveSession() {
    final states = _tracker.states;
    final end = _tracker.committedPosition;
    final showMistakes = tier.detectsMistakes;
    final mistakes = <MistakeRecord>[];
    final tajweed = <MistakeRecord>[];
    final attempts = <AyahAttempt>[];
    final now = DateTime.now();
    var ayahWords = 0, ayahMistakes = 0;
    for (var i = _sessionStart; i < end; i++) {
      final w = words[i];
      final st = states[i];
      ayahWords++;
      if (st.status.isMistake) {
        ayahMistakes++;
        if (showMistakes) {
          mistakes.add(MistakeRecord(
            surah: w.surah,
            ayah: w.ayah,
            word: w.indexInAyah,
            expected: w.text,
            kind: st.status.name,
            heard: st.heard,
            at: now,
          ));
        }
      }
      for (final n in tajweedNotes[i] ?? const <ReviewNote>[]) {
        tajweed.add(MistakeRecord(
          surah: w.surah,
          ayah: w.ayah,
          word: w.indexInAyah,
          expected: w.text,
          kind: n.kind.name,
          heard: n.label,
          at: now,
        ));
      }
      if (w.endsAyah) {
        // Only ayahs recited from their first word count as attempts.
        if (ayahWords == i - firstWordOf(w.ayah) + 1) {
          attempts.add(AyahAttempt(surah: w.surah, ayah: w.ayah, words: ayahWords, mistakes: ayahMistakes));
        }
        ayahWords = 0;
        ayahMistakes = 0;
      }
    }
    services.progress.recordSession(
      ayahs: attempts,
      mistakes: [...mistakes, ...tajweed],
      wordsRecited: end - _sessionStart,
    );
    return SessionResult(
      tier: tier,
      stats: _tracker.statsFor(_sessionStart, end),
      mistakes: mistakes,
      tajweedNotes: tajweed,
      ayahsCompleted: attempts.length,
    );
  }

  Future<void> _teardown() async {
    await _transcriptSub?.cancel();
    await _levelSub?.cancel();
    await _engine?.dispose();
    _transcriptSub = null;
    _levelSub = null;
    _engine = null;
  }

  @override
  void dispose() {
    unawaited(_teardown());
    level.dispose();
    super.dispose();
  }
}
