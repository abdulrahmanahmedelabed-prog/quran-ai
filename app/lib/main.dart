import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'billing/subscription.dart';
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
  final services = AppServices(
    quran: Quran.fromJson(json),
    settings: settings,
    progress: progress,
    subscription: subscription,
  );
  runApp(QuranAiApp(services: services));
  // Prices load in the background; the paywall shows them once ready.
  unawaited(subscription.init());
}

class QuranAiApp extends StatelessWidget {
  const QuranAiApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'تلاوة',
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
