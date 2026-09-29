import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of reciting one ayah in one session.
class AyahAttempt {
  const AyahAttempt({required this.surah, required this.ayah, required this.words, required this.mistakes});

  final int surah;
  final int ayah;
  final int words;
  final int mistakes;
}

/// One mistake, kept for review.
class MistakeRecord {
  const MistakeRecord({
    required this.surah,
    required this.ayah,
    required this.word,
    required this.expected,
    required this.kind,
    required this.at,
    this.heard,
  });

  factory MistakeRecord.fromJson(Map<String, dynamic> j) => MistakeRecord(
        surah: j['s'] as int,
        ayah: j['a'] as int,
        word: j['w'] as int,
        expected: j['e'] as String,
        kind: j['k'] as String,
        heard: j['h'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      );

  final int surah;
  final int ayah;

  /// Word index within the ayah.
  final int word;
  final String expected;

  /// Reading notes: `wrong`, `skipped` or `hinted`. Tajweed notes (Plus):
  /// `shortMadd` or `endingVowel`.
  final String kind;

  /// What was heard (wrong words), or the note's text (tajweed notes).
  final String? heard;
  final DateTime at;

  bool get isTajweed => kind == 'shortMadd' || kind == 'endingVowel';

  String get description => switch (kind) {
        'wrong' => 'سُمِعَت «${heard ?? ''}»',
        'skipped' => 'لم تُقرأ',
        'hinted' => 'بمساعدة تلميح',
        _ => heard ?? '',
      };

  Map<String, dynamic> toJson() => {
        's': surah,
        'a': ayah,
        'w': word,
        'e': expected,
        'k': kind,
        if (heard != null) 'h': heard,
        't': at.millisecondsSinceEpoch,
      };
}

class AyahProgress {
  AyahProgress({this.attempts = 0, this.cleanAttempts = 0, this.lastAccuracy = 0});

  factory AyahProgress.fromJson(List<dynamic> j) =>
      AyahProgress(attempts: j[0] as int, cleanAttempts: j[1] as int, lastAccuracy: (j[2] as num).toDouble());

  int attempts;

  /// Attempts without a single mistake.
  int cleanAttempts;
  double lastAccuracy;

  List<dynamic> toJson() => [attempts, cleanAttempts, double.parse(lastAccuracy.toStringAsFixed(3))];
}

/// Persistent recitation history: per-ayah progress, daily activity and
/// recent mistakes.
class ProgressStore extends ChangeNotifier {
  ProgressStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      (j['ayahs'] as Map<String, dynamic>).forEach((k, v) => _ayahs[k] = AyahProgress.fromJson(v as List));
      (j['days'] as Map<String, dynamic>).forEach((k, v) => _dailyWords[k] = v as int);
      _mistakes.addAll([for (final m in j['mistakes'] as List) MistakeRecord.fromJson(m as Map<String, dynamic>)]);
    }
  }

  static const _key = 'progress.v1';
  static const maxMistakes = 300;

  final SharedPreferences _prefs;
  final Map<String, AyahProgress> _ayahs = {};
  final Map<String, int> _dailyWords = {};
  final List<MistakeRecord> _mistakes = [];

  static Future<ProgressStore> load() async => ProgressStore(await SharedPreferences.getInstance());

  static String _ayahKey(int surah, int ayah) => '$surah:$ayah';
  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  AyahProgress? ayah(int surah, int ayah) => _ayahs[_ayahKey(surah, ayah)];

  /// Number of distinct ayahs of [surah] recited at least once.
  int recitedAyahsIn(int surah) => _ayahs.keys.where((k) => k.startsWith('$surah:')).length;

  /// Ayahs whose last recitation was flawless.
  int get masteredAyahs => _ayahs.values.where((p) => p.lastAccuracy >= 1).length;

  int get recitedAyahs => _ayahs.length;

  int wordsOn(DateTime day) => _dailyWords[_dayKey(day)] ?? 0;

  int get totalWords => _dailyWords.values.fold(0, (a, b) => a + b);

  /// Consecutive days with activity, ending today (or yesterday, so a streak
  /// isn't shown as broken before today's session).
  int streak({DateTime? now}) {
    var day = now ?? DateTime.now();
    if (wordsOn(day) == 0) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (wordsOn(day) > 0) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  List<MistakeRecord> get recentMistakes => List.unmodifiable(_mistakes.reversed);

  void recordSession({
    required List<AyahAttempt> ayahs,
    required List<MistakeRecord> mistakes,
    required int wordsRecited,
    DateTime? at,
  }) {
    if (wordsRecited == 0) return;
    for (final a in ayahs) {
      final p = _ayahs.putIfAbsent(_ayahKey(a.surah, a.ayah), AyahProgress.new);
      p.attempts++;
      if (a.mistakes == 0) p.cleanAttempts++;
      p.lastAccuracy = a.words == 0 ? 1 : (a.words - a.mistakes) / a.words;
    }
    final day = _dayKey(at ?? DateTime.now());
    _dailyWords[day] = (_dailyWords[day] ?? 0) + wordsRecited;
    _mistakes.addAll(mistakes);
    if (_mistakes.length > maxMistakes) _mistakes.removeRange(0, _mistakes.length - maxMistakes);
    _save();
  }

  void reset() {
    _ayahs.clear();
    _dailyWords.clear();
    _mistakes.clear();
    _save();
  }

  void _save() {
    _prefs.setString(
      _key,
      jsonEncode({
        'ayahs': {for (final e in _ayahs.entries) e.key: e.value.toJson()},
        'days': _dailyWords,
        'mistakes': [for (final m in _mistakes) m.toJson()],
      }),
    );
    notifyListeners();
  }
}
