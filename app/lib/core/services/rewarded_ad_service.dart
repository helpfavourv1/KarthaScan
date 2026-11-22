import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_consent_service.dart';
import 'interstitial_ad_service.dart';
import 'reward_service.dart';

/// Loads and shows the rewarded video behind "Watch an ad, get 6 hours ad-free".
/// The person always chooses to watch; the reward is granted only when Google
/// reports the video was earned.
class RewardedAdService {
  RewardedAdService._();
  static final RewardedAdService instance = RewardedAdService._();

  // Google's test Rewarded units. Replace with the real ones before launch.
  static const String _testAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const String _testIOS = 'ca-app-pub-3940256099942544/1712485313';

  RewardedAd? _ad;
  bool _loading = false;
  bool _waitingForConsent = false;

  /// True while a rewarded ad is loaded and ready to play.
  final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  String get _adUnitId => Platform.isAndroid ? _testAndroid : _testIOS;

  /// Loads an ad when one could be offered. Safe to call often.
  Future<void> preload() async {
    try {
      if (_ad != null || _loading) return;
      if (await InterstitialAdService.instance.adsRemovedCached()) return;
      if (RewardService.instance.isActive() || RewardService.instance.capReached()) return;
      if (!AdConsentService.instance.adsReady.value) {
        if (!_waitingForConsent) {
          _waitingForConsent = true;
          void onReady() {
            if (!AdConsentService.instance.adsReady.value) return;
            AdConsentService.instance.adsReady.removeListener(onReady);
            _waitingForConsent = false;
            unawaited(preload());
          }
          AdConsentService.instance.adsReady.addListener(onReady);
        }
        return;
      }
      _loading = true;
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _ad = ad;
            _loading = false;
            loaded.value = true;
          },
          onAdFailedToLoad: (LoadAdError e) {
            _ad = null;
            _loading = false;
            loaded.value = false;
          },
        ),
      );
    } catch (_) {
      _loading = false;
    }
  }

  /// Plays the ad. Returns true when the reward was earned and granted.
  Future<bool> show() async {
    final RewardedAd? ad = _ad;
    if (ad == null) {
      unawaited(preload());
      return false;
    }
    _ad = null;
    loaded.value = false;
    bool earned = false;
    final Completer<bool> done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (RewardedAd a) {
        a.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (RewardedAd a, AdError e) {
        a.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (AdWithoutView view, RewardItem item) {
        earned = true;
      });
    } catch (_) {
      if (!done.isCompleted) done.complete(false);
    }
    final bool ok = await done.future;
    if (ok) await RewardService.instance.grant();
    unawaited(preload());
    return ok;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
    loaded.value = false;
  }
}
