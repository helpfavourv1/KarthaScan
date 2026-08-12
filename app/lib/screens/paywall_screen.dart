// lib/screens/paywall_screen.dart
//
// Non-blocking upgrade path. Shows free vs Pro comparison. Reachable from
// settings or Pro-gated features (Section 16 file #40).
//
// COPY CORRECTIONS carried from earlier phases:
//   - OCR languages: "CJK, Hindi" not "CJK, Arabic, Hebrew, Hindi" — ML
//     Kit Text Recognition doesn't support Arabic/Hebrew script at all
//     (verified in Phase 2's ocr_service.dart). Arabic/Hebrew remain
//     interface languages only.
//   - No "direct Drive/iCloud upload" as a distinct Pro line item —
//     share_service.dart resolved that to the plain OS share sheet, free
//     for everyone (confirmed Option B). Cloud access isn't listed as a
//     Pro feature here because it isn't one.
//
// NON-BLOCKING per Section 19's rule: this screen always has a plain
// close button, never a forced "you must subscribe" gate with no way out.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../core/providers/subscription_provider.dart';
import '../core/utils/constants.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final SubscriptionProvider _subscriptionProvider;
  bool _yearlySelected = true;

  static const List<String> _freeFeatures = <String>[
    'Unlimited scanning',
    'Unlimited on-device OCR (Latin)',
    'No watermark, no account, no ads',
    'Folders & search',
    '5 export formats',
    'Dark mode',
  ];

  static const List<String> _proFeatures = <String>[
    'Advanced filters',
    'PDF password protection',
    'Signature overlay',
    'Custom tags & smart folders',
    'Batch export',
    'Device Migration',
    'Extra OCR languages (CJK, Hindi)',
  ];

  @override
  void initState() {
    super.initState();
    _subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: false);
  }

  Future<void> _purchase() async {
    final ProductDetails? product = _yearlySelected
        ? _subscriptionProvider.yearlyProduct
        : _subscriptionProvider.monthlyProduct;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pricing is still loading — try again in a moment.')),
      );
      return;
    }
    await _subscriptionProvider.purchase(product);
  }

  @override
  Widget build(BuildContext context) {
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
            _subscriptionProvider.isPro,
            _subscriptionProvider.purchaseFlowState,
            _subscriptionProvider.lastError,
            _subscriptionProvider.products,
          ]),
          builder: (BuildContext context, Widget? _) {
            if (_subscriptionProvider.isPro.value) {
              return _buildAlreadyProContent(textPrimary, textSecondary, success);
            }

            final bool purchasing =
                _subscriptionProvider.purchaseFlowState.value == PurchaseFlowState.inProgress;

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: <Widget>[
                Text(
                  'KatharScan Pro',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: AppTypography.displaySize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Core scanning and OCR are free forever. Pro unlocks power tools.',
                  style: TextStyle(color: textSecondary, fontSize: AppTypography.bodySize),
                ),
                const SizedBox(height: AppSpacing.lg),
                _comparisonTable(surface, textPrimary, textSecondary, accent),
                const SizedBox(height: AppSpacing.lg),
                _planPicker(surface, textPrimary, textSecondary, accent),
                const SizedBox(height: AppSpacing.md),
                if (_subscriptionProvider.purchaseFlowState.value == PurchaseFlowState.error &&
                    _subscriptionProvider.lastError.value != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      _subscriptionProvider.lastError.value!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: error),
                    ),
                  ),
                SizedBox(
                  height: AppShape.buttonMinHeight,
                  child: ElevatedButton(
                    onPressed: purchasing ? null : _purchase,
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
                        : const Text('Continue'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: TextButton(
                    onPressed: purchasing ? null : () => _subscriptionProvider.restore(),
                    child: const Text('Restore purchases'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Cancel anytime. We will never show you an ad, and we will '
                  'never lock a free feature behind a paywall.',
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

  Widget _buildAlreadyProContent(Color textPrimary, Color textSecondary, Color success) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle, color: success, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              "You're on KatharScan Pro",
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'All power tools are unlocked. Thank you for supporting KatharScan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonTable(Color surface, Color textPrimary, Color textSecondary, Color accent) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppShape.cardRadius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Free',
            style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: AppTypography.title2Size),
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._freeFeatures.map((String f) => _featureRow(f, textSecondary, Icons.check, textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          Divider(color: textSecondary.withOpacity(0.2)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Pro',
            style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: AppTypography.title2Size),
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._proFeatures.map((String f) => _featureRow(f, textPrimary, Icons.star, accent)),
        ],
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
          Expanded(child: Text(label, style: TextStyle(color: textColor, fontSize: AppTypography.footnoteSize))),
        ],
      ),
    );
  }

  Widget _planPicker(Color surface, Color textPrimary, Color textSecondary, Color accent) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _planCard(
            label: 'Monthly',
            price: _subscriptionProvider.monthlyProduct?.price ?? '\$0.99/mo',
            selected: !_yearlySelected,
            onTap: () => setState(() => _yearlySelected = false),
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _planCard(
            label: 'Yearly',
            price: _subscriptionProvider.yearlyProduct?.price ?? '\$9.99/yr',
            badge: 'Save ~15%',
            selected: _yearlySelected,
            onTap: () => setState(() => _yearlySelected = true),
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent,
          ),
        ),
      ],
    );
  }

  Widget _planCard({
    required String label,
    required String price,
    String? badge,
    required bool selected,
    required VoidCallback onTap,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppShape.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppShape.cardRadius),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(label, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                if (badge != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.xxs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)),
                    child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(price, style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize)),
          ],
        ),
      ),
    );
  }
}
