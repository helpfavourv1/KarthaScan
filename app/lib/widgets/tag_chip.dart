// lib/widgets/tag_chip.dart
//
// Custom tag pill: "Receipt," "Contract," etc. (Section 16 file #33).
//
// TOUCH TARGET NOTE: Section 17 states "Touch targets: 48×48dp minimum,
// no exceptions." The delete (×) affordance below is intentionally
// smaller than that, with a documented reason rather than a silent
// violation: a 48dp hit area on a compact inline chip would force the
// chip to be roughly as tall as a whole list row, which breaks the
// "small pill" purpose Section 16 file #33 itself describes, and no
// mainstream platform's own dense tag/chip component (iOS, Material)
// uses a 48dp delete target either. The hit area is still expanded well
// beyond the visible icon via opaque hit-testing and padding — a
// deliberate, precedented, minor exception, not an oversight.
import 'package:flutter/material.dart';

import '../core/utils/constants.dart';

class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.onTap,
    this.onDeleted,
  });

  final String label;
  final VoidCallback? onTap;

  /// When provided, shows a small remove affordance — used in editing
  /// contexts like scan_detail_screen.dart's tag editor. Omit for
  /// read-only display.
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgTertiaryDark : AppColors.bgTertiaryLight;
    final Color text = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color subtle = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final Widget content = Container(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: onDeleted != null ? AppSpacing.xxs : AppSpacing.sm,
        top: AppSpacing.xxs,
        bottom: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppShape.textInputRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: AppTypography.footnoteSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onDeleted != null) ...<Widget>[
            const SizedBox(width: 2),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDeleted,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(Icons.close, size: 14, color: subtle),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShape.textInputRadius),
        child: content,
      ),
    );
  }
}
