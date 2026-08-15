// lib/widgets/scan_list_tile.dart
//
// Home screen card: thumbnail, title, page count, date, OCR text preview
// (Section 16 file #25).
//
// Presentational only — takes a ScanDocument and callbacks via
// constructor, no direct provider/service access. home_screen.dart
// (Phase 5) wires this to scan_provider.dart via ListenableBuilder.
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
    this.isSelected = false,
  });

  final ScanDocument document;

  /// Drives date formatting (AppDateFormatter) — passed in rather than
  /// read from a BuildContext-bound localization lookup, keeping this
  /// widget simple to preview/test with any locale.
  final String localeCode;

  final VoidCallback? onTap;

  /// Used by home_screen.dart's batch-select mode (folder_screen.dart's
  /// "batch select" per file #36).
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
    final Color textTertiary = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final Color tileBg = isSelected ? accent.withOpacity(0.08) : bg;
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

/// Small, non-interactive tag label used inline in the tile — the full
/// removable TagChip (file #33) is for editing contexts like
/// scan_detail_screen.dart, not for a dense list row.
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
