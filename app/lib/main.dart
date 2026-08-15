// lib/main.dart
//
// Init: sqflite, IAP, error boundary, localization (Section 16 file #41).
//
// Services are constructed once here and shared across providers via
// Provider.value — the MANDATORY DI-only scope of `provider`
// (constants.dart / Section 15). This file never uses ChangeNotifierProvider,
// Consumer, or context.watch, matching every other file in this project.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'core/providers/folder_provider.dart';
import 'core/providers/scan_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/subscription_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/doc_scanner_service.dart';
import 'core/services/local_storage.dart';
import 'core/services/ocr_service.dart';
import 'core/utils/error_handler.dart';
import 'platform/iap_service.dart';
import 'platform/permission_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  installGlobalErrorHandling(
    onReportIssue: (Uri mailUri) async {
      try {
        await launchUrl(mailUri);
      } catch (_) {
        // If even the report-issue mailto: fails to launch, there's
        // nothing further to do — the app is already showing its
        // non-crashing fallback error screen at this point (Section 14/15
        // "never crash" applies here too: a failed report action must not
        // itself throw somewhere uncaught).
      }
    },
  );

  // sqflite init (Section 16 file #41's first named responsibility).
  // LocalStorageService.initialize() itself never throws — it falls back
  // to in-memory mode internally per Section 15 — so awaiting it here is
  // safe and doesn't need its own try-catch.
  final LocalStorageService localStorage = LocalStorageService();
  await localStorage.initialize();

  final DocScannerService docScanner = DocScannerService();
  final OcrService ocr = OcrService();
  final PermissionService permission = PermissionService();
  // IAP init (Section 16 file #41's second named responsibility) happens
  // inside SubscriptionProvider's constructor, which calls
  // IapService.initialize() — constructing the provider below is what
  // actually starts it.
  final IapService iap = IapService();

  final SettingsProvider settingsProvider = SettingsProvider(localStorage);
  final ThemeProvider themeProvider = ThemeProvider(settingsProvider);
  final SubscriptionProvider subscriptionProvider =
      SubscriptionProvider(iap, settingsProvider);
  final ScanProvider scanProvider = ScanProvider(
    storage: localStorage,
    docScanner: docScanner,
    ocr: ocr,
  );
  final FolderProvider folderProvider = FolderProvider(localStorage);

  runApp(
    MultiProvider(
      providers: [
        Provider<LocalStorageService>.value(value: localStorage),
        Provider<PermissionService>.value(value: permission),
        Provider<SettingsProvider>.value(value: settingsProvider),
        Provider<ThemeProvider>.value(value: themeProvider),
        Provider<SubscriptionProvider>.value(value: subscriptionProvider),
        Provider<ScanProvider>.value(value: scanProvider),
        Provider<FolderProvider>.value(value: folderProvider),
      ],
      child: const KatharScanApp(),
    ),
  );
}
