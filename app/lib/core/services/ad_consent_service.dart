// lib/core/services/ad_consent_service.dart
//
// One gate in front of every ad. Ads may only load once:
//   1. (iOS) the App Tracking Transparency prompt has been answered, and
//   2. Google's consent form (UMP) has run, for people in the EEA/UK, and
//      the SDK says ads may be requested.
// Banners and interstitials wait on [adsReady] instead of loading on their own.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConsentService {
  AdConsentService._();
  static final AdConsentService instance = AdConsentService._();

  /// True once ads are allowed to be requested.
  final ValueNotifier<bool> adsReady = ValueNotifier<bool>(false);

  /// True when the person must be offered a way to change their consent.
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  bool _started = false;

  /// Runs consent and then starts the ads SDK. Safe to call more than once.
  /// Call it only after the iOS tracking prompt has been answered.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final Completer<void> infoDone = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
              if (error != null) debugPrint('Consent form: ${error.message}');
            });
          } catch (e) {
            debugPrint('Consent form failed: $e');
          }
          if (!infoDone.isCompleted) infoDone.complete();
        },
        (FormError error) {
          debugPrint('Consent info update failed: ${error.message}');
          if (!infoDone.isCompleted) infoDone.complete();
        },
      );
      await infoDone.future;
      await _refreshPrivacyOptions();
      // If the consent state is already known from an earlier launch,
      // canRequestAds() is true even when the update above failed offline.
      if (await ConsentInformation.instance.canRequestAds()) {
        await MobileAds.instance.initialize();
        adsReady.value = true;
      }
    } catch (e) {
      debugPrint('Ad consent start failed: $e');
      _started = false; // allow a later retry
    }
  }

  Future<void> _refreshPrivacyOptions() async {
    try {
      final PrivacyOptionsRequirementStatus status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      privacyOptionsRequired.value = status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {}
  }

  /// Opens Google's privacy options form (Settings entry for EEA/UK).
  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) debugPrint('Privacy options: ${error.message}');
      });
      if (!adsReady.value && await ConsentInformation.instance.canRequestAds()) {
        await MobileAds.instance.initialize();
        adsReady.value = true;
      }
    } catch (e) {
      debugPrint('Privacy options failed: $e');
    }
  }

  /// Platform note for callers: on Android there is no tracking prompt.
  static bool get hasTrackingPrompt => Platform.isIOS;
}
