import 'dart:isolate';

import 'package:flutter/widgets.dart';

import 'asr/engine.dart';
import 'asr/on_device_engine.dart';
import 'asr/server_engine.dart';
import 'billing/subscription.dart';
import 'core/ayah_search.dart';
import 'data/mushaf_layout.dart';
import 'data/progress.dart';
import 'data/quran.dart';
import 'data/settings.dart';

/// App-wide services, available to every widget via [AppScope.of].
class AppServices {
  AppServices({
    required this.quran,
    required this.settings,
    required this.progress,
    required this.subscription,
    this.mushaf,
    this.engineFactory,
  });

  final Quran quran;
  final AppSettings settings;
  final ProgressStore progress;
  final SubscriptionService subscription;

  /// Madinah Mushaf page layout, when bundled.
  final MushafLayout? mushaf;

  /// Overrides engine creation (used by tests).
  final RecognitionEngine Function()? engineFactory;

  Future<AyahSearchIndex>? _searchIndex;

  /// Built on first use (~77k words) in a background isolate so the UI stays
  /// responsive on slower phones, then cached.
  Future<AyahSearchIndex> get searchIndex => _searchIndex ??= _buildSearchIndex(quran);

  // Static so the isolate closure captures only [quran], not these services
  // (which hold unsendable objects).
  static Future<AyahSearchIndex> _buildSearchIndex(Quran quran) => Isolate.run(() => AyahSearchIndex([
        for (final w in quran.allWords(withTajweed: false)) IndexedWord(w.surah, w.ayah, w.indexInAyah, w.forms),
      ]));

  ModelManager get modelManager => ModelManager(modelUrl: settings.modelUrl);

  /// [onModelProgress] reports the on-device model's first download, and
  /// [onModelLoading] when it is then loaded into memory.
  RecognitionEngine createEngine({void Function(double?)? onModelProgress, VoidCallback? onModelLoading}) =>
      engineFactory?.call() ??
      switch (settings.engine) {
        EngineKind.server => ServerEngine(baseUrl: settings.serverUrl, apiKey: settings.apiKey),
        EngineKind.onDevice =>
          OnDeviceEngine(models: modelManager, onModelProgress: onModelProgress, onModelLoading: onModelLoading),
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
