import 'package:flutter/widgets.dart';

import 'asr/engine.dart';
import 'asr/on_device_engine.dart';
import 'asr/server_engine.dart';
import 'core/ayah_search.dart';
import 'data/progress.dart';
import 'data/quran.dart';
import 'data/settings.dart';

/// App-wide services, available to every widget via [AppScope.of].
class AppServices {
  AppServices({required this.quran, required this.settings, required this.progress, this.engineFactory});

  final Quran quran;
  final AppSettings settings;
  final ProgressStore progress;

  /// Overrides engine creation (used by tests).
  final RecognitionEngine Function()? engineFactory;

  AyahSearchIndex? _searchIndex;

  /// Built on first use (~77k words), then cached.
  AyahSearchIndex get searchIndex => _searchIndex ??= AyahSearchIndex([
        for (final w in quran.allWords()) IndexedWord(w.surah, w.ayah, w.indexInAyah, w.forms),
      ]);

  ModelManager get modelManager => ModelManager(modelUrl: settings.modelUrl);

  RecognitionEngine createEngine() =>
      engineFactory?.call() ??
      switch (settings.engine) {
        EngineKind.server => ServerEngine(baseUrl: settings.serverUrl, apiKey: settings.apiKey),
        EngineKind.onDevice => OnDeviceEngine(models: modelManager),
      };
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
