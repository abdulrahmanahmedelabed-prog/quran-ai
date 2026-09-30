import 'package:flutter/material.dart';

import '../../core/recitation_tracker.dart';
import '../../data/quran.dart';
import '../../data/settings.dart';
import '../../ui/theme.dart';
import 'recite_controller.dart';

/// How a word of the recited surah looks: progress, hidden (memorization),
/// the next word, reading notes and tajweed colors. Shared by the continuous
/// view and the mushaf pages.
class WordStyler {
  WordStyler(BuildContext context, this.c, this.settings)
      : colors = WordColors.of(context),
        theme = Theme.of(context);

  final ReciteController c;
  final AppSettings settings;
  final WordColors colors;
  final ThemeData theme;

  ColorScheme get scheme => theme.colorScheme;

  bool get _showTajweed => c.tier.detectsTajweed && settings.tajweedColors;

  // Mistakes stay out of the text while reciting (they go to the margin),
  // unless the reader asked to see them live. Afterwards they get a quiet
  // dotted underline for review.
  bool get _markMistakes => c.tier.detectsMistakes && (settings.mistakesInText || !c.isListening);

  /// The span for word [i] of the controller's surah.
  InlineSpan span(int i) {
    final word = c.words[i];
    final state = c.tracker.stateOf(i);
    final hidden = c.hidden && state.status == WordStatus.pending && !c.peeked.contains(i);
    final isNext = c.isListening && i == c.position;
    final recited = state.status != WordStatus.pending;
    final mistake = state.status.isMistake;
    final mistakeColor = colors.forStatus(state.status);

    Color? base = recited ? colors.correct : scheme.onSurface;
    if (state.tentative) base = base.withValues(alpha: 0.7);
    if (mistake && _markMistakes && settings.mistakesInText) base = mistakeColor;
    final Color? background = hidden ? scheme.surfaceContainerHighest : (isNext ? colors.current : null);
    final style = TextStyle(
      color: hidden ? scheme.surfaceContainerHighest : base,
      backgroundColor: background,
      decoration: mistake && _markMistakes ? TextDecoration.underline : null,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: mistakeColor,
    );
    if (_showTajweed && !hidden && word.tajweed.isNotEmpty) {
      return TextSpan(style: style, children: tajweedSpans(word, theme.brightness));
    }
    return TextSpan(text: word.text, style: style);
  }

  /// A word of another surah sharing the page: shown quietly.
  InlineSpan otherSurahSpan(String text) =>
      TextSpan(text: text, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.45)));

  InlineSpan ayahMarker(int ayah, {bool otherSurah = false}) => TextSpan(
        text: '﴿${arabicNumber(ayah)}﴾',
        style: TextStyle(color: scheme.primary.withValues(alpha: otherSurah ? 0.45 : 1)),
      );
}

/// A word split into spans colored by tajweed rule.
List<InlineSpan> tajweedSpans(QuranWord word, Brightness brightness) {
  final marks = [...word.tajweed]..sort((a, b) => a.start.compareTo(b.start));
  final out = <InlineSpan>[];
  var at = 0;
  for (final m in marks) {
    if (m.start < at) continue;
    if (m.start > at) out.add(TextSpan(text: word.text.substring(at, m.start)));
    out.add(TextSpan(
      text: word.text.substring(m.start, m.end),
      style: TextStyle(color: tajweedColor(m.rule, brightness)),
    ));
    at = m.end;
  }
  if (at < word.text.length) out.add(TextSpan(text: word.text.substring(at)));
  return out;
}
