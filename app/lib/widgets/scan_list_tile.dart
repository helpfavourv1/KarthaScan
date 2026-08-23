// lib/widgets/scan_list_tile.dart
//
// Home screen card: thumbnail, title, page count, date, OCR text preview,
// 3-dots menu (rename, move to folder, add tags, export, share, delete, favorite).

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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final Color border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color textTertiary = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final Color tileBg = isSelected ? accent.withValues(alpha: 0.08) : bg;
    final Color tileBorder = isSelected ? accent : border;

    final String pageLabel = l10n.scanListPageCount(document.pageCount);
    final String dateLabel =
        AppDateFormatter.formatSmartDate(document.updatedAt, localeCode: localeCode);
    final String? preview = document.ocrText.trim().isEmpty
        ? null
        : document.ocrText.trim().replaceAll(RegExp(r'\s+'), ' ');

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
            children: <Widget>[
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
                  children: <Widget>[
                    Text(
                      document.title,
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
                      '$pageLabel · $dateLabel',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: AppTypography.footnoteSize,
                        height: AppTypography.footnoteLineHeight,
                      ),
                    ),
                    if (preview != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textTertiary,
                          fontSize: AppTypography.captionSize,
                          height: AppTypography.captionLineHeight,
                        ),
                      ),
                    ],
                    if (document.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xxs,
                        runSpacing: AppSpacing.xxs,
                        children: document.tags
                            .take(3)
                            .map((String tag) => _InlineTagLabel(tag: tag, isDark: isDark))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // 3-dots menu button
              if (onMenuAction != null)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: textSecondary),
                  tooltip: 'More options',
                  onSelected: (String action) => onMenuAction!(action),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'favorite',
                      child: Row(
                        children: <Widget>[
                          Icon(
                            document.isFavorite ? Icons.star : Icons.star_border,
                            color: accent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(document.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.edit_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('Rename'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'folder',
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.folder_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('Move to Folder'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'tags',
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.label_outline, size: 20),
                          SizedBox(width: 8),
                          Text('Add Tags'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'export',
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.file_download_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('Export'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'share',
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.ios_share, size: 20),
                          SizedBox(width: 8),
                          Text('Share'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.delete_outline, size: 20),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
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
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        return Container(
          color: isDark ? AppColors.bgTertiaryDark : AppColors.bgTertiaryLight,
          alignment: Alignment.center,
          child: Icon(
            Icons.description_outlined,
            color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight,
            size: 20,
          ),
        );
      },
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
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgTertiaryDark : AppColors.bgTertiaryLight,
        borderRadius: BorderRadius.circular(AppShape.textInputRadius),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: AppTypography.captionSize,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        ),
      ),
    );
  }
}
