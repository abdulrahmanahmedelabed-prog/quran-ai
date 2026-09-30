import 'dart:convert';

/// A run of consecutive words of one ayah on one line of the mushaf.
class MushafSegment {
  const MushafSegment(this.surah, this.ayah, this.first, this.last, this.endsAyah);

  final int surah;
  final int ayah;

  /// Word indices within the ayah, inclusive; -1 when the line holds only
  /// the ayah's end marker.
  final int first;
  final int last;

  /// Whether the ayah's end marker is on this line.
  final bool endsAyah;

  bool get hasWords => first >= 0;
}

enum MushafLineKind { text, surahTitle, basmala, blank }

class MushafLine {
  const MushafLine(this.kind, this.segments, {this.titleSurah});

  final MushafLineKind kind;
  final List<MushafSegment> segments;

  /// The surah a title or basmala line introduces.
  final int? titleSurah;
}

/// The Madinah Mushaf (Hafs) page layout: 604 pages of 15 lines, with the
/// same words on each line as the printed mushaf.
class MushafLayout {
  MushafLayout(this.pages) {
    for (var p = 0; p < pages.length; p++) {
      for (final line in pages[p]) {
        for (final s in line.segments) {
          _firstPage.putIfAbsent(s.surah * 1000 + s.ayah, () => p);
        }
      }
    }
  }

  static const pageCount = 604;
  static const linesPerPage = 15;

  /// Lines of each page (index 0 = page 1).
  final List<List<MushafLine>> pages;
  final Map<int, int> _firstPage = {};

  /// Page index (0-based) where [ayah] of [surah] starts.
  int pageOf(int surah, int ayah) => _firstPage[surah * 1000 + ayah] ?? 0;

  factory MushafLayout.fromJson(String json) {
    final raw = (jsonDecode(json) as Map<String, dynamic>)['pages'] as List;
    final segs = [
      for (final page in raw)
        [
          for (final line in page as List)
            [
              for (final s in line as List)
                MushafSegment(s[0] as int, s[1] as int, s[2] as int, s[3] as int, s[4] == 1),
            ],
        ],
    ];
    return MushafLayout(_classify(segs));
  }

  /// Names the lines without words: the one or two empty lines right before
  /// a surah's first word hold its title and (except al-Fatiha and at-Tawba,
  /// and where there's room) the basmala.
  static List<List<MushafLine>> _classify(List<List<List<MushafSegment>>> pages) {
    final flat = <(int, int)>[];
    for (var p = 0; p < pages.length; p++) {
      for (var l = 0; l < pages[p].length; l++) {
        flat.add((p, l));
      }
    }
    final kinds = <(int, int), (MushafLineKind, int?)>{};
    for (var k = 0; k < flat.length; k++) {
      final (p, l) = flat[k];
      final segs = pages[p][l];
      if (segs.isEmpty) continue;
      final first = segs.first;
      if (first.ayah != 1 || first.first != 0) continue;
      // Empty lines just before this surah start.
      final hasBasmala = first.surah != 1 && first.surah != 9;
      final before = <(int, int)>[];
      for (var j = k - 1; j >= 0 && before.length < 2; j--) {
        final (pp, ll) = flat[j];
        if (pages[pp][ll].isNotEmpty) break;
        before.add(flat[j]);
      }
      if (before.isEmpty) continue;
      if (hasBasmala && before.length == 2) {
        kinds[before[0]] = (MushafLineKind.basmala, first.surah);
        kinds[before[1]] = (MushafLineKind.surahTitle, first.surah);
      } else {
        kinds[before[0]] = (MushafLineKind.surahTitle, first.surah);
      }
    }
    return [
      for (var p = 0; p < pages.length; p++)
        [
          for (var l = 0; l < pages[p].length; l++)
            if (pages[p][l].isNotEmpty)
              MushafLine(MushafLineKind.text, pages[p][l])
            else
              switch (kinds[(p, l)]) {
                (final kind, final surah) => MushafLine(kind, const [], titleSurah: surah),
                null => const MushafLine(MushafLineKind.blank, []),
              },
        ],
    ];
  }
}
