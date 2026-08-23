// lib/core/utils/constants.dart
//
// iOS-grade design tokens, feature flags, and state-management constraint.

import 'package:flutter/material.dart';

// =============================================================================
// MANDATORY — STATE MANAGEMENT SCOPE (Section 15)
// =============================================================================
//
// provider is used STRICTLY as dependency injection. ValueNotifier + ListenableBuilder
// is the ONLY reactivity mechanism. No ChangeNotifierProvider, no Consumer, no context.watch.
// =============================================================================

abstract final class AppFeatureFlags {
  static const bool hasDailyHabitLoop = false;
  static const bool hasCrossDeviceSync = false;
  static const bool hasAds = true;
  AppFeatureFlags._();
}

abstract final class AppColors {
  // Light Mode
  static const Color bgPrimaryLight = Color(0xFFF2F2F7);
  static const Color bgSecondaryLight = Color(0xFFFFFFFF);
  static const Color bgTertiaryLight = Color(0xFFE8E8ED);

  // Dark Mode
  static const Color bgPrimaryDark = Color(0xFF000000);
  static const Color bgSecondaryDark = Color(0xFF1C1C1E);
  static const Color bgTertiaryDark = Color(0xFF2C2C2E);

  // Accent (iOS System Blue)
  static const Color accentLight = Color(0xFF007AFF);
  static const Color accentDark = Color(0xFF0A84FF);
  static const Color accentDimLight = Color(0xFF0051D5);
  static const Color accentDimDark = Color(0xFF0A84FF);

  // Text
  static const Color textPrimaryLight = Color(0xFF111111);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryLight = Color(0xFF3A3A3C);
  static const Color textSecondaryDark = Color(0xFFEBEBF5);
  static const Color textTertiaryLight = Color(0xFF8E8E93);
  static const Color textTertiaryDark = Color(0xFF8E8E93);

  // Borders
  static const Color borderSubtleLight = Color(0xFFE5E5EA);
  static const Color borderSubtleDark = Color(0xFF38383A);
  static const Color borderFocusLight = Color(0xFF007AFF);
  static const Color borderFocusDark = Color(0xFF0A84FF);

  // Semantic Colors
  static const Color errorLight = Color(0xFFFF3B30);
  static const Color errorDark = Color(0xFFFF453A);
  static const Color successLight = Color(0xFF34C759);
  static const Color successDark = Color(0xFF30D158);
  static const Color warningLight = Color(0xFFFF9500);
  static const Color warningDark = Color(0xFFFF9F0A);

  AppColors._();
}

abstract final class AppTypography {
  static const double displaySize = 34;
  static const int displayWeight = 700;
  static const double displayLineHeight = 1.1;

  static const double headlineSize = 28;
  static const int headlineWeight = 700;
  static const double headlineLineHeight = 1.2;

  static const double title1Size = 22;
  static const int title1Weight = 600;
  static const double title1LineHeight = 1.3;

  static const double title2Size = 17;
  static const int title2Weight = 600;
  static const double title2LineHeight = 1.3;

  static const double bodySize = 17;
  static const int bodyWeight = 400;
  static const double bodyLineHeight = 1.5;

  static const double calloutSize = 16;
  static const int calloutWeight = 500;
  static const double calloutLineHeight = 1.4;

  static const double footnoteSize = 13;
  static const int footnoteWeight = 400;
  static const double footnoteLineHeight = 1.4;

  static const double captionSize = 12;
  static const int captionWeight = 400;
  static const double captionLineHeight = 1.3;

  AppTypography._();
}

abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
  AppSpacing._();
}

abstract final class AppShape {
  static const double cardRadius = 16;
  static const double cardBorderWidth = 0;
  static const double buttonRadius = 14;
  static const double buttonMinHeight = 48;
  static const double bottomSheetTopRadius = 24;
  static const double textInputRadius = 12;
  static const double minTouchTarget = 48;
  AppShape._();
}

abstract final class AppShadows {
  static List<BoxShadow> get ambient => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get fab => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}

abstract final class AppAnimationDurations {
  static const Duration screenPush = Duration(milliseconds: 350);
  static const Duration screenPop = Duration(milliseconds: 280);
  static const Duration sheetPresent = Duration(milliseconds: 400);
  static const Duration buttonPress = Duration(milliseconds: 150);
  static const Duration saveSuccess = Duration(milliseconds: 300);
  static const Duration themeToggle = Duration(milliseconds: 200);
  static const double buttonPressScale = 0.97;
  AppAnimationDurations._();
}

abstract final class AppPermissionRationale {
  static const String cameraUsageDescription =
      'To scan documents. Images are processed on your device and stored locally.';
  static const String photoLibraryUsageDescription =
      'To import photos of documents from your gallery for scanning.';
  AppPermissionRationale._();
}

abstract final class AppSupportContact {
  static const String supportEmail = 'accessmakr@gmail.com';
  static const String privacyPolicyUrl = 'https://katharscan.helpfavourv1.workers.dev/privacy';
  static const String supportUrl = 'https://katharscan.helpfavourv1.workers.dev/support';
  AppSupportContact._();
}

abstract final class AppPluginFailureCopy {
  static const String ocrUnavailableTooltip = 'OCR unavailable on this device.';
  static const String docScannerUnsupportedMessage =
      "Your device doesn't support the advanced document scanner. Take a "
      'photo with your Camera app, then tap Import below to crop and save it.';
  static const String billingUnavailableMessage =
      'Billing unavailable — try again later.';
  AppPluginFailureCopy._();
}

abstract final class AppLocales {
  static const List<String> supportedLanguageCodes = [
    'en',
    'es',
    'fr',
    'de',
    'pt',
    'ar',
    'hi',
    'ja',
    'ko',
    'zh',
    'he',
  ];
  static const List<String> rtlLanguageCodes = ['ar', 'he'];
  static const String defaultLanguageCode = 'en';
  static bool isRtl(String languageCode) =>
      rtlLanguageCodes.contains(languageCode);
  AppLocales._();
}
