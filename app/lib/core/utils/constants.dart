// lib/core/utils/constants.dart
//
// Design tokens (Section 17), permission rationale copy (Section 12),
// feature flags, and the durable state-management constraint (Section 15).
//
// This file imports package:flutter/material.dart for `Color` only. That is
// a Flutter SDK framework import, not a third-party plugin — it requires no
// platform channel, no device, and no emulator, so it does not violate
// Section 4's "no plugin imports in core/" rule. The test is whether a file
// is unit-testable headlessly (`flutter test`), and this is.
import 'package:flutter/material.dart' show Color;

// =============================================================================
// MANDATORY — STATE MANAGEMENT SCOPE (Section 15)
// =============================================================================
//
// `provider` (pubspec dependency) is used STRICTLY as a dependency-injection
// mechanism: `Provider.value` to pass existing `ValueNotifier` instances
// down the widget tree. Nothing more.
//
// PROHIBITED anywhere in this codebase, in every phase, no exceptions:
//   - ChangeNotifierProvider
//   - Consumer / Consumer2 / Consumer3...
//   - context.watch<T>()
//
// The sole reactivity mechanism, everywhere, is:
//   ValueNotifier<T>  +  ListenableBuilder
//
// If you are about to reach for `Consumer` or `context.watch` because it's
// the "normal" way to use `provider` — stop. Use `Provider.of<T>(context,
// listen: false)` (or `context.read<T>()`) to obtain the ValueNotifier
// instance, then wrap the widget that needs to rebuild in a
// `ListenableBuilder(listenable: thatNotifier, builder: ...)`.
//
// This constraint was confirmed explicitly and is not open to
// reinterpretation by a future phase or a future file. If a file you're
// about to write seems to need `Consumer` to work cleanly, that's a signal
// to restructure the widget tree — not a reason to add it.
// =============================================================================

/// Feature flags. These mirror decisions locked in Section 1 of the
/// blueprint. They exist so that "no notifications" / "no cross-device
/// sync" / "no ads" are checkable constants — not just an absence of code —
/// and so a future contributor can `grep` for why a subsystem doesn't exist.
abstract final class AppFeatureFlags {
  /// Section 1: "Has a daily-habit/retention loop? No". Determines whether
  /// Section 7's notification subsystem exists. It does not. Do not add
  /// flutter_local_notifications or POST_NOTIFICATIONS to this project
  /// without renegotiating this flag and Section 7 together.
  static const bool hasDailyHabitLoop = false;

  /// Section 1: "Needs cross-device sync? No". No backend is generated.
  /// Device Migration (file #39) is an explicit export/import archive
  /// flow, not sync, and must never be marketed as sync.
  static const bool hasCrossDeviceSync = false;

  /// Section 19 Trust Promise: "We will never show you an ad." AdMob and
  /// all ad SDKs are permanently removed from this project's scope.
  static const bool hasAds = false;

  AppFeatureFlags._();
}

/// Color tokens — Section 17. Both light and dark values are provided;
/// callers select the active set via ThemeMode, never by hardcoding one
/// palette. No raw hex values should appear anywhere outside this file.
abstract final class AppColors {
  // bgPrimary — Scaffold background
  static const Color bgPrimaryLight = Color(0xFFFFFFFF);
  static const Color bgPrimaryDark = Color(0xFF0F0F11);

  // bgSecondary — Cards, sheets
  static const Color bgSecondaryLight = Color(0xFFF5F5F7);
  static const Color bgSecondaryDark = Color(0xFF1A1A1E);

  // bgTertiary — Inputs, disabled
  static const Color bgTertiaryLight = Color(0xFFE8E8ED);
  static const Color bgTertiaryDark = Color(0xFF232329);

  // accent — Primary actions, active nav
  static const Color accentLight = Color(0xFF6366F1);
  static const Color accentDark = Color(0xFF818CF8);

  // accentDim — Pressed states
  static const Color accentDimLight = Color(0xFF4F46E5);
  static const Color accentDimDark = Color(0xFF6366F1);

  // textPrimary — Headlines, body
  static const Color textPrimaryLight = Color(0xFF1C1C1E);
  static const Color textPrimaryDark = Color(0xFFF0F0F5);

  // textSecondary — Subtitles
  static const Color textSecondaryLight = Color(0xFF6E6E73);
  static const Color textSecondaryDark = Color(0xFF8A8A95);

  // textTertiary — Placeholders, timestamps
  static const Color textTertiaryLight = Color(0xFFA1A1AA);
  static const Color textTertiaryDark = Color(0xFF52525B);

  // borderSubtle — Dividers
  static const Color borderSubtleLight = Color(0xFFE5E5EA);
  static const Color borderSubtleDark = Color(0xFF2A2A30);

