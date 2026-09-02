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
  static const String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBannerAd());
  }

  void _initBannerAd() {
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: false);
    if (subscriptionProvider.adsRemoved.value) return;

    _bannerAd = BannerAd(
      adUnitId: !kReleaseMode ? _testBannerId : _testBannerId, // TODO: Replace with real ID before store submission
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
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: true);
    if (subscriptionProvider.adsRemoved.value || _bannerAd == null || !_isAdLoaded) {
      return const SizedBox.shrink();
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
