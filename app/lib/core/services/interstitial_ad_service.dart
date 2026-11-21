import 'dart:async' show Completer, unawaited;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_consent_service.dart';
import 'ad_pacing_service.dart';
import 'modal_moment_gate.dart';

class InterstitialAdService {
  InterstitialAdService._();
  static final InterstitialAdService instance = InterstitialAdService._();

  static const String _testAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testIOS = 'ca-app-pub-3940256099942544/4411468910';

  InterstitialAd? _ad;
  bool _loading = false;

  String get _adUnitId => Platform.isAndroid ? _testAndroid : _testIOS;

  Future<bool> _isAdsRemovedCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString('katharscan.user_settings.v1');
      if (s == null) return false;
      return (jsonDecode(s) as Map)['adsRemoved'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    // Never request an ad before the tracking prompt and consent form are done.
    if (!AdConsentService.instance.adsReady.value) return;
    if (_loading) return;
    _loading = true;
    final Completer<void> done = Completer<void>();
    await InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          if (!done.isCompleted) done.complete();
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) { a.dispose(); ModalMomentGate.instance.release(hold: const Duration(seconds: 3)); _load(); },
            onAdFailedToShowFullScreenContent: (a, e) { a.dispose(); ModalMomentGate.instance.release(); _load(); },
          );
        },
        onAdFailedToLoad: (e) { _ad = null; _loading = false; if (!done.isCompleted) done.complete(); },
      ),
    );
    // Wait for the answer, but never longer than 8 seconds.
    await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
  }

  /// Called when the person finishes a counted action. It adds one to the
  /// tally and, if an ad is pending and allowed, shows it.
  Future<void> onAction() async {
    if (await _isAdsRemovedCached()) return;
    final bool attempt = await AdPacingService.instance.registerAction();
    if (!attempt) return;
    await _tryShow();
  }

  Future<void> _tryShow() async {
    if (!AdConsentService.instance.adsReady.value) {
      _ad?.dispose();
      _ad = null;
      await AdPacingService.instance.recordFailedAttempt();
      return;
    }
    if (_ad == null) {
      await _load();
      if (_ad == null) {
        await AdPacingService.instance.recordFailedAttempt();
        return;
      }
    }
    // Not in the same moment as the review dialog.
    if (!ModalMomentGate.instance.tryAcquire()) {
      await AdPacingService.instance.recordFailedAttempt();
      return;
    }
    _ad!.show();
    await AdPacingService.instance.recordAdShown();
    _ad = null;
  }

  bool _waitingForConsent = false;

  Future<void> preload() async {
    if (await _isAdsRemovedCached()) return;
    if (!AdConsentService.instance.adsReady.value) {
      // Try again as soon as the tracking prompt and consent form are done.
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
    await _load();
  }
  void dispose() => _ad?.dispose();
}

/// Counts one finished action toward the next full-screen ad.
void countAdAction() => unawaited(InterstitialAdService.instance.onAction());
