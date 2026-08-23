// lib/core/models/user_settings.dart
//
// Immutable model per Section 16 (file #12): theme mode, accent color,
// storage path, language, adsRemoved, ocrLanguage.
//
// Uses Flutter's own `ThemeMode` and `Color` types rather than reinventing
// local equivalents — Section 15 already types theme_provider.dart's state
// as `ValueNotifier<ThemeMode>`, so this model matches that. This is a
// Flutter SDK framework import, not a plugin: it requires no platform
// channel and runs fine under `flutter test` with no device or emulator,
// so it doesn't violate Section 4's "no plugin imports in core/" rule —
// that rule targets dart:io and native-plugin dependencies specifically.
//
// `adsRemoved` here is a cached, persisted convenience flag for instant UI on
// cold start (avoiding an "ad banner" flash before purchase state loads) —
// subscription_provider.dart (file #23) via iap_service.dart (file #19) is
// the runtime source of truth and reconciles this value against the store
// on launch and on restore.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Color, ThemeMode;

import '../utils/constants.dart';

@immutable
class UserSettings {
  const UserSettings({
    this.themeMode = ThemeMode.system,
    this.accentColor = AppColors.accentLight,
    this.storagePath,
    this.language = AppLocales.defaultLanguageCode,
    this.adsRemoved = false,
    this.ocrLanguage = 'latin',
  });

  /// Section 1: "Default theme: Light mode (respects system, manual toggle
  /// available, persists to SharedPreferences)". Default is
  /// [ThemeMode.system] so the app follows the OS until the user
  /// explicitly overrides it via the toggle in settings_screen.dart.
  final ThemeMode themeMode;

  final Color accentColor;

  /// User-selected storage location override. Null means "use the default
  /// app documents directory" — resolving that default is a
  /// platform-touching operation (path_provider) and does not belong in
  /// this model; local_storage.dart (file #13) resolves it at read time.
  final String? storagePath;

  /// One of [AppLocales.supportedLanguageCodes].
  final String language;

  /// True when the user has purchased the one-time "Remove Ads" product.
  /// This is a cached convenience flag for instant cold-start UI;
  /// subscription_provider.dart is the authoritative runtime source of truth.
  final bool adsRemoved;

  /// Selected OCR script pack. All scripts are free; 'latin' is the bundled default.
  final String ocrLanguage;

  /// Sentinel used by [copyWith] to distinguish "storagePath not passed"
  /// from "storagePath explicitly set to null" — a plain `??` can't tell
  /// those apart, which would make it impossible to ever clear a storage
  /// path override back to the default once set.
  static const Object _unset = Object();

  UserSettings copyWith({
    ThemeMode? themeMode,
    Color? accentColor,
    Object? storagePath = _unset,
    String? language,
    bool? adsRemoved,
    String? ocrLanguage,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      storagePath: identical(storagePath, _unset)
          ? this.storagePath
          : storagePath as String?,
      language: language ?? this.language,
      adsRemoved: adsRemoved ?? this.adsRemoved,
      ocrLanguage: ocrLanguage ?? this.ocrLanguage,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      // Color has no stable public int constructor across Flutter
      // versions to round-trip through JSON directly, so this stores the
      // 32-bit ARGB value explicitly.
      'accentColorArgb': _colorToArgb(accentColor),
      'storagePath': storagePath,
      'language': language,
      'adsRemoved': adsRemoved,
      'ocrLanguage': ocrLanguage,
    };
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    // Backward compatibility: old installs used 'isPro' instead of 'adsRemoved'.
    final bool adsRemovedValue = json['adsRemoved'] as bool? ?? json['isPro'] as bool? ?? false;
    return UserSettings(
      themeMode: ThemeMode.values.byName(
        json['themeMode'] as String? ?? ThemeMode.system.name,
      ),
      accentColor: json['accentColorArgb'] == null
          ? AppColors.accentLight
          : _colorFromArgb(json['accentColorArgb'] as int),
      storagePath: json['storagePath'] as String?,
      language: json['language'] as String? ?? AppLocales.defaultLanguageCode,
      adsRemoved: adsRemovedValue,
      ocrLanguage: json['ocrLanguage'] as String? ?? 'latin',
    );
  }

  static int _colorToArgb(Color color) {
    // Color.value (a 32-bit ARGB int) is the correct API on the pinned
    // Flutter 3.24.0 SDK. The double-based component getters (.a/.r/.g/.b)
    // that later replaced it were only added in Flutter 3.27 — using them
    // here would fail to compile against this project's pinned SDK. If
    // this project's Flutter pin is ever deliberately upgraded past 3.27,
    // this should be revisited alongside that change, not before.
    // ignore: deprecated_member_use
    return color.value;
  }

  static Color _colorFromArgb(int argb) {
    final int a = (argb >> 24) & 0xff;
    final int r = (argb >> 16) & 0xff;
    final int g = (argb >> 8) & 0xff;
    final int b = argb & 0xff;
    return Color.fromARGB(a, r, g, b);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserSettings &&
        other.themeMode == themeMode &&
        other.accentColor == accentColor &&
        other.storagePath == storagePath &&
        other.language == language &&
        other.adsRemoved == adsRemoved &&
        other.ocrLanguage == ocrLanguage;
  }

  @override
  int get hashCode => Object.hash(
        themeMode,
        accentColor,
        storagePath,
        language,
        adsRemoved,
        ocrLanguage,
      );

  @override
  String toString() =>
      'UserSettings(themeMode: $themeMode, language: $language, adsRemoved: $adsRemoved, ocrLanguage: $ocrLanguage)';
}
