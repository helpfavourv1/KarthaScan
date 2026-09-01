import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../core/models/scan_document.dart';
import '../core/utils/constants.dart';
import '../core/utils/date_formatter.dart';
import '../l10n/app_localizations.dart';

class ScanListTile extends StatelessWidget {
  const ScanListTile({
    super.key,
    required this.document,
    required this.localeCode,
    this.onTap,
    this.onLongPress,
    this.onMenuAction,
    this.isSelected = false,
  });

  final ScanDocument document;
  final String localeCode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(String action)? onMenuAction;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final textTertiary = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final tileBg = isSelected ? accent.withValues(alpha: 0.08) : bg;
    final tileBorder = isSelected ? accent : border;

    final pageLabel = l10n.scanListPageCount(document.pageCount);
    final dateLabel = AppDateFormatter.formatSmartDate(document.updatedAt, localeCode: localeCode);
    final preview = document.ocrText.trim().isEmpty ? null : document.ocrText.trim().replaceAll(RegExp(r'\s+'), ' ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppShape.minTouchTarget),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: BorderRadius.circular(AppShape.cardRadius),
            border: Border.all(color: tileBorder, width: AppShape.cardBorderWidth),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppShape.cardRadius - 8),
                child: SizedBox(
                  width: 56,
                  height: 72,
                  child: _Thumbnail(path: document.thumbnailPath, isDark: isDark),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textPrimary, fontSize: AppTypography.title2Size, fontWeight: FontWeight.w600, height: AppTypography.title2LineHeight),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$pageLabel · $dateLabel',
                      style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, height: AppTypography.footnoteLineHeight),
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textTertiary, fontSize: AppTypography.captionSize, height: AppTypography.captionLineHeight),
                      ),
                    ],
                    if (document.tags.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xxs,
                        runSpacing: AppSpacing.xxs,
                        children: document.tags.take(3).map((tag) => _InlineTagLabel(tag: tag, isDark: isDark)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (onMenuAction != null)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: textSecondary),
                  tooltip: AppLocalizations.of(context).moreOptionsTooltip,
                  onSelected: (action) => onMenuAction!(action),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Row(children: [Icon(document.isFavorite ? Icons.star : Icons.star_border, color: accent, size: 20), const SizedBox(width: 8), Text(document.isFavorite ? 'Remove from Favorites' : 'Add to Favorites')]),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_outlined, size: 20), SizedBox(width: 8), Text(AppLocalizations.of(context).commonRename)])),
                    PopupMenuItem(value: 'folder', child: Row(children: [Icon(Icons.folder_outlined, size: 20), SizedBox(width: 8), Text(AppLocalizations.of(context).moveToFolderTitle)])),
                    PopupMenuItem(value: 'tags', child: Row(children: [Icon(Icons.label_outline, size: 20), SizedBox(width: 8), Text(AppLocalizations.of(context).addTagsAction)])),
                    PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 20), SizedBox(width: 8), Text(AppLocalizations.of(context).editDocumentAction)])),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.file_download_outlined, size: 20), SizedBox(width: 8), Text(AppLocalizations.of(context).exportTitle)])),
                    PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.ios_share, size: 20), SizedBox(width: 8), Text(AppLocalizations.of(context).commonShare)])),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 20), SizedBox(width: 8), Text(AppLocalizations.of(context).commonDelete)])),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path, required this.isDark});
  final String path;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: isDark ? AppColors.bgTertiaryDark : AppColors.bgTertiaryLight,
        alignment: Alignment.center,
        child: Icon(Icons.description_outlined, color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight, size: 20),
      ),
    );
  }
}

class _InlineTagLabel extends StatelessWidget {
  const _InlineTagLabel({required this.tag, required this.isDark});
  final String tag;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
      decoration: BoxDecoration(color: isDark ? AppColors.bgTertiaryDark : AppColors.bgTertiaryLight, borderRadius: BorderRadius.circular(AppShape.textInputRadius)),
      child: Text(tag, style: TextStyle(fontSize: AppTypography.captionSize, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
    );
  }
}
