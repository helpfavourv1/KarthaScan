// lib/widgets/empty_state.dart
//
// First launch: "Tap the camera to scan your first document." (Section 16
// file #29).
//
// Built as a reusable empty-state widget with that exact copy as the
// default, so the same widget also serves other empty moments (empty
// search results, an empty folder) with different copy passed in — per
// the frontend-design skill's guidance to treat emptiness as a moment for
// direction, not just an absence.
import 'package:flutter/material.dart';

import '../core/utils/constants.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.document_scanner_outlined,
    this.message = 'Tap the camera to scan your first document.',
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
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
