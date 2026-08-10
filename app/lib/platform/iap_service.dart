// lib/platform/iap_service.dart
//
// StoreKit / Play Billing: $0.99/mo and $9.99/yr Pro, purchase / restore /
// acknowledgment (Section 16 file #19).
//
// WHY THIS FILE LIVES IN platform/, NOT core/services/: Play Billing and
// StoreKit have genuinely different completion contracts, not just
// different plugin calls. Android requires an explicit acknowledgment
// within 3 days of purchase or the purchase is auto-refunded; iOS's
// transaction-finishing model doesn't have that specific constraint. Both
// happen to funnel through the same completePurchase() call in this
// package, but the *consequence* of getting it wrong is platform-specific
// business logic this file owns — the exact kind of OS-divergent decision
// surface that belongs in platform/, per the confirmed layering.
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/utils/constants.dart';

/// Thrown when a purchase is attempted while billing isn't reachable.
/// Callers (paywall_screen.dart) should catch this and show
/// [AppPluginFailureCopy.billingUnavailableMessage] per Section 14 —
/// never crash.
class IapUnavailableException implements Exception {
  const IapUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'IapUnavailableException: $message';
}

class IapService {
  static const String monthlyProductId = 'com.zdmgold.katharscan.pro.monthly';
  static const String yearlyProductId = 'com.zdmgold.katharscan.pro.yearly';
  static const Set<String> allProductIds = <String>{
    monthlyProductId,
    yearlyProductId,
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Starts listening to the purchase stream. [onPurchaseUpdate] fires for
  /// every purchase event — new purchase, restored purchase, error, or
  /// pending — so subscription_provider.dart can update
  /// ValueNotifier<bool> isPro accordingly. Safe to call once at app
  /// startup; later calls are no-ops. Never throws — returns false if
  /// billing isn't available on this device at all, which is a normal
  /// startup-time check, not a user-initiated purchase attempt. For the
  /// exact Section 14 message at the moment a user taps "Subscribe", use
  /// [purchase] instead, which throws [IapUnavailableException].
  Future<bool> initialize({
    required void Function(PurchaseDetails details) onPurchaseUpdate,
  }) async {
    if (_subscription != null) return true;
    try {
      final bool available = await _iap.isAvailable();
      if (!available) return false;

      _subscription = _iap.purchaseStream.listen(
        (List<PurchaseDetails> purchases) {
          for (final PurchaseDetails purchase in purchases) {
            onPurchaseUpdate(purchase);
            if (purchase.pendingCompletePurchase) {
              // Required Android acknowledgment / iOS transaction-finish
              // step. Skipping this on Android auto-refunds the purchase
              // within 3 days — this is the one line in this whole file
              // that most directly justifies platform/ over core/.
              _iap.completePurchase(purchase);
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _logError('purchaseStream', error, stackTrace);
        },
      );
      return true;
    } catch (error, stackTrace) {
      _logError('initialize', error, stackTrace);
      return false;
    }
  }

  /// Fetches live store metadata (localized price, title, description)
  /// for the two Pro product IDs. Returns an empty list on any failure —
  /// paywall_screen.dart should fall back to Section 19's static
  /// "$0.99/mo, $9.99/yr" copy in that case rather than showing nothing.
  Future<List<ProductDetails>> queryProducts() async {
    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(allProductIds);
      if (response.error != null) {
        debugPrint(
          '[IapService] queryProducts store error: ${response.error}',
        );
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          '[IapService] Product IDs not found in store: '
          '${response.notFoundIDs}',
        );
      }
      return response.productDetails;
    } catch (error, stackTrace) {
      _logError('queryProducts', error, stackTrace);
      return const <ProductDetails>[];
    }
  }

  /// Initiates a purchase for [product]. This only reports whether the
  /// native purchase flow was successfully *launched* — the actual result
  /// (success, error, cancelled, pending) arrives asynchronously via the
  /// purchaseStream callback passed to [initialize]. Throws
  /// [IapUnavailableException] with the exact Section 14 copy if billing
  /// isn't reachable, so the caller can surface that message directly.
  Future<void> purchase(ProductDetails product) async {
    try {
      final bool available = await _iap.isAvailable();
      if (!available) {
        throw const IapUnavailableException(
          AppPluginFailureCopy.billingUnavailableMessage,
        );
      }

      final PurchaseParam param = PurchaseParam(productDetails: product);
      // Subscriptions go through buyNonConsumable in this package —
      // renewal itself is handled by StoreKit/Play Billing, not by
      // treating the subscription as a "consumable" purchase that this
      // app would need to re-grant on each renewal.
      final bool launched = await _iap.buyNonConsumable(purchaseParam: param);
      if (!launched) {
        throw const IapUnavailableException(
          AppPluginFailureCopy.billingUnavailableMessage,
        );
      }
    } on IapUnavailableException {
      rethrow;
    } catch (error, stackTrace) {
      _logError('purchase', error, stackTrace);
      throw const IapUnavailableException(
        AppPluginFailureCopy.billingUnavailableMessage,
      );
    }
  }

  /// Restores prior purchases — the same App Store/Play Store account
  /// already owns Pro on another device, or reinstalled the app. Results
  /// arrive via the same purchaseStream callback as a fresh purchase,
  /// with PurchaseDetails.status == PurchaseStatus.restored.
  Future<bool> restorePurchases() async {
    try {
      await _iap.restorePurchases();
      return true;
    } catch (error, stackTrace) {
      _logError('restorePurchases', error, stackTrace);
      return false;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[IapService] $operation failed: $error');
  }
}
