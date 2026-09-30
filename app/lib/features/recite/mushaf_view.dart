import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/mushaf_layout.dart';
import '../../ui/theme.dart';
import 'ayah_margin_sheet.dart';
import 'recite_controller.dart';
import 'word_style.dart';

/// The recited surah on Madinah Mushaf pages: 15 lines a page with the
/// printed mushaf's line breaks, lines justified edge to edge, swiped like a
/// book. Follows the reciter from page to page.
class MushafView extends StatefulWidget {
  const MushafView({
    super.key,
    required this.controller,
    required this.layout,
    required this.initialAyah,
    required this.onAyahTap,
    this.playingAyah,
  });

  final ReciteController controller;
  final MushafLayout layout;
  final int initialAyah;
  final ValueChanged<int> onAyahTap;

  /// Ayah being played by the reciter audio, followed like recitation.
  final int? playingAyah;

  @override
  State<MushafView> createState() => MushafViewState();
}

class MushafViewState extends State<MushafView> {
  late final int _first;
  late final int _last;
  late final PageController _pages;

  ReciteController get _c => widget.controller;
  int get _surah => _c.surah.number;

  @override
  void initState() {
    super.initState();
    _first = widget.layout.pageOf(_surah, 1);
    _last = widget.layout.pageOf(_surah, _c.surah.ayahCount);
    _pages = PageController(initialPage: widget.layout.pageOf(_surah, widget.initialAyah) - _first);
    _c.addListener(_follow);
  }

  @override
  void didUpdateWidget(MushafView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playingAyah != null && widget.playingAyah != oldWidget.playingAyah) showAyah(widget.playingAyah!);
  }

  void _follow() {
    if (_c.isListening) showAyah(_c.currentAyah);
  }

  /// Turns to the page holding [ayah].
  void showAyah(int ayah) {
    if (!_pages.hasClients) return;
    final target = widget.layout.pageOf(_surah, ayah) - _first;
    if (target != _pages.page?.round()) {
      _pages.animateToPage(target, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_follow);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pages,
      itemCount: _last - _first + 1,
      itemBuilder: (context, k) => _MushafPage(
        page: _first + k,
        lines: widget.layout.pages[_first + k],
        controller: _c,
        onAyahTap: widget.onAyahTap,
      ),
    );
  }
}

class _MushafPage extends StatelessWidget {
  const _MushafPage({required this.page, required this.lines, required this.controller, required this.onAyahTap});

  /// 0-based page index.
  final int page;
  final List<MushafLine> lines;
  final ReciteController controller;
  final ValueChanged<int> onAyahTap;

  static const _fontFamily = 'AmiriQuran';
  static const _marginWidth = 26.0;

  // Word widths at font size 100, shared across pages.
  static final Map<String, double> _widthCache = {};

  static double _width(String text) => _widthCache.putIfAbsent(text, () {
        final painter = TextPainter(
          text: TextSpan(text: text, style: const TextStyle(fontFamily: _fontFamily, fontSize: 100)),
          textDirection: TextDirection.rtl,
        )..layout();
        return painter.width;
      });

  /// Space between words on the centered opening pages, per font size.
  static const _centeredGap = 0.3;

