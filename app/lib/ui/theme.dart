import 'package:flutter/material.dart';

import '../core/recitation_tracker.dart';

const _seed = Color(0xFF0F766E);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Amiri',
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFFBF8F1) : scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Amiri',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Colors for word states in the mushaf view.
class WordColors {
  const WordColors._(this.correct, this.wrong, this.skipped, this.hinted, this.current);

  factory WordColors.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const WordColors._(Color(0xFF5EEAD4), Color(0xFFF87171), Color(0xFFFBBF24), Color(0xFFC4B5FD), Color(0x3314B8A6))
        : const WordColors._(Color(0xFF0F766E), Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF7C3AED), Color(0x2214B8A6));
  }

  final Color correct;
  final Color wrong;
  final Color skipped;
  final Color hinted;

  /// Background behind the word the reciter is expected to say next.
  final Color current;

  Color? forStatus(WordStatus status) => switch (status) {
        WordStatus.correct => correct,
        WordStatus.wrong => wrong,
        WordStatus.skipped => skipped,
        WordStatus.hinted => hinted,
        WordStatus.pending => null,
      };
}

/// Arabic-Indic digits for ayah numbers.
String arabicNumber(int n) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return n.toString().split('').map((d) => digits[int.parse(d)]).join();
}
