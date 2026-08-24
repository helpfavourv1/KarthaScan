// lib/core/providers/theme_provider.dart
//
// ValueNotifier<ThemeMode> + accent color (Section 16 file #20).
//
// SOURCE-OF-TRUTH NOTE: Section 15 lists this provider's state as
// ThemeMode + accent color, but UserSettings (settings_provider.dart)
// already contains both of those same fields. Persisting them
// independently in two places would create two sources of truth for the
// same data. Instead, this provider derives its two notifiers from
// settings_provider.dart's ValueNotifier<UserSettings> and delegates
// every write back to it — settings_provider remains the only place that
// ever calls LocalStorageService.saveSettings(). What this provider adds
// is a narrowly-scoped pair of notifiers so a widget that only cares
// about theme doesn't rebuild when, say, language changes.
//
// REACTIVITY: ValueNotifier + ListenableBuilder only, per the MANDATORY
// constraint in constants.dart. This class is not a ChangeNotifier
// itself — it exposes ValueNotifier fields directly.

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart' show Color, ThemeMode;

import '../models/user_settings.dart';
import 'settings_provider.dart';

class ThemeProvider {
  ThemeProvider(this._settingsProvider) {
    final UserSettings initial = _settingsProvider.settings.value;
    themeMode = ValueNotifier<ThemeMode>(initial.themeMode);
    accentColor = ValueNotifier<Color>(initial.accentColor);
    _settingsProvider.settings.addListener(_onSettingsChanged);
  }

  final SettingsProvider _settingsProvider;

  late final ValueNotifier<ThemeMode> themeMode;
  late final ValueNotifier<Color> accentColor;

  void _onSettingsChanged() {
    final UserSettings current = _settingsProvider.settings.value;
    if (themeMode.value != current.themeMode) {
      themeMode.value = current.themeMode;
    }
    if (accentColor.value != current.accentColor) {
      accentColor.value = current.accentColor;
    }
  }

  Future<bool> setThemeMode(ThemeMode mode) =>
      _settingsProvider.setThemeMode(mode);

  Future<bool> setAccentColor(Color color) =>
      _settingsProvider.setAccentColor(color);

  void dispose() {
    _settingsProvider.settings.removeListener(_onSettingsChanged);
    themeMode.dispose();
    accentColor.dispose();
  }
}
