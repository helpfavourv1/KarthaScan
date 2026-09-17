import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show immutable, mapEquals;
import 'package:flutter/material.dart' show Color, ThemeMode;

import '../utils/constants.dart';

@immutable
class UserSettings {
  const UserSettings({
    this.themeMode = ThemeMode.system,
    this.accentColor = AppColors.defaultAccentColor,
    this.storagePath,
    this.language = AppLocales.defaultLanguageCode,
    this.adsRemoved = false,
    this.autoCopyOcr = false,
    this.beepOnCapture = false,
    this.vibrateOnCapture = false,
    this.enableNotifications = false,
    this.enableReviewPrompts = false,
    this.enableSharePrompts = false,
    this.lastWatermark,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final String? storagePath;
  final String language;
  final bool adsRemoved;
  final bool autoCopyOcr;
  final bool beepOnCapture;
  final bool vibrateOnCapture;
  final bool enableNotifications;
  final bool enableReviewPrompts;
  final bool enableSharePrompts;

  final Map<String, dynamic>? lastWatermark;
  static const Object _unset = Object();

  UserSettings copyWith({
    ThemeMode? themeMode,
    Color? accentColor,
    Object? storagePath = _unset,
    String? language,
    bool? adsRemoved,
    bool? autoCopyOcr,
    bool? beepOnCapture,
    bool? vibrateOnCapture,
    bool? enableNotifications,
    bool? enableReviewPrompts,
    bool? enableSharePrompts,
    Object? lastWatermark = _unset,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      storagePath: identical(storagePath, _unset) ? this.storagePath : storagePath as String?,
      language: language ?? this.language,
      adsRemoved: adsRemoved ?? this.adsRemoved,
      autoCopyOcr: autoCopyOcr ?? this.autoCopyOcr,
      beepOnCapture: beepOnCapture ?? this.beepOnCapture,
      vibrateOnCapture: vibrateOnCapture ?? this.vibrateOnCapture,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableReviewPrompts: enableReviewPrompts ?? this.enableReviewPrompts,
      enableSharePrompts: enableSharePrompts ?? this.enableSharePrompts,
      lastWatermark: identical(lastWatermark, _unset) ? this.lastWatermark : lastWatermark as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      'accentColorArgb': _colorToArgb(accentColor),
      'storagePath': storagePath,
      'language': language,
      'adsRemoved': adsRemoved,
      'autoCopyOcr': autoCopyOcr,
      'beepOnCapture': beepOnCapture,
      'vibrateOnCapture': vibrateOnCapture,
      'enableNotifications': enableNotifications,
      'enableReviewPrompts': enableReviewPrompts,
      'enableSharePrompts': enableSharePrompts,
      'lastWatermark': lastWatermark,
    };
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    final bool adsRemovedValue = json['adsRemoved'] as bool? ?? json['isPro'] as bool? ?? false;
    return UserSettings(
      themeMode: ThemeMode.values.byName(json['themeMode'] as String? ?? ThemeMode.system.name),
      accentColor: json['accentColorArgb'] == null ? AppColors.accentLight : _colorFromArgb(json['accentColorArgb'] as int),
      storagePath: json['storagePath'] as String?,
      language: json['language'] as String? ?? (() {
        final deviceLocale = PlatformDispatcher.instance.locale;
        return AppLocales.supportedLanguageCodes.firstWhere(
          (code) => code == deviceLocale.languageCode,
          orElse: () => 'en',
        );
      })(),
      adsRemoved: adsRemovedValue,
      autoCopyOcr: json['autoCopyOcr'] as bool? ?? false,
      beepOnCapture: json['beepOnCapture'] as bool? ?? false,
      vibrateOnCapture: json['vibrateOnCapture'] as bool? ?? false,
      enableNotifications: json['enableNotifications'] as bool? ?? false,
      enableReviewPrompts: json['enableReviewPrompts'] as bool? ?? false,
      enableSharePrompts: json['enableSharePrompts'] as bool? ?? false,
      lastWatermark: (json['lastWatermark'] as Map?)?.cast<String, dynamic>(),
    );
  }

  static int _colorToArgb(Color color) { return color.toARGB32(); }
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
        other.themeMode == themeMode && other.accentColor == accentColor &&
        other.storagePath == storagePath && other.language == language &&
        other.adsRemoved == adsRemoved && other.autoCopyOcr == autoCopyOcr &&
        other.beepOnCapture == beepOnCapture && other.vibrateOnCapture == vibrateOnCapture &&
        other.enableNotifications == enableNotifications && other.enableReviewPrompts == enableReviewPrompts &&
        other.enableSharePrompts == enableSharePrompts && mapEquals(other.lastWatermark, lastWatermark);
  }

  @override
  int get hashCode {
    final int base = Object.hash(themeMode, accentColor, storagePath, language, adsRemoved, autoCopyOcr, beepOnCapture, vibrateOnCapture, enableNotifications, enableReviewPrompts, enableSharePrompts);
    if (lastWatermark == null) return base;
    final int mapHash = Object.hashAll(lastWatermark!.entries.map((MapEntry<String, dynamic> e) => Object.hash(e.key, e.value)));
    return Object.hash(base, mapHash);
  }

  @override
  String toString() => 'UserSettings(themeMode: $themeMode, language: $language, adsRemoved: $adsRemoved, autoCopy: $autoCopyOcr, beep: $beepOnCapture, vibrate: $vibrateOnCapture, notif: $enableNotifications, review: $enableReviewPrompts, share: $enableSharePrompts)';
}