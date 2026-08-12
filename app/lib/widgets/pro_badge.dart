// lib/widgets/pro_badge.dart
//
// "Pro" chip on premium-locked UI elements (Section 16 file #28).
import 'package:flutter/material.dart';

import '../core/utils/constants.dart';

class ProBadge extends StatelessWidget {
  const ProBadge({super.key, this.onTap});

  /// Typically navigates to paywall_screen.dart. Optional so this can
  /// also be used as a plain visual indicator with no action attached.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    final Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(AppShape.textInputRadius),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          color: Colors.white,
          fontSize: AppTypography.captionSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );

    if (onTap == null) return chip;

    // The badge itself stays visually small (it's a label, not a primary
    // control), but the tappable area is expanded via opaque hit-testing
    // and padding so it still reaches a reasonable target size without
    // inflating the chip's footprint next to whatever locked feature it
    // labels.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: chip,
      ),
    );
  }
}
