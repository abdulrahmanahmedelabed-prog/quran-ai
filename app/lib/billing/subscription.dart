import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subscription levels. The app has no ads at any level.
enum Tier {
  /// Follow-along: the recitation is tracked, but not corrected.
  free('المجاني'),

  /// Word mistakes (wrong and skipped words) in the margin.
  pro('برو'),

  /// Everything in Pro plus tajweed: colored rulings and madd/ending checks.
  plus('بلس');

  const Tier(this.label);

  final String label;

  bool get detectsMistakes => this != free;
  bool get detectsTajweed => this == plus;
}

/// A store product. Prices come from the App Store / Google Play listing.
class Plan {
  const Plan(this.tier, this.productId, {required this.yearly});

  final Tier tier;
  final String productId;
  final bool yearly;
}

/// Product IDs to create in App Store Connect and the Play Console, as
/// auto-renewing subscriptions.
const plans = [
  Plan(Tier.pro, 'quranai.pro.monthly', yearly: false),
  Plan(Tier.pro, 'quranai.pro.yearly', yearly: true),
  Plan(Tier.plus, 'quranai.plus.monthly', yearly: false),
  Plan(Tier.plus, 'quranai.plus.yearly', yearly: true),
];

Plan? planFor(String productId) {
  for (final p in plans) {
    if (p.productId == productId) return p;
  }
  return null;
}

/// Checks a purchase before it unlocks anything. The default trusts the
/// store callback; production apps should verify the receipt on a server
/// (App Store Server API / Google Play Developer API), which also reports
/// expiry and cancellation.
typedef PurchaseVerifier = Future<bool> Function(PurchaseDetails purchase);

class SubscriptionService extends ChangeNotifier {
  SubscriptionService(this._prefs, {InAppPurchase? store, PurchaseVerifier? verify})
      : _storeOverride = store,
        _verify = verify ?? ((_) async => true);

  final SharedPreferences _prefs;
  final InAppPurchase? _storeOverride;
  final PurchaseVerifier _verify;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  InAppPurchase get _store => _storeOverride ?? InAppPurchase.instance;

  /// Products loaded from the store, by ID.
  final Map<String, ProductDetails> products = {};

  bool storeAvailable = false;
  bool busy = false;
  String? error;

  Tier get tier => Tier.values.asNameMap()[_prefs.getString('tier')] ?? Tier.free;

  set _tier(Tier t) {
    _prefs.setString('tier', t.name);
    notifyListeners();
  }

  /// Connects to the store and loads prices. Call once at startup.
  Future<void> init() async {
    try {
      storeAvailable = await _store.isAvailable();
      if (!storeAvailable) return;
      _sub = _store.purchaseStream.listen(_onPurchases, onError: (Object e) {
        error = 'تعذرت عملية الشراء: $e';
        busy = false;
        notifyListeners();
      });
      final response = await _store.queryProductDetails({for (final p in plans) p.productId});
      for (final p in response.productDetails) {
        products[p.id] = p;
      }
    } catch (e) {
      storeAvailable = false;
      debugPrint('store unavailable: $e');
    }
    notifyListeners();
  }

  Future<void> buy(Plan plan) async {
    final product = products[plan.productId];
    if (product == null) {
      error = 'هذا الاشتراك غير متاح حاليًا في المتجر.';
      notifyListeners();
      return;
    }
    error = null;
    busy = true;
    notifyListeners();
    try {
      // The plugin sells subscriptions through buyNonConsumable.
      await _store.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      busy = false;
      error = 'تعذرت عملية الشراء: $e';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    error = null;
    busy = true;
    notifyListeners();
    try {
      await _store.restorePurchases();
    } catch (e) {
      error = 'تعذرت استعادة المشتريات: $e';
    }
    busy = false;
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          busy = true;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final plan = planFor(p.productID);
          if (plan != null && await _verify(p) && plan.tier.index > tier.index) {
            _tier = plan.tier;
          }
          busy = false;
        case PurchaseStatus.error:
          error = 'تعذرت عملية الشراء. حاول مرة أخرى.';
          busy = false;
        case PurchaseStatus.canceled:
          busy = false;
      }
      if (p.pendingCompletePurchase) await _store.completePurchase(p);
    }
    notifyListeners();
  }

  /// Switches tier without a purchase (debug builds only, for testing).
  void debugSetTier(Tier t) => _tier = t;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
