import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app.dart';
import 'core/providers/folder_provider.dart';
import 'core/providers/scan_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/subscription_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/debug_log_service.dart';
import 'core/services/doc_scanner_service.dart';
import 'core/services/local_storage.dart';
import 'core/services/ocr_service.dart';
import 'core/utils/error_handler.dart';
import 'platform/iap_service.dart';
import 'platform/permission_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();

  installGlobalErrorHandling(
    onReportError: (FlutterErrorDetails details) {
      DebugLogService().log(
        'FLUTTER_ERROR',
        '${details.exceptionAsString()} | lib: ${details.library ?? 'unknown'} | ${(details.stack?.toString() ?? '').split('\n').take(6).join(' / ')}',
      );
    },
    onReportIssue: (Uri mailUri) async {
      try {
        await launchUrl(mailUri);
      } catch (_) {}
    },
  );

  final LocalStorageService localStorage = LocalStorageService();
  await localStorage.initialize();

  final DocScannerService docScanner = DocScannerService();
  final OcrService ocr = OcrService();
  final PermissionService permission = PermissionService();
  final IapService iap = IapService();

  final SettingsProvider settingsProvider = SettingsProvider(localStorage);
  final ThemeProvider themeProvider = ThemeProvider(settingsProvider);
  final SubscriptionProvider subscriptionProvider = SubscriptionProvider(iap, settingsProvider);
  final ScanProvider scanProvider = ScanProvider(storage: localStorage, docScanner: docScanner, ocr: ocr, settings: settingsProvider);
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
