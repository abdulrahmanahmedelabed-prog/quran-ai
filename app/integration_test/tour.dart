// A scripted walk through the main screens, used to screenshot the app on
// emulators and simulators. Recognition is replaced by a scripted transcript
// so the tour runs without a microphone or a server.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/app_scope.dart';
import 'package:quran_ai/asr/engine.dart';
import 'package:quran_ai/billing/subscription.dart';
import 'package:quran_ai/core/recitation_review.dart';
import 'package:quran_ai/data/progress.dart';
import 'package:quran_ai/data/quran.dart';
import 'package:quran_ai/data/settings.dart';
import 'package:quran_ai/features/recite/ayah_margin_sheet.dart';
import 'package:quran_ai/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScriptedEngine implements RecognitionEngine {
  ScriptedEngine(this.transcript, this.timedWords);

  final String transcript;
  final _transcripts = StreamController<String>.broadcast();

  @override
  final List<TimedWord> timedWords;

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Stream<double> get levels => const Stream.empty();

  @override
  Future<void> start() async {}

  /// Emits the first [words] words of the transcript, as if heard so far.
  void hear(int words) => _transcripts.add(transcript.split(' ').take(words).join(' '));

  @override
  Future<String> stop() async => transcript;

  @override
  Future<void> dispose() => _transcripts.close();
}

/// Builds services for a Plus subscriber reciting the start of al-Baqarah
/// with one wrong word and a shortened madd.
Future<(AppServices, ScriptedEngine)> tourServices() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setString('tier', Tier.plus.name);
  final quran = Quran.fromJson(await rootBundle.loadString('assets/quran/quran_uthmani.json'));
  final said = [for (final w in quran.wordsOf(2, toAyah: 5)) w.normalized];
  said[11] = 'ويقولون'; // وَيُقِيمُونَ (2:3) misread
  // An even pace per letter makes every checked madd sound short.
  var t = 0.0;
  final timed = <TimedWord>[];
  for (final w in said) {
    final d = w.length * 0.12;
    timed.add(TimedWord(w, t, t + d));
    t += d + 0.05;
  }
  final engine = ScriptedEngine(said.join(' '), timed);
  final services = AppServices(
    quran: quran,
    settings: AppSettings(prefs),
    progress: ProgressStore(prefs),
    subscription: SubscriptionService(prefs),
    engineFactory: () => engine,
  );
  return (services, engine);
}

/// Walks through the app, calling [shot] at each screen. [settle] lets
/// animations and async work finish.
Future<void> runTour(
  WidgetTester tester, {
  required (AppServices, ScriptedEngine) setup,
  required Future<void> Function(String name) shot,
  required Future<void> Function() settle,
  bool visitPaywall = true,
}) async {
  final (services, engine) = setup;
  await tester.pumpWidget(QuranAiApp(services: services));
  await settle();
  await shot('01_home');

  await tester.tap(find.text('سورة البقرة'));
  await settle();
  await tester.tap(find.byIcon(Icons.mic));
  await settle();
  engine.hear(20);
  await settle();
  engine.hear(24);
  await settle();
  await shot('02_reciting');

  await tester.tap(find.byIcon(Icons.stop_rounded));
  await settle();
  await shot('03_summary');

  await tester.ensureVisible(find.text('متابعة'));
  await settle();
  await tester.tap(find.text('متابعة'));
  await settle();
  await shot('04_margin');

  final marker = find.byType(MarginMarker).first;
  await tester.ensureVisible(marker);
  await settle();
  await tester.tap(marker);
  await settle();
  expect(find.byType(AyahMarginSheet), findsOneWidget);
  await shot('05_margin_sheet');

  if (!visitPaywall) return;
  Navigator.of(tester.element(find.byType(AyahMarginSheet))).pop();
  await settle();
  await tester.pageBack();
  await settle();
  await tester.tap(find.text('الإعدادات'));
  await settle();
  await tester.tap(find.textContaining('باقتك'));
  await settle();
  await shot('06_paywall');
}
