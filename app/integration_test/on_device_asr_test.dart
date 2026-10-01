// Runs the real on-device recognizer on an emulator: downloads the Quran
// model as the app does, loads it with whisper.cpp and transcribes recited
// al-Ikhlas served by the CI host (ASR_PCM_URL, 16 kHz mono PCM16).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:quran_ai/asr/on_device_engine.dart';
import 'package:quran_ai/core/arabic.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

const pcmUrl = String.fromEnvironment('ASR_PCM_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Quran model loads and recognizes al-Ikhlas', (tester) async {
    final clock = Stopwatch()..start();
    final path = await ModelManager(modelUrl: '').ensure();
    // ignore: avoid_print
    print('ASR model ready after ${clock.elapsed}: ${File(path).lengthSync()} bytes');

    clock.reset();
    final session = await startWhisperLiveSession(
      modelPath: path,
      lang: 'ar',
      suppressNonSpeechTokens: true,
      keepModelLoaded: true,
    ).timeout(OnDeviceEngine.loadTimeout);
    // ignore: avoid_print
    print('ASR model loaded in ${clock.elapsed}');

    final pcm = (await http.get(Uri.parse(pcmUrl))).bodyBytes;
    // ignore: avoid_print
    session.partials.listen((text) => print('ASR partial at ${clock.elapsed}: $text'));
    clock.reset();
    // 100 ms chunks at the pace of the microphone.
    for (var i = 0; i < pcm.length; i += 3200) {
      session.feed(pcm.sublist(i, (i + 3200).clamp(0, pcm.length)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('ASR audio fed in ${clock.elapsed}');
    final text = await session.stop().timeout(const Duration(minutes: 3));
    // ignore: avoid_print
    print('ASR final after ${clock.elapsed}: $text');
    final heard = skeleton(normalizeArabic(text));
    for (final word in ['أحد', 'الصمد', 'يولد', 'كفوا']) {
      expect(heard, contains(skeleton(normalizeArabic(word))));
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
