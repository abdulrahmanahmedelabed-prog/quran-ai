/// Finds where in the Quran a recited passage comes from.
library;

import 'dart:math' as math;

import 'alignment.dart';
import 'arabic.dart';

class IndexedWord {
  const IndexedWord(this.surah, this.ayah, this.indexInAyah, this.forms);

  final int surah;
  final int ayah;
  final int indexInAyah;
  final List<String> forms;
}

class SearchHit {
  const SearchHit({
    required this.surah,
    required this.ayah,
    required this.wordIndex,
    required this.globalIndex,
    required this.score,
  });

  final int surah;
  final int ayah;

  /// Index within the ayah of the first matched word.
  final int wordIndex;

  /// Index of the first matched word in the whole-Quran word sequence.
  final int globalIndex;

  /// Matched share of the query in [0, 1].
  final double score;
}

class AyahSearchIndex {
  AyahSearchIndex(Iterable<IndexedWord> words) : _words = List.unmodifiable(words) {
    for (var p = 0; p < _words.length; p++) {
      final key = skeleton(_words[p].forms.first);
      (_postings[key] ??= <int>[]).add(p);
    }
  }

  final List<IndexedWord> _words;
  final Map<String, List<int>> _postings = {};

  int get wordCount => _words.length;
  IndexedWord wordAt(int globalIndex) => _words[globalIndex];

  /// Returns the best matching passages for [transcript], best first, at most
  /// one hit per ayah.
  List<SearchHit> search(
    String transcript, {
    int limit = 5,
    int candidates = 25,
    double minScore = 0.6,
    AlignerConfig config = const AlignerConfig(),
  }) {
    final query = normalizeWords(transcript);
    if (query.isEmpty) return const [];

    // 1. Vote for start positions using exact skeleton matches weighted by
    //    rarity, so common words (الله, من) count little.
    final n = _words.length.toDouble();
    final votes = <int, double>{};
    for (var k = 0; k < query.length; k++) {
      final posting = _postings[skeleton(query[k])];
      if (posting == null) continue;
      final idf = math.log(n / posting.length);
      for (final p in posting) {
        final start = p - k;
        votes[start] = (votes[start] ?? 0) + idf;
      }
    }
    if (votes.isEmpty) return const [];
    final ranked = votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // 2. Verify the best candidates with fuzzy alignment, which tolerates
    //    recognition errors, merged words and repetitions.
    final hits = <SearchHit>[];
    final seenAyahs = <int>{};
    for (final c in ranked.take(candidates)) {
      final from = math.max(0, c.key - 3);
      final to = math.min(_words.length, c.key + query.length * 2 + 5);
      final window = [for (var p = from; p < to; p++) _words[p].forms];
      final result = alignWords(window, query, config: config, freeLeadingSkips: true);
      final matched = result.matches.where((o) => o.similarity >= config.threshold);
      if (matched.isEmpty) continue;
      final heardMatched =
          matched.fold<int>(0, (sum, o) => sum + (o.heardEnd - o.heardStart));
      final score = heardMatched / query.length;
      if (score < minScore) continue;
      final first = from + matched.first.expected;
      final w = _words[first];
      final ayahKey = w.surah * 1000 + w.ayah;
      if (!seenAyahs.add(ayahKey)) continue;
      hits.add(SearchHit(
        surah: w.surah,
        ayah: w.ayah,
        wordIndex: w.indexInAyah,
        globalIndex: first,
        score: score,
      ));
    }
    // Stable sort: equal scores keep their vote ranking.
    final order = {for (var k = 0; k < hits.length; k++) hits[k]: k};
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : order[a]!.compareTo(order[b]!);
    });
    return hits.take(limit).toList();
  }
}
