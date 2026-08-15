// lib/widgets/folder_list_tile.dart
//
// Folder card: name, document count, tap to open (Section 16 file #26).
import 'package:flutter/material.dart';

import '../core/models/folder.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class FolderListTile extends StatelessWidget {
  const FolderListTile({
    super.key,
    required this.folder,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  final Folder folder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final Color border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color tileBg = isSelected ? accent.withOpacity(0.08) : bg;
    final Color tileBorder = isSelected ? accent : border;

    final String countLabel = l10n.folderDocumentCount(folder.documentIds.length);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppShape.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: BorderRadius.circular(AppShape.cardRadius),
            border: Border.all(color: tileBorder, width: AppShape.cardBorderWidth),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (isSelected ? accent : (isDark ? AppColors.bgTertiaryDark : AppColors.bgTertiaryLight)),
                  borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                ),
                child: Icon(
                  Icons.folder_outlined,
                  color: isSelected ? Colors.white : accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: AppTypography.title2Size,
                        fontWeight: FontWeight.w600,
                        height: AppTypography.title2LineHeight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      countLabel,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: AppTypography.footnoteSize,
                        height: AppTypography.footnoteLineHeight,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
