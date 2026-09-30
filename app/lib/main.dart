import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'billing/subscription.dart';
import 'data/mushaf_layout.dart';
import 'data/progress.dart';
import 'data/quran.dart';
import 'data/settings.dart';
import 'features/home/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (json, settings, progress) = await (
    rootBundle.loadString('assets/quran/quran_uthmani.json'),
    AppSettings.load(),
    ProgressStore.load(),
  ).wait;
  final subscription = SubscriptionService(await SharedPreferences.getInstance());
  final mushaf = await _loadMushafLayout();
  final services = AppServices(
    // Parsed off the UI thread: 1.3 MB of JSON is slow on older phones.
    quran: await _parseQuran(json),
    settings: settings,
    progress: progress,
    subscription: subscription,
    mushaf: mushaf,
  );
  runApp(QuranAiApp(services: services));
  // Prices load in the background; the paywall shows them once ready.
  unawaited(subscription.init());
}

/// The Madinah Mushaf layout, or null if it isn't bundled.
Future<MushafLayout?> _loadMushafLayout() async {
  try {
    return await _parseMushaf(await rootBundle.loadString('assets/quran/mushaf_madani.json'));
  } catch (_) {
    return null;
  }
}

Future<MushafLayout> _parseMushaf(String json) => Isolate.run(() => MushafLayout.fromJson(json));

// A separate function so the isolate closure captures only [json].
Future<Quran> _parseQuran(String json) => Isolate.run(() => Quran.fromJson(json));

class QuranAiApp extends StatelessWidget {
  const QuranAiApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'قرآن AI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomePage(),
      ),
    );
  }
}
