// test/app_boot_test.dart
//
// Starts the real app shell on a fake phone (fake storage folder, real
// sqlite through FFI, plugin channels answered with nothing) and fails with
// the full call trace if any widget throws while drawing. Used to find
// "Something went wrong" screens without a device.
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:katharscan/app.dart';
import 'package:katharscan/core/providers/folder_provider.dart';
import 'package:katharscan/core/providers/scan_provider.dart';
import 'package:katharscan/core/providers/settings_provider.dart';
import 'package:katharscan/core/providers/subscription_provider.dart';
import 'package:katharscan/core/providers/theme_provider.dart';
import 'package:katharscan/core/services/doc_scanner_service.dart';
import 'package:katharscan/core/services/engagement_service.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:katharscan/platform/iap_service.dart';
import 'package:katharscan/platform/permission_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeIapService implements IapService {
  @override
  Future<bool> initialize({
    required void Function(PurchaseDetails details) onPurchaseUpdate,
  }) async =>
      false;
  @override
  Future<List<ProductDetails>> queryProducts() async => const <ProductDetails>[];
  @override
  Future<void> purchase(ProductDetails product) async {}
  @override
  Future<bool> restorePurchases() async => false;
  @override
  Future<void> dispose() async {}
}

String _trace(Object error, StackTrace? stack) {
  final String head = error.toString().split('\n').first;
  final List<String> lines = (stack?.toString() ?? '').split('\n');
  final String app = lines.where((String l) => l.contains('katharscan')).take(8).join('\n');
  final String top = lines.where((String l) => l.trim().isNotEmpty).take(4).join('\n');
  return '$head\nTOP:\n$top\nAPP FRAMES:\n${app.isEmpty ? '(none)' : app}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<void> boot(WidgetTester tester, {required bool seenOnboarding}) async {
    final Directory tmp = Directory.systemTemp.createTempSync('katharscan_boot_');
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tmp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (MethodCall call) async => <String, dynamic>{
        'appName': 'KatharScan',
        'packageName': 'com.zdmgold.katharscan',
        'version': '1.0.0',
        'buildNumber': '1',
        'buildSignature': '',
      },
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hasSeenOnboarding': seenOnboarding,
    });

    final List<String> errors = <String>[];
    final void Function(FlutterErrorDetails)? oldOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      errors.add('[widget/${d.library}] ${_trace(d.exception, d.stack)}');
      oldOnError?.call(d); // keep the test framework's own bookkeeping
    };
    PlatformDispatcher.instance.onError = (Object e, StackTrace s) {
      if (e is MissingPluginException) return true;
      errors.add('[async] ${_trace(e, s)}');
      return true;
    };

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;

    late LocalStorageService storage;
    await tester.runAsync(() async {
      storage = LocalStorageService();
      await storage.initialize();
    });
    final SettingsProvider settings = SettingsProvider(storage);
    final ThemeProvider theme = ThemeProvider(settings);
    final SubscriptionProvider sub = SubscriptionProvider(_FakeIapService(), settings);
    final ScanProvider scan = ScanProvider(
      storage: storage,
      docScanner: DocScannerService(),
      ocr: OcrService(),
      settings: settings,
    );
    final FolderProvider folders = FolderProvider(storage);
    // Mirrors main.dart: the prompt listener needs this on the first frame.
    await tester.runAsync(() => EngagementService.init(sub));

    await tester.pumpWidget(
      MultiProvider(
        providers: <Provider<dynamic>>[
          Provider<LocalStorageService>.value(value: storage),
          Provider<PermissionService>.value(value: PermissionService()),
          Provider<SettingsProvider>.value(value: settings),
          Provider<ThemeProvider>.value(value: theme),
          Provider<SubscriptionProvider>.value(value: sub),
          Provider<ScanProvider>.value(value: scan),
          Provider<FolderProvider>.value(value: folders),
        ],
        child: const KatharScanApp(),
      ),
    );
    for (int i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 300));
    }

    FlutterError.onError = oldOnError;
    while (tester.takeException() != null) {}
    if (errors.isNotEmpty) {
      fail('App threw while starting (seenOnboarding=$seenOnboarding):\n'
          '${errors.take(4).join('\n----\n')}');
    }
  }

  testWidgets('returning user: home screen draws without errors', (WidgetTester tester) async {
    await boot(tester, seenOnboarding: true);
  });

  testWidgets('first launch: onboarding draws without errors', (WidgetTester tester) async {
    await boot(tester, seenOnboarding: false);
  }, skip: true);
}
