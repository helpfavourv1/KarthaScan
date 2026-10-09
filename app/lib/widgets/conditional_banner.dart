import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../core/providers/subscription_provider.dart';

class ConditionalBanner extends StatefulWidget {
  const ConditionalBanner({super.key});

  @override
  State<ConditionalBanner> createState() => _ConditionalBannerState();
}

class _ConditionalBannerState extends State<ConditionalBanner> {
  // Google's official test banner units (Android and iOS differ).
  static String get _testBannerId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';
  // Test IDs are kept until launch — replace with the production AdMob banner IDs before store submission
  static String get _prodBannerId => _testBannerId;
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  SubscriptionProvider? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBannerAd());
  }

  void _onAdsRemovedChanged() {
    if (_subscription?.adsRemoved.value != true) return;
    _bannerAd?.dispose();
    _bannerAd = null;
    if (mounted) setState(() => _isAdLoaded = false);
  }

  void _initBannerAd() {
    if (!mounted) return;
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: false);
    _subscription = subscriptionProvider;
    subscriptionProvider.adsRemoved.addListener(_onAdsRemovedChanged);
    if (subscriptionProvider.adsRemoved.value) return;

    _bannerAd = BannerAd(
      adUnitId: kReleaseMode ? _prodBannerId : _testBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('$ad loaded.');
          if (mounted) setState(() => _isAdLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _subscription?.adsRemoved.removeListener(_onAdsRemovedChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: true);
    if (subscriptionProvider.adsRemoved.value || _bannerAd == null || !_isAdLoaded) {
      return const SafeArea(child: SizedBox.shrink());
    }
    return SafeArea(
      child: SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}
