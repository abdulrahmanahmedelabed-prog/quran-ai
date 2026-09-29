import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_scope.dart';
import '../../asr/engine.dart';
import '../../core/recitation_tracker.dart';
import '../../data/progress.dart';
import '../../data/quran.dart';

enum ReciteStatus { idle, starting, listening, stopping }

/// Summary of a finished session, shown to the user and saved to progress.
class SessionResult {
  const SessionResult({required this.stats, required this.mistakes, required this.ayahsCompleted});

  final SessionStats stats;
  final List<MistakeRecord> mistakes;
  final int ayahsCompleted;
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
    if (fromAyah > 1) _tracker.restartFrom(firstWordOf(fromAyah));
    _sessionStart = _tracker.committedPosition;
  }

  final AppServices services;
  final Surah surah;
  late final List<QuranWord> words;
  late final RecitationTracker _tracker;
  late int _sessionStart;

  RecognitionEngine? _engine;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<double>? _levelSub;

  ReciteStatus status = ReciteStatus.idle;
  String? error;
  double level = 0;
  String lastTranscript = '';

  /// Memorization mode: words not yet recited are hidden.
  bool hidden;

  /// Words revealed by long-pressing in memorization mode.
  final Set<int> peeked = {};

  RecitationTracker get tracker => _tracker;
  bool get isListening => status == ReciteStatus.listening;
  int get position => _tracker.position;

  int firstWordOf(int ayah) => words.indexWhere((w) => w.ayah == ayah);

  /// Ayah the reciter is currently on.
  int get currentAyah => position < words.length ? words[position].ayah : surah.ayahCount;

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
    _levelSub = engine.levels.listen((v) {
      level = v;
      notifyListeners();
    });
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

  /// Stops listening, finalizes mistakes and saves progress.
  Future<SessionResult?> stop() async {
    final engine = _engine;
    if (engine == null || status != ReciteStatus.listening) return null;
    status = ReciteStatus.stopping;
    notifyListeners();
    final transcript = await engine.stop();
    _tracker.finish(transcript);
    await _teardown();
    status = ReciteStatus.idle;
    level = 0;
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
    _tracker.restartFrom(firstWordOf(ayah));
    _sessionStart = _tracker.committedPosition;
    lastTranscript = '';
    peeked.clear();
    notifyListeners();
  }

  SessionResult _saveSession() {
    final states = _tracker.states;
    final end = _tracker.committedPosition;
    final mistakes = <MistakeRecord>[];
    final attempts = <AyahAttempt>[];
    final now = DateTime.now();
    var ayahWords = 0, ayahMistakes = 0;
    for (var i = _sessionStart; i < end; i++) {
      final w = words[i];
      final st = states[i];
      ayahWords++;
      if (st.status.isMistake) {
        ayahMistakes++;
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
      final ayahDone = i + 1 == words.length || words[i + 1].ayah != w.ayah;
      if (ayahDone) {
        // Only ayahs recited from their first word count as attempts.
        if (ayahWords == i - firstWordOf(w.ayah) + 1) {
          attempts.add(AyahAttempt(surah: w.surah, ayah: w.ayah, words: ayahWords, mistakes: ayahMistakes));
        }
        ayahWords = 0;
        ayahMistakes = 0;
      }
    }
    services.progress.recordSession(ayahs: attempts, mistakes: mistakes, wordsRecited: end - _sessionStart);
    return SessionResult(
      stats: _tracker.statsFor(_sessionStart, end),
      mistakes: mistakes,
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
    super.dispose();
  }
}