  // borderFocus — Active input borders
  static const Color borderFocusLight = Color(0xFF6366F1);
  static const Color borderFocusDark = Color(0xFF818CF8);

  // error — Validation
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFEF4444);

  // success — Saved, exported
  static const Color successLight = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF34D399);

  // warning — Attention
  static const Color warningLight = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFFBBF24);

  AppColors._();
}

/// Typography scale — Section 17. Sizes in logical pixels, weights as
/// FontWeight-compatible ints, line heights as unitless multipliers (to be
/// applied as `height:` in a TextStyle, which Flutter interprets as a
/// multiple of the font size).
abstract final class AppTypography {
  static const double displaySize = 34;
  static const int displayWeight = 700;
  static const double displayLineHeight = 1.1;

  static const double headlineSize = 28;
  static const int headlineWeight = 600;
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

/// Spacing scale — Section 17. 4px base unit.
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

/// Shape & elevation — Section 17.
abstract final class AppShape {
  static const double cardRadius = 16;
  static const double cardBorderWidth = 0.5;

  static const double buttonRadius = 12;
  static const double buttonMinHeight = 48;

  static const double bottomSheetTopRadius = 20;

  static const double textInputRadius = 12;

  /// 48x48dp minimum touch target, no exceptions — Section 17.
  static const double minTouchTarget = 48;

  AppShape._();
}

/// Animation durations — Section 17. Easing curves are applied at the
/// widget layer (Curves.easeInOut, Curves.easeOut, Curves.linear); this
/// file only fixes the durations so they can't drift between screens.
abstract final class AppAnimationDurations {
  static const Duration screenPush = Duration(milliseconds: 350);
  static const Duration screenPop = Duration(milliseconds: 280);
  static const Duration sheetPresent = Duration(milliseconds: 400);
  static const Duration buttonPress = Duration(milliseconds: 150);
  static const Duration saveSuccess = Duration(milliseconds: 300);
  static const Duration themeToggle = Duration(milliseconds: 200);

  /// Button press scale target — Section 17 ("scale 0.97").
  static const double buttonPressScale = 0.97;

  AppAnimationDurations._();
}

/// Permission rationale copy — Section 8 (feature scope) and Section 12
/// (exact required strings for NSCameraUsageDescription /
/// NSPhotoLibraryUsageDescription). The iOS Info.plist strings (file #60)
/// and the in-app rationale dialog shown by permission_service.dart (file
/// #18, permanent-denial handling) both read from here so the copy the user
/// sees pre-permission-prompt and post-permanent-denial never drifts from
/// what's declared to Apple/Google.
abstract final class AppPermissionRationale {
  static const String cameraUsageDescription =
      'To scan documents. Images are processed on your device and stored locally.';

  static const String photoLibraryUsageDescription =
      'To import photos of documents from your gallery for scanning.';

  AppPermissionRationale._();
}

/// Support contact. The domain is still an unresolved placeholder tracked
/// in Section 1a / the blueprint's "REMAINING PLACEHOLDERS TO INJECT"
/// table — this constant intentionally mirrors that same unresolved
/// [YOUR_DOMAIN] token rather than inventing a new, separate placeholder.
/// Does not block the Android build (see that table); update once a domain
/// is registered.
abstract final class AppSupportContact {
  static const String supportEmail = 'support@katharscan.[YOUR_DOMAIN]';
  static const String privacyPolicyUrl =
      'https://katharscan.[YOUR_DOMAIN]/privacy.html';
  static const String supportUrl =
      'https://katharscan.[YOUR_DOMAIN]/support.html';

  AppSupportContact._();
}

/// Exact required user-facing copy for third-party plugin failures —
/// Section 14 (MANDATORY, verbatim strings). Centralized here so
/// ocr_service.dart, doc_scanner_service.dart, iap_service.dart, and the
/// widgets that surface these states all read the same source rather than
/// each hardcoding their own slightly-different wording.
abstract final class AppPluginFailureCopy {
  /// Section 14, ML Kit Text Recognition failure: OCR button should be
  /// disabled with this as its tooltip.
  static const String ocrUnavailableTooltip = 'OCR unavailable on this device.';

  /// Section 14, ML Kit Document Scanner UNSUPPORTED failure (<1.7GB RAM
  /// devices etc.): shown before routing to the manual crop flow (files
  /// #74-75).
  static const String docScannerUnsupportedMessage =
      "Your device doesn't support the advanced document scanner. Take a "
      'photo with your Camera app, then tap Import below to crop and save it.';

  /// Section 14, IAP billing connection failure.
  static const String billingUnavailableMessage =
      'Billing unavailable — try again later.';

  AppPluginFailureCopy._();
}

/// The 11 supported locale codes — Section 18. Arabic and Hebrew are RTL;
/// everything else is LTR. Keep this list and lib/l10n/*.arb in sync.
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
