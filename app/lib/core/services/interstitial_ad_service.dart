import 'dart:convert';
import 'dart:io' show Platform;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_pacing_service.dart';

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
    if (_loading) return;
    _loading = true;
    await InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) { a.dispose(); _load(); },
            onAdFailedToShowFullScreenContent: (a, e) { a.dispose(); _load(); },
          );
        },
        onAdFailedToLoad: (e) { _ad = null; _loading = false; },
      ),
    );
  }

  Future<void> showIfAllowed() async {
    if (await _isAdsRemovedCached()) return;
    if (!AdPacingService.instance.canShowAd()) return;
    if (_ad == null) {
      await _load();
      if (_ad == null) return;
    }
    _ad!.show();
    await AdPacingService.instance.recordAdShown();
    _ad = null;
  }

  Future<void> showAfterScan() async {
    if (AdPacingService.instance.canShowAfterScan()) await showIfAllowed();
  }
  Future<void> showAfterExport() async {
    if (AdPacingService.instance.canShowAfterExport()) await showIfAllowed();
  }
  Future<void> showAfterConvert() async {
    if (AdPacingService.instance.canShowAfterConvert()) await showIfAllowed();
  }
  Future<void> showAfterIdle() async {
    if (AdPacingService.instance.canShowAfterIdle()) await showIfAllowed();
  }

  void preload() => _load();
  void dispose() => _ad?.dispose();
}
