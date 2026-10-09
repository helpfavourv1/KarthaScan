// lib/core/providers/settings_provider.dart
//
// ValueNotifier<UserSettings> + persistence (Section 16 file #24).
// This is the ONE place in the app that calls
// LocalStorageService.loadSettings()/saveSettings(). theme_provider.dart
// derives its narrower ThemeMode/accent-color notifiers from this
// provider's `settings` notifier rather than persisting independently —
// see theme_provider.dart's file header for the full reasoning.
//
// REACTIVITY: ValueNotifier + ListenableBuilder only, per the MANDATORY
// constraint in constants.dart. This class is not a ChangeNotifier
// itself — it exposes ValueNotifier fields directly.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart' show Color, ThemeMode;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_settings.dart';
import '../services/local_storage.dart';
import '../services/notification_service.dart';

class SettingsProvider {
  SettingsProvider(this._storage) {
    unawaited(_load());
  }

  final LocalStorageService _storage;

  final ValueNotifier<UserSettings> settings =
      ValueNotifier<UserSettings>(const UserSettings());

  /// True while the initial load from storage is in flight. Screens can
  /// use this to avoid flashing default settings before the real ones
  /// arrive on cold start.
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(true);

  /// Set on the most recent save failure, per Section 15's "every save...
  /// shows explicit... error feedback" rule. Cleared on the next
  /// successful save.
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  Future<void> _load() async {
    isLoading.value = true;
    try {
      settings.value = await _storage.loadSettings();
    } finally {
      isLoading.value = false;
    }
    await _mirrorEngagementFlags(settings.value);
    if (settings.value.enableNotifications) {
      try {
        await NotificationService.instance.initialize();
      } catch (_) {}
    }
  }

  /// The notification and prompt services read these three plain flags from
  /// SharedPreferences, so the saved toggles are copied there. Without this
  /// the Settings switches never reached them.
  Future<void> _mirrorEngagementFlags(UserSettings s) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enableNotifications', s.enableNotifications);
      await prefs.setBool('enableReviewPrompts', s.enableReviewPrompts);
      await prefs.setBool('enableSharePrompts', s.enableSharePrompts);
    } catch (_) {}
  }

  Future<void> _applyNotificationChoice(bool enabled) async {
    try {
      if (enabled) {
        await NotificationService.instance.initialize();
        await NotificationService.instance.requestPermission();
      } else {
        await NotificationService.instance.cancelAllNotifications();
      }
    } catch (_) {}
  }

  Future<bool> _persist(UserSettings next) async {
    final bool notificationsChanged =
        next.enableNotifications != settings.value.enableNotifications;
    settings.value = next;
    await _mirrorEngagementFlags(next);
    if (notificationsChanged) {
      unawaited(_applyNotificationChoice(next.enableNotifications));
    }
    final bool success = await _storage.saveSettings(next);
    lastError.value = success ? null : 'Could not save settings.';
    return success;
  }

  Future<bool> setThemeMode(ThemeMode mode) =>
      _persist(settings.value.copyWith(themeMode: mode));

  Future<bool> setAccentColor(Color color) =>
      _persist(settings.value.copyWith(accentColor: color));

  Future<bool> setLanguage(String languageCode) =>
      _persist(settings.value.copyWith(language: languageCode));

  /// Pass null to clear a storage-path override back to the app default.
  Future<bool> setStoragePath(String? path) =>
      _persist(settings.value.copyWith(storagePath: path));

  /// Called by subscription_provider.dart when the authoritative
  /// entitlement state changes, keeping UserSettings.adsRemoved — a cached
  /// convenience flag for instant cold-start UI — in sync. Not meant to
  /// be called directly by UI code; subscription_provider.dart is the
  /// source of truth for ad removal status, this just mirrors it into storage.
  Future<bool> setAdsRemoved(bool adsRemoved) =>
      _persist(settings.value.copyWith(adsRemoved: adsRemoved));

  Future<bool> setAutoCopyOcr(bool value) =>
      _persist(settings.value.copyWith(autoCopyOcr: value));

  Future<bool> setBeepOnCapture(bool value) =>
      _persist(settings.value.copyWith(beepOnCapture: value));

  Future<bool> setVibrateOnCapture(bool value) =>
      _persist(settings.value.copyWith(vibrateOnCapture: value));

  Future<bool> setLastWatermark(Map<String, dynamic>? value) =>
      _persist(settings.value.copyWith(lastWatermark: value));


  Future<bool> setEnableNotifications(bool value) =>
      _persist(settings.value.copyWith(enableNotifications: value));

  Future<bool> setEnableReviewPrompts(bool value) =>
      _persist(settings.value.copyWith(enableReviewPrompts: value));

  Future<bool> setEnableSharePrompts(bool value) =>
      _persist(settings.value.copyWith(enableSharePrompts: value));

  void dispose() {
    settings.dispose();
    isLoading.dispose();
    lastError.dispose();
  }
}
