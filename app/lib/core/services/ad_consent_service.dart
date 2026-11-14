// lib/core/services/ad_consent_service.dart
//
// One gate in front of every ad. Google's consent SDK decides whether ads may
// be requested; this service only asks it, again and again where needed, and
// follows the answer. It adds no rule of its own.
//   1. (iOS) the App Tracking Transparency prompt has been answered, then
//   2. Google's consent form (UMP) runs where Google requires it, and
//   3. the SDK's canRequestAds() says whether ads may load.
// Banners and interstitials wait on [adsReady]. It can turn false again if
// Google later says ads may no longer be requested (consent withdrawn).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Where the consent check stands.
enum ConsentOutcome {
  /// The first check has not finished yet.
  pending,

  /// Google says ads may be requested.
  ready,

  /// Google answered and ads may not be requested (the person declined).
  blocked,

  /// Google could not be asked, or did not answer; ask again later.
  unknown,
}

/// Turns what Google's SDK reported into an outcome. Pure, so it is easy to test.
/// [canRequestAds] is the SDK's answer (null when asking it threw);
/// [infoUpdateFailed] is true when refreshing the consent state failed (offline, etc.).
/// The SDK's own answer always wins: a stored "yes" still counts when the refresh failed.
ConsentOutcome consentOutcome({required bool? canRequestAds, required bool infoUpdateFailed}) {
  if (canRequestAds == true) return ConsentOutcome.ready;
  if (canRequestAds == null || infoUpdateFailed) return ConsentOutcome.unknown;
  return ConsentOutcome.blocked;
}

/// The calls the service makes to Google's SDK, so tests can replace them.
abstract class ConsentGateway {
  /// Refreshes the consent state and shows Google's form if it is required.
  /// Returns true when the refresh failed.
  Future<bool> refreshAndShowFormIfRequired();

  /// Refreshes the consent state only, with no form. Returns true when it failed.
  Future<bool> refreshOnly();

  Future<bool> canRequestAds();
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptionsForm();
  Future<void> initializeAds();
}

class GoogleConsentGateway implements ConsentGateway {
  const GoogleConsentGateway();

  Future<bool> _update() {
    final Completer<bool> failed = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        if (!failed.isCompleted) failed.complete(false);
      },
      (FormError error) {
        debugPrint('Consent info update failed: ${error.message}');
        if (!failed.isCompleted) failed.complete(true);
      },
    );
    return failed.future;
  }

  @override
  Future<bool> refreshOnly() => _update();

  @override
  Future<bool> refreshAndShowFormIfRequired() async {
    final bool failed = await _update();
    if (failed) return true;
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
        if (error != null) debugPrint('Consent form: ${error.message}');
      });
    } catch (e) {
      debugPrint('Consent form failed: $e');
    }
    return false;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptionsForm() async {
    await ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) debugPrint('Privacy options: ${error.message}');
    });
  }

  @override
  Future<void> initializeAds() async {
    await MobileAds.instance.initialize();
  }
}

class AdConsentService {
  AdConsentService._() : _gateway = const GoogleConsentGateway();
  @visibleForTesting
  AdConsentService.forTest(this._gateway);
  static final AdConsentService instance = AdConsentService._();

  final ConsentGateway _gateway;

  /// True while Google says ads may be requested. Can go back to false.
  final ValueNotifier<bool> adsReady = ValueNotifier<bool>(false);

  /// Where the check stands; the banner uses it to give back its space once
  /// Google has said no (or could not be asked).
  final ValueNotifier<ConsentOutcome> outcome = ValueNotifier<ConsentOutcome>(ConsentOutcome.pending);

  /// True when the person must be offered a way to change their consent.
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  bool _started = false;
  bool _adsInitialized = false;
  bool _busy = false;

  /// Runs consent and then starts the ads SDK. Safe to call more than once.
  /// Call it only after the iOS tracking prompt has been answered.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _run(showForm: true);
  }

  /// Asks Google again. Called when the app returns to the foreground, so a
  /// failed or unfinished check is retried and a withdrawn consent is noticed.
  /// Does nothing before [start] (the tracking prompt may not be answered yet).
  Future<void> recheck() async {
    if (!_started) return;
    // Show Google's form again only if the last answer was "could not ask";
    // otherwise just read the current answer.
    await _run(showForm: outcome.value == ConsentOutcome.unknown || outcome.value == ConsentOutcome.pending);
  }

  Future<void> _run({required bool showForm}) async {
    if (_busy) return;
    _busy = true;
    try {
      bool failed;
      try {
        failed = showForm ? await _gateway.refreshAndShowFormIfRequired() : await _gateway.refreshOnly();
      } catch (e) {
        debugPrint('Consent refresh failed: $e');
        failed = true;
      }
      await _refreshPrivacyOptions();
      bool? can;
      try {
        can = await _gateway.canRequestAds();
      } catch (e) {
        debugPrint('canRequestAds failed: $e');
      }
      await _apply(consentOutcome(canRequestAds: can, infoUpdateFailed: failed));
    } finally {
      _busy = false;
    }
  }

  Future<void> _apply(ConsentOutcome result) async {
    if (result == ConsentOutcome.ready && !_adsInitialized) {
      try {
        await _gateway.initializeAds();
        _adsInitialized = true;
      } catch (e) {
        debugPrint('Ads start failed: $e');
        outcome.value = ConsentOutcome.unknown;
        adsReady.value = false;
        return;
      }
    }
    outcome.value = result;
    adsReady.value = result == ConsentOutcome.ready;
  }

  Future<void> _refreshPrivacyOptions() async {
    try {
      privacyOptionsRequired.value = await _gateway.privacyOptionsRequired();
    } catch (e) {
      debugPrint('Privacy options status failed: $e');
    }
  }

  /// Opens Google's privacy options form (Settings entry where required) and
  /// then reads Google's answer again, so a change takes effect at once.
  Future<void> showPrivacyOptions() async {
    try {
      await _gateway.showPrivacyOptionsForm();
    } catch (e) {
      debugPrint('Privacy options failed: $e');
    }
    await _run(showForm: false);
  }

  /// Platform note for callers: on Android there is no tracking prompt.
  static bool get hasTrackingPrompt => Platform.isIOS;
}
