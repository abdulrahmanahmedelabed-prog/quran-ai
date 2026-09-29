import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/app_scope.dart';
import 'package:quran_ai/asr/engine.dart';
import 'package:quran_ai/data/progress.dart';
import 'package:quran_ai/data/quran.dart';
import 'package:quran_ai/data/settings.dart';
import 'package:quran_ai/features/recite/recite_controller.dart';
import 'package:quran_ai/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays back a scripted transcript instead of using the microphone.
class FakeEngine implements RecognitionEngine {
  FakeEngine(this.script);

  final List<String> script;
  final _transcripts = StreamController<String>.broadcast();

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Stream<double> get levels => const Stream.empty();

  @override
  Future<void> start() async {}

  /// Emits the next scripted transcript.
  void emit(int i) => _transcripts.add(script[i]);

  @override
  Future<String> stop() async => script.last;

  @override
  Future<void> dispose() => _transcripts.close();
}

void main() {
  final quran = Quran.fromJson(File('assets/quran/quran_uthmani.json').readAsStringSync());

  Future<AppServices> makeServices({FakeEngine? engine}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return AppServices(
      quran: quran,
      settings: AppSettings(prefs),
      progress: ProgressStore(prefs),
      engineFactory: engine == null ? null : () => engine,
    );
  }

  test('a recitation session records progress and mistakes', () async {
    final engine = FakeEngine([
      'قل هو الله احد',
      'قل هو الله احد الله الصمد لم يلد ولم يولد',
      'قل هو الله احد الله الصمد لم يلد ولم يولد ولم يكن له كفوا احمد',
    ]);
    final services = await makeServices(engine: engine);
    final c = ReciteController(services: services, surah: quran.surah(112));
    await c.start();
    expect(c.isListening, isTrue);
    engine.emit(0);
    engine.emit(1);
    await Future<void>.delayed(Duration.zero);
    expect(c.position, greaterThan(4));

    final result = (await c.stop())!;
    expect(result.stats.wrong, 1);
    expect(result.mistakes.single.heard, 'احمد');
    expect(result.ayahsCompleted, 4);
    expect(services.progress.recitedAyahsIn(112), 4);
    expect(services.progress.ayah(112, 4)!.lastAccuracy, lessThan(1));
    expect(services.progress.ayah(112, 1)!.lastAccuracy, 1);
    expect(services.progress.streak(), 1);
    c.dispose();
  });

  testWidgets('app opens a surah and shows its text', (tester) async {
    final services = await makeServices();
    await tester.pumpWidget(QuranAiApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('سورة الفاتحة'), findsOneWidget);

    await tester.tap(find.text('سورة الفاتحة'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.textContaining('ٱلۡحَمۡدُ', findRichText: true), findsOneWidget);
  });
}
