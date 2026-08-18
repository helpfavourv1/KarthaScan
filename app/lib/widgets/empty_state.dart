// lib/widgets/empty_state.dart
//
// First launch: "Tap the camera to scan your first document." (Section 16
// file #29).
//
// Built as a reusable empty-state widget with that copy as the default,
// so the same widget also serves other empty moments (empty search
// results, an empty folder) with different copy passed in — per the
// frontend-design skill's guidance to treat emptiness as a moment for
// direction, not just an absence.
//
// LOCALIZATION: [message] is nullable rather than defaulting to a literal
// string — a constructor default value must be a compile-time constant,
// and AppLocalizations.of(context) needs a BuildContext that isn't
// available at that point. The real default is resolved in build()
// instead, via `message ?? AppLocalizations.of(context).emptyStateDefaultMessage`.
import 'package:flutter/material.dart';

import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.document_scanner_outlined,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;

  /// When null, falls back to Section 16 file #29's exact required copy
  /// (localized) — see the file header for why this can't be a
  /// constructor default value directly.
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
            Icon(icon, size: 48, color: textSecondary),
            const SizedBox(height: AppSpacing.md),
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
