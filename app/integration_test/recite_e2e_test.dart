// End to end on an Android emulator:
// 1. the real microphone opens and streams audio (permission granted by the
//    CI script);
// 2. the whole app follows a real recitation: al-Minshawi reciting al-Ikhlas
//    (ASR_PCM_URL, 16 kHz mono PCM16) is played in at the microphone layer,
//    recognized on the device, tracked on the mushaf page, and the session
//    ends with every word read and no note.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:quran_ai/app_scope.dart';
import 'package:quran_ai/asr/engine.dart';
import 'package:quran_ai/billing/subscription.dart';
import 'package:quran_ai/data/mushaf_layout.dart';
import 'package:quran_ai/data/progress.dart';
import 'package:quran_ai/data/quran.dart';
import 'package:quran_ai/data/settings.dart';
import 'package:quran_ai/features/home/home_page.dart';
import 'package:quran_ai/features/recite/recite_page.dart';
import 'package:quran_ai/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pcmUrl = String.fromEnvironment('ASR_PCM_URL');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the microphone streams audio', (tester) async {
    final mic = Microphone();
    await mic.ensurePermission().timeout(const Duration(seconds: 20));
    var bytes = 0;
    final sub = (await mic.start()).listen((chunk) => bytes += chunk.length);
    await Future<void>.delayed(const Duration(seconds: 2));
    await sub.cancel();
    await mic.dispose();
    // ignore: avoid_print
    print('E2E microphone: $bytes bytes in 2 s');
    expect(bytes, greaterThan(Microphone.sampleRate)); // over 0.5 s of audio
  });

  testWidgets('the app follows a recitation of al-Ikhlas', (tester) async {
    final pcm = (await http.get(Uri.parse(pcmUrl))).bodyBytes;
    Microphone.debugAudioSource = () async* {
      // 100 ms chunks at the pace of a real microphone.
      for (var i = 0; i < pcm.length; i += 3200) {
        yield Uint8List.sublistView(pcm, i, (i + 3200).clamp(0, pcm.length));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // Then silence, as when the reciter stops.
      while (true) {
        yield Uint8List(3200);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    };
    addTearDown(() => Microphone.debugAudioSource = null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('tier', Tier.plus.name);
    final quran = Quran.fromJson(await rootBundle.loadString('assets/quran/quran_uthmani.json'));
    final services = AppServices(
      quran: quran,
      settings: AppSettings(prefs),
      progress: ProgressStore(prefs),
      subscription: SubscriptionService(prefs),
      mushaf: MushafLayout.fromJson(await rootBundle.loadString('assets/quran/mushaf_madani.json')),
    );

    Future<void> wait(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      }
    }

    Future<void> waitFor(Finder finder, Duration timeout) async {
      final end = DateTime.now().add(timeout);
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $finder');
        await wait(const Duration(milliseconds: 400));
      }
    }

    await tester.pumpWidget(QuranAiApp(services: services));
    await wait(const Duration(seconds: 1));
    Navigator.of(tester.element(find.byType(HomePage)))
        .push(MaterialPageRoute<void>(builder: (_) => RecitePage(surah: quran.surah(112))));
    await wait(const Duration(seconds: 1));

    final clock = Stopwatch()..start();
    await tester.tap(find.byIcon(Icons.mic));
    // Downloads the model on a fresh install, then listens.
    await waitFor(find.byIcon(Icons.stop_rounded), const Duration(minutes: 4));
    // ignore: avoid_print
    print('E2E listening after ${clock.elapsed}');
    clock.reset();

    await binding.convertFlutterSurfaceToImage();
    await wait(const Duration(seconds: 9));
    await binding.takeScreenshot('07_live_recitation');
    // The recitation is 14 s; leave time for the last ayah's final decode.
    await wait(const Duration(seconds: 9));
    await binding.takeScreenshot('08_live_recitation_done');

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await waitFor(find.text('كلمة قرأتها'), const Duration(minutes: 1));
    await wait(const Duration(seconds: 1));
    await binding.takeScreenshot('09_live_summary');
    // ignore: avoid_print
    print('E2E summary shown after ${clock.elapsed}');
    expect(find.text('ما شاء الله! قراءة بلا ملاحظات'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
