import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'core/providers/folder_provider.dart';
import 'core/providers/scan_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/subscription_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/ad_consent_service.dart';
import 'core/services/debug_log_service.dart';
import 'core/services/doc_scanner_service.dart';
import 'core/services/engagement_service.dart';
import 'core/services/local_storage.dart';
import 'core/services/ocr_service.dart';
import 'core/utils/error_handler.dart';
import 'platform/iap_service.dart';
import 'platform/permission_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  final PermissionService permission = PermissionService();

  // GATED AdMob Initialization (Apple ATT Compliance)
  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

  // The tracking prompt is answered at the end of onboarding, so on later
  // launches consent can run straight away. Ads load only after it finishes.
  if (hasSeenOnboarding) {
    unawaited(AdConsentService.instance.start());
  }

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
  final IapService iap = IapService();

  final SettingsProvider settingsProvider = SettingsProvider(localStorage);
  final ThemeProvider themeProvider = ThemeProvider(settingsProvider);
  final SubscriptionProvider subscriptionProvider = SubscriptionProvider(iap, settingsProvider);
  final ScanProvider scanProvider = ScanProvider(storage: localStorage, docScanner: docScanner, ocr: ocr, settings: settingsProvider);
  final FolderProvider folderProvider = FolderProvider(localStorage);

  // The share/review prompt listener wraps the whole app and needs this
  // service on the very first frame.
  await EngagementService.init(subscriptionProvider);

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

/// Lists the bundled fonts' SIL Open Font Licences on the licences page.
void _registerFontLicenses() {
  const fonts = <String, List<String>>{
    'assets/licenses/OFL-NotoSans.txt': ['Noto Sans'],
    'assets/licenses/OFL-NotoSansArabic.txt': ['Noto Sans Arabic'],
    'assets/licenses/OFL-PlusJakartaSans.txt': ['Plus Jakarta Sans'],
    'assets/licenses/OFL-DancingScript.txt': ['Dancing Script'],
    'assets/licenses/OFL-Caveat.txt': ['Caveat'],
    'assets/licenses/Apache-2.0-Tesseract.txt': ['Tesseract OCR, Tesseract4Android and tessdata_fast language files'],
    'assets/licenses/BSD-Leptonica.txt': ['Leptonica'],
    'assets/licenses/OFL-NotoSansCJK.txt': ['Noto Sans SC, JP and KR (downloaded for PDF text)'],
  };
  LicenseRegistry.addLicense(() async* {
    for (final e in fonts.entries) {
      yield LicenseEntryWithLineBreaks(e.value, await rootBundle.loadString(e.key));
    }
  });
}