  /// One font size for the whole page, so its longest line just fits.
  double _fontSize(List<List<(String, InlineSpan, int?)>> tokens, double width, double lineHeight,
      {required bool centered}) {
    // Justified lines need at least a third of the font size between words;
    // centered ones get [_centeredGap].
    final gap = centered ? 100 * _centeredGap : 33;
    var widest = 0.0;
    for (final line in tokens) {
      if (line.isEmpty) continue;
      final natural = line.fold<double>(0, (s, t) => s + _width(t.$1)) + gap * (line.length - 1);
      widest = math.max(widest, natural);
    }
    // A little slack for glyphs that overhang their advance width.
    final byWidth = widest == 0 ? 30.0 : 0.97 * 100 * width / widest;
    return math.min(byWidth, lineHeight / 1.75);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final quran = services.quran;
    final styler = WordStyler(context, controller, services.settings);
    final scheme = Theme.of(context).colorScheme;
    final surah = controller.surah.number;
    // Pages 1 and 2 (al-Fatiha, start of al-Baqarah) are centered, not
    // justified, as in the printed mushaf.
    final centered = page < 2;

    // (plain text for measuring, span to draw, ayah to open on tap)
    final tokens = <List<(String, InlineSpan, int?)>>[];
    for (final line in lines) {
      final row = <(String, InlineSpan, int?)>[];
      for (final seg in line.segments) {
        final mine = seg.surah == surah;
        if (seg.hasWords) {
          final other = mine ? null : quran.ayahWords(seg.surah, seg.ayah, withTajweed: false);
          for (var w = seg.first; w <= seg.last; w++) {
            if (mine) {
              final i = controller.wordIndex(seg.ayah, w);
              if (i < 0) continue;
              row.add((controller.words[i].text, styler.span(i), seg.ayah));
            } else if (w < other!.length) {
              row.add((other[w].text, styler.otherSurahSpan(other[w].text), null));
            }
          }
        }
        if (seg.endsAyah) {
          row.add(('﴿${arabicNumber(seg.ayah)}﴾', styler.ayahMarker(seg.ayah, otherSurah: !mine), mine ? seg.ayah : null));
        }
      }
      tokens.add(row);
    }

    return LayoutBuilder(builder: (context, box) {
      const padding = EdgeInsets.fromLTRB(10, 6, 4, 4);
      const footer = 22.0;
      final lineHeight = (box.maxHeight - padding.vertical - footer) / MushafLayout.linesPerPage;
      final textWidth = box.maxWidth - padding.horizontal - _marginWidth;
      final fontSize = _fontSize(tokens, textWidth, lineHeight, centered: centered);
      final wordStyle = TextStyle(fontFamily: _fontFamily, fontSize: fontSize, height: 1.0, color: scheme.onSurface);

      Widget lineWidget(int l) {
        final line = lines[l];
        switch (line.kind) {
          case MushafLineKind.surahTitle:
            return _SurahTitle(name: quran.surah(line.titleSurah!).name, height: lineHeight);
          case MushafLineKind.basmala:
            return Center(
              child: Text('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ', style: wordStyle),
            );
          case MushafLineKind.blank:
            return const SizedBox.shrink();
          case MushafLineKind.text:
            final row = tokens[l];
            return Row(
              mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                for (final (_, span, ayah) in row)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: centered ? fontSize * _centeredGap / 2 : 0),
                    child: GestureDetector(
                      onTap: ayah == null ? null : () => onAyahTap(ayah),
                      child: Text.rich(span, style: wordStyle, textScaler: TextScaler.noScaling, maxLines: 1),
                    ),
                  ),
              ],
            );
        }
      }

      Widget margin(int l) {
        // Notes of the ayahs that end on this line.
        var reading = 0, tajweed = 0;
        int? ayah;
        for (final seg in lines[l].segments) {
          if (seg.surah != surah || !seg.endsAyah) continue;
          final n = controller.marginNotes(seg.ayah);
          reading += n.reading;
          tajweed += n.tajweed;
          ayah ??= seg.ayah;
        }
        final notes = MarginNotes(reading, tajweed);
        if (notes.isEmpty || ayah == null) return const SizedBox(width: _marginWidth);
        return SizedBox(
          width: _marginWidth,
          child: FittedBox(fit: BoxFit.scaleDown, child: MarginMarker(notes: notes, onTap: () => onAyahTap(ayah!))),
        );
      }

      // The opening pages hold fewer lines, centered on the page.
      final shown = [
        for (var l = 0; l < lines.length; l++)
          if (!centered || lines[l].kind != MushafLineKind.blank) l,
      ];
      return Padding(
        padding: padding,
        child: Column(
          children: [
            if (centered) const Spacer(),
            for (final l in shown)
              SizedBox(
                height: lineHeight,
                child: Row(children: [Expanded(child: Center(child: lineWidget(l))), margin(l)]),
              ),
            if (centered) const Spacer(),
            SizedBox(
              height: footer,
              child: Center(
                child: Text(arabicNumber(page + 1), style: TextStyle(color: scheme.outline, fontSize: 13)),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _SurahTitle extends StatelessWidget {
  const _SurahTitle({required this.name, required this.height});

  final String name;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height * 0.86,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary.withValues(alpha: 0.6), width: 1.2),
        borderRadius: BorderRadius.circular(8),
        color: scheme.primaryContainer.withValues(alpha: 0.25),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('سُورَةُ $name',
            style: TextStyle(fontFamily: 'AmiriQuran', fontSize: height * 0.5, color: scheme.primary, height: 1.2)),
      ),
    );
  }
}
