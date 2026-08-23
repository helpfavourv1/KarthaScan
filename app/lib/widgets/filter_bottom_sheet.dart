// lib/widgets/filter_bottom_sheet.dart
//
// Grayscale, B&W, color enhance, shadow removal — all free (Section 16
// file #31).
//
// This widget is a SELECTOR only — it returns which FilterType the user
// picked. FilterType itself is defined in core/services/export_service.dart
// (not here) because that core/ file needs it too, and core/ must never
// depend on widgets/ — so the dependency runs the other way: this widget
// imports the enum from there. Actually applying the filter to page
// images is export_service.dart's job, wired up when export_screen.dart
// (Phase 5) orchestrates the full "format → filter → signature →
// password → share" flow — this widget doesn't perform image processing
// itself.
//
// LOCALIZATION: the option list was originally a top-level `const` with
// labels baked in at compile time. AppLocalizations needs a BuildContext,
// unavailable for a compile-time const — so this is now a function
// computed inside build(), where l10n is available.

import 'package:flutter/material.dart';

import '../core/services/export_service.dart' show FilterType;
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class FilterOption {
  const FilterOption({required this.type, required this.label, required this.icon});

  final FilterType type;
  final String label;
  final IconData icon;
}

List<FilterOption> _filterOptions(AppLocalizations l10n) {
  return <FilterOption>[
    FilterOption(type: FilterType.none, label: l10n.filterOriginal, icon: Icons.crop_original),
    FilterOption(type: FilterType.grayscale, label: l10n.filterGrayscale, icon: Icons.filter_b_and_w),
    FilterOption(type: FilterType.blackAndWhite, label: l10n.filterBlackAndWhite, icon: Icons.contrast),
    FilterOption(type: FilterType.colorEnhance, label: l10n.filterColorEnhance, icon: Icons.auto_awesome),
    FilterOption(type: FilterType.shadowRemoval, label: l10n.filterShadowRemoval, icon: Icons.wb_shade),
  ];
}

/// Shows the filter picker as a modal bottom sheet. [current] pre-selects
/// the active filter (checkmark). All options are always tappable.
Future<FilterType?> showFilterSheet(
  BuildContext context, {
  required FilterType current,
}) {
  return showModalBottomSheet<FilterType>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FilterBottomSheet(
      current: current,
    ),
  );
}

class FilterBottomSheet extends StatelessWidget {
  const FilterBottomSheet({
    super.key,
    required this.current,
  });

  final FilterType current;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final Color border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
            topRight: Radius.circular(AppShape.bottomSheetTopRadius),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                Text(
                  l10n.filterSheetTitle,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: AppTypography.title1Size,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._filterOptions(l10n).map((FilterOption option) {
              final bool selected = option.type == current;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(option.type),
                  borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: AppShape.minTouchTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(option.icon, color: accent, size: 22),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: AppTypography.bodySize,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (selected) Icon(Icons.check, color: accent, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
