import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:quran_ai/app_scope.dart';
import 'package:quran_ai/asr/engine.dart';
import 'package:quran_ai/billing/subscription.dart';
import 'package:quran_ai/core/recitation_review.dart';
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
  List<TimedWord> timedWords = const [];

  @override
  Future<void> start() async {}

  /// Emits the next scripted transcript.
  void emit(int i) => _transcripts.add(script[i]);

  @override
  Future<String> stop() async => script.last;

  @override
  Future<void> dispose() => _transcripts.close();
}

/// In-memory store: every purchase succeeds.
class FakeStore implements InAppPurchase {
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();
  int completed = 0;

  void deliver(String productId, PurchaseStatus status) => _purchases.add([
        PurchaseDetails(
          productID: productId,
          verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'test'),
          transactionDate: '0',
          status: status,
        )..pendingCompletePurchase = true,
      ]);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchases.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async => ProductDetailsResponse(
        productDetails: [
          for (final id in identifiers)
            ProductDetails(id: id, title: id, description: '', price: '\$1', rawPrice: 1, currencyCode: 'USD'),
        ],
        notFoundIDs: const [],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    deliver(purchaseParam.productDetails.id, PurchaseStatus.purchased);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async => completed++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final quran = Quran.fromJson(File('assets/quran/quran_uthmani.json').readAsStringSync());

  Future<AppServices> makeServices({FakeEngine? engine, Tier tier = Tier.pro}) async {
    SharedPreferences.setMockInitialValues({'tier': tier.name});
    final prefs = await SharedPreferences.getInstance();
    return AppServices(
      quran: quran,
      settings: AppSettings(prefs),
      progress: ProgressStore(prefs),
      subscription: SubscriptionService(prefs),
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

  test('reading notes go to the margin (Pro); free tier sees progress only', () async {
    const said = 'قل هو الله احد الله الصمد لم يلد ولم يولد ولم يكن له كفوا احمد';
    for (final tier in [Tier.pro, Tier.free]) {
      final engine = FakeEngine([said]);
      final services = await makeServices(engine: engine, tier: tier);
      final c = ReciteController(services: services, surah: quran.surah(112));
      await c.start();
      final result = (await c.stop())!;
      expect(result.stats.recited, greaterThan(10));
      if (tier == Tier.pro) {
        expect(c.marginNotes(4).reading, 1);
        expect(c.marginNotes(1).isEmpty, isTrue);
        expect(result.mistakes, hasLength(1));
      } else {
        expect(c.marginNotes(4).isEmpty, isTrue);
        expect(result.mistakes, isEmpty);
        expect(services.progress.recentMistakes, isEmpty);
      }
      c.dispose();
    }
  });

  test('Plus reviews madd lengths from word timings', () async {
    final words = quran.wordsOf(1);
    // Every word at 0.12 s per letter: الضالين's six-count madd is cut short.
    var t = 0.0;
    final timed = <TimedWord>[];
    for (final w in words) {
      final d = w.normalized.length * 0.12;
      timed.add(TimedWord(w.normalized, t, t + d));
      t += d + 0.05;
    }
    final engine = FakeEngine([words.map((w) => w.normalized).join(' ')])..timedWords = timed;
    final services = await makeServices(engine: engine, tier: Tier.plus);
    final c = ReciteController(services: services, surah: quran.surah(1));
    await c.start();
    final result = (await c.stop())!;
    expect(result.tajweedNotes.single.kind, 'shortMadd');
    expect(c.marginNotes(7).tajweed, 1);
    expect(services.progress.recentMistakes.single.isTajweed, isTrue);
    c.dispose();
  });

  test('the search index builds in a background isolate', () async {
    final services = await makeServices();
    final index = await services.searchIndex;
    expect(index.search('قل هو الله احد الله الصمد').first.surah, 112);
    expect(identical(await services.searchIndex, index), isTrue);
  });

  test('owner account unlocks Plus and can preview other tiers', () async {
    SharedPreferences.setMockInitialValues({});
    final sub = SubscriptionService(await SharedPreferences.getInstance());
    expect(sub.unlockOwner('wrong-code'), isFalse);
    expect(sub.isOwner, isFalse);
    expect(sub.tier, Tier.free);

    SharedPreferences.setMockInitialValues({'owner': true});
    final owner = SubscriptionService(await SharedPreferences.getInstance());
    expect(owner.tier, Tier.plus);
    owner.setOwnerTier(Tier.free);
    expect(owner.tier, Tier.free);
    owner.signOutOwner();
    expect(owner.isOwner, isFalse);
  });

  test('a store purchase unlocks its tier', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeStore();
    final sub = SubscriptionService(await SharedPreferences.getInstance(), store: store);
    await sub.init();
    expect(sub.storeAvailable, isTrue);
    expect(sub.products, hasLength(plans.length));
    expect(sub.tier, Tier.free);

    await sub.buy(plans.firstWhere((p) => p.tier == Tier.plus));
    await Future<void>.delayed(Duration.zero);
    expect(sub.tier, Tier.plus);
    expect(store.completed, 1);

    // A later Pro restore doesn't downgrade.
    store.deliver('quranai.pro.monthly', PurchaseStatus.restored);
    await Future<void>.delayed(Duration.zero);
    expect(sub.tier, Tier.plus);
    sub.dispose();
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
