// lib/widgets/export_dialog.dart
//
// Format selector: PDF / JPG / PNG / TXT / DOCX (Section 16 file #30).
//
// SCOPE CORRECTION: the blueprint's original purpose text says "Cloud
// options gated by Pro." That's stale language from before the confirmed
// resolution to share_service.dart's scope — the OS share sheet (which
// covers Drive/iCloud) is free-tier for everyone, so there's no separate
// "cloud option" left to gate. This widget is the plain format selector
// only; the actual Pro-gated steps in the export flow (filters,
// signature) are separate widgets/screens per file #38's
// "format select → filter apply (Pro) → signature (Pro) → share"
// sequence.
//
// LOCALIZATION: the format option list was originally a top-level `const`
// with labels/descriptions baked in at compile time. AppLocalizations
// needs a BuildContext, which isn't available for a compile-time const —
// so this is now a function computed inside build(), where context (and
// therefore l10n) is available.

import 'package:flutter/material.dart';

import '../core/models/export_job.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class ExportFormatOption {
  const ExportFormatOption({
    required this.format,
    required this.label,
    required this.description,
    required this.icon,
  });

  final ExportFormat format;
  final String label;
  final String description;
  final IconData icon;
}

List<ExportFormatOption> _exportFormatOptions(AppLocalizations l10n) {
  return <ExportFormatOption>[
    ExportFormatOption(
      format: ExportFormat.pdf,
      label: l10n.exportFormatPdfLabel,
      description: l10n.exportFormatPdfDescription,
      icon: Icons.picture_as_pdf_outlined,
    ),
    ExportFormatOption(
      format: ExportFormat.docx,
      label: l10n.exportFormatDocxLabel,
      description: l10n.exportFormatDocxDescription,
      icon: Icons.description_outlined,
    ),
    ExportFormatOption(
      format: ExportFormat.txt,
      label: l10n.exportFormatTxtLabel,
      description: l10n.exportFormatTxtDescription,
      icon: Icons.notes_outlined,
    ),
    ExportFormatOption(
      format: ExportFormat.jpg,
      label: l10n.exportFormatJpgLabel,
      description: l10n.exportFormatJpgDescription,
      icon: Icons.image_outlined,
    ),
    ExportFormatOption(
      format: ExportFormat.png,
      label: l10n.exportFormatPngLabel,
      description: l10n.exportFormatPngDescription,
      icon: Icons.image_outlined,
    ),
    ExportFormatOption(
      format: ExportFormat.csv,
      label: 'CSV',
      description: 'Spreadsheet data',
      icon: Icons.table_chart_outlined,
    ),
  ];
}

/// Shows the format picker as a modal bottom sheet and resolves with the
/// chosen [ExportFormat], or null if dismissed without a choice.
Future<ExportFormat?> showExportFormatSheet(BuildContext context) {
  return showModalBottomSheet<ExportFormat>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => const ExportDialog(),
  );
}

class ExportDialog extends StatelessWidget {
  const ExportDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;

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
          children: [
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
            Text(
              l10n.exportFormatSheetTitle,
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._exportFormatOptions(l10n).map(
              (ExportFormatOption option) => _FormatTile(
                option: option,
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                onTap: () => Navigator.of(context).pop(option.format),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.option,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  final ExportFormatOption option;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShape.buttonRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppShape.minTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Icon(option.icon, color: accent, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: AppTypography.bodySize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      option.description,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: AppTypography.footnoteSize,
                      ),
                    ),
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
