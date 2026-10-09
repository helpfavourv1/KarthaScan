// test/subscription_provider_test.dart
//
// Regression test: a returning ad-free buyer must not be treated as a
// free user just because settings finish loading after the provider is
// created on cold start.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:katharscan/core/models/user_settings.dart';
import 'package:katharscan/core/providers/settings_provider.dart';
import 'package:katharscan/core/providers/subscription_provider.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/platform/iap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Implements (not extends) the real service so no billing plugin is touched.
class _FakeIapService implements IapService {
  @override
  Future<bool> initialize({
    required void Function(PurchaseDetails details) onPurchaseUpdate,
  }) async =>
      false;

  @override
  Future<List<ProductDetails>> queryProducts() async =>
      const <ProductDetails>[];

  @override
  Future<void> purchase(ProductDetails product) async {}

  @override
  Future<bool> restorePurchases() async => false;

  @override
  Future<void> dispose() async {}
}

Future<void> _waitForSettings(SettingsProvider settings) async {
  for (int i = 0; i < 400 && settings.isLoading.value; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String settingsKey = 'katharscan.user_settings.v1';

  test('ad-free flag follows saved settings once they finish loading', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(const UserSettings(adsRemoved: true).toJson()),
    });
    final SettingsProvider settings = SettingsProvider(LocalStorageService());
    final SubscriptionProvider subscription =
        SubscriptionProvider(_FakeIapService(), settings);

    // Settings have not loaded yet, so the default is still in place.
    expect(subscription.adsRemoved.value, isFalse);

    await _waitForSettings(settings);

    expect(settings.isLoading.value, isFalse);
    expect(subscription.adsRemoved.value, isTrue);
  });

  test('ad-free flag stays false when nothing was purchased', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsProvider settings = SettingsProvider(LocalStorageService());
    final SubscriptionProvider subscription =
        SubscriptionProvider(_FakeIapService(), settings);

    await _waitForSettings(settings);

    expect(settings.isLoading.value, isFalse);
    expect(subscription.adsRemoved.value, isFalse);
  });
}
