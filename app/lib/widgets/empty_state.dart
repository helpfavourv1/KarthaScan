// lib/widgets/empty_state.dart
//
// Reusable empty state with SVG illustration.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData? icon;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final String resolvedMessage = message ?? l10n.emptyStateDefaultMessage;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SvgPicture.string(
              _emptyStateSvg,
              width: 160,
              height: 160,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              resolvedMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textSecondary,
                fontSize: AppTypography.bodySize,
                height: AppTypography.bodyLineHeight,
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppShape.buttonMinHeight,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const String _emptyStateSvg = '''
<svg width="160" height="160" viewBox="0 0 160 160" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="30" y="15" width="100" height="130" rx="14" fill="#007AFF" fill-opacity="0.06"/>
  <rect x="45" y="38" width="70" height="6" rx="3" fill="#007AFF" fill-opacity="0.15"/>
  <rect x="45" y="52" width="50" height="6" rx="3" fill="#007AFF" fill-opacity="0.15"/>
  <rect x="45" y="66" width="60" height="6" rx="3" fill="#007AFF" fill-opacity="0.15"/>
  <rect x="45" y="86" width="70" height="40" rx="8" fill="#007AFF" fill-opacity="0.08"/>
  <circle cx="122" cy="42" r="18" fill="#007AFF" fill-opacity="0.10"/>
  <path d="M115 42L120 47L129 37" stroke="#007AFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.35"/>
</svg>
''';
