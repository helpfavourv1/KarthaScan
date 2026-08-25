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
    this.autoCopyOcr = false,
    this.beepOnCapture = false,
    this.vibrateOnCapture = false,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final String? storagePath;
  final String language;
  final bool adsRemoved;
  final bool autoCopyOcr;
  final bool beepOnCapture;
  final bool vibrateOnCapture;

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
    };
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    final bool adsRemovedValue = json['adsRemoved'] as bool? ?? json['isPro'] as bool? ?? false;
    return UserSettings(
      themeMode: ThemeMode.values.byName(json['themeMode'] as String? ?? ThemeMode.system.name),
      accentColor: json['accentColorArgb'] == null ? AppColors.accentLight : _colorFromArgb(json['accentColorArgb'] as int),
      storagePath: json['storagePath'] as String?,
      language: json['language'] as String? ?? AppLocales.defaultLanguageCode,
      adsRemoved: adsRemovedValue,
      autoCopyOcr: json['autoCopyOcr'] as bool? ?? false,
      beepOnCapture: json['beepOnCapture'] as bool? ?? false,
      vibrateOnCapture: json['vibrateOnCapture'] as bool? ?? false,
    );
  }

  static int _colorToArgb(Color color) {
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
        other.autoCopyOcr == autoCopyOcr &&
        other.beepOnCapture == beepOnCapture &&
        other.vibrateOnCapture == vibrateOnCapture;
  }

  @override
  int get hashCode => Object.hash(themeMode, accentColor, storagePath, language, adsRemoved, autoCopyOcr, beepOnCapture, vibrateOnCapture);

  @override
  String toString() => 'UserSettings(themeMode: $themeMode, language: $language, adsRemoved: $adsRemoved, autoCopy: $autoCopyOcr, beep: $beepOnCapture, vibrate: $vibrateOnCapture)';
}
