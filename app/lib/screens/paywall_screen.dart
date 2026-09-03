// lib/screens/paywall_screen.dart
//
// Non-blocking upgrade path. Shows a single "Remove Ads" card.
// Reachable from settings or Pro-gated features (Section 16 file #40).
//
// NON-BLOCKING per Section 19's rule: this screen always has a plain
// close button, never a forced "you must subscribe" gate with no way out.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../core/providers/subscription_provider.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final SubscriptionProvider _subscriptionProvider;

  @override
  void initState() {
    super.initState();
    _subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: false);
  }

  Future<void> _purchase(AppLocalizations l10n) async {
    final ProductDetails? product = _subscriptionProvider.removeAdsProduct;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pricingLoadingError)),
      );
      return;
    }
    await _subscriptionProvider.purchase(product);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final Color success = isDark ? AppColors.successDark : AppColors.successLight;
    final Color error = isDark ? AppColors.errorDark : AppColors.errorLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            _subscriptionProvider.adsRemoved,
            _subscriptionProvider.purchaseFlowState,
            _subscriptionProvider.lastError,
            _subscriptionProvider.products,
          ]),
          builder: (BuildContext context, Widget? _) {
            if (_subscriptionProvider.adsRemoved.value) {
              return _buildAlreadyRemovedContent(l10n, textPrimary, textSecondary, success);
            }

            final bool purchasing =
                _subscriptionProvider.purchaseFlowState.value == PurchaseFlowState.inProgress;

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: <Widget>[
                Text(
                  l10n.paywallTitle,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: AppTypography.displaySize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.paywallSubtitle,
                  style: TextStyle(color: textSecondary, fontSize: AppTypography.bodySize),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(AppShape.cardRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.paywallTitle,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: AppTypography.title1Size,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.paywallFallbackPrice,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: AppTypography.title2Size,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...<String>[
                        l10n.paywallFeatureNoBanner,
                        l10n.paywallFeatureNoInterstitial,
                        l10n.paywallFeatureFreeForever,
                      ].map((String feature) => _featureRow(feature, textPrimary, Icons.check, accent)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_subscriptionProvider.purchaseFlowState.value == PurchaseFlowState.error &&
                    _subscriptionProvider.lastError.value != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      l10n.genericErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: error),
                    ),
                  ),
                SizedBox(
                  height: AppShape.buttonMinHeight,
                  child: ElevatedButton(
                    onPressed: purchasing ? null : () => _purchase(l10n),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                      ),
                    ),
                    child: purchasing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(l10n.continueButton),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: TextButton(
                    onPressed: purchasing ? null : () => _subscriptionProvider.restore(),
                    child: Text(l10n.restorePurchasesButton),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.paywallLegalText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAlreadyRemovedContent(
    AppLocalizations l10n,
    Color textPrimary,
    Color textSecondary,
    Color success,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle, color: success, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.paywallSuccessTitle,
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.paywallSuccessMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String label, Color textColor, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: textColor, fontSize: AppTypography.footnoteSize),
            ),
          ),
        ],
      ),
    );
  }
}
