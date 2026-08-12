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
// signature, password) are separate widgets/screens per file #38's
// "format select → filter apply (Pro) → signature (Pro) → password (Pro)
// → share" sequence.
import 'package:flutter/material.dart';

import '../core/models/export_job.dart';
import '../core/utils/constants.dart';

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

const List<ExportFormatOption> kExportFormatOptions = <ExportFormatOption>[
  ExportFormatOption(
    format: ExportFormat.pdf,
    label: 'PDF',
    description: 'Best for sharing and printing',
    icon: Icons.picture_as_pdf_outlined,
  ),
  ExportFormatOption(
    format: ExportFormat.docx,
    label: 'Word (.docx)',
    description: 'Editable text document',
    icon: Icons.description_outlined,
  ),
  ExportFormatOption(
    format: ExportFormat.txt,
    label: 'Text (.txt)',
    description: 'Plain OCR text only',
    icon: Icons.notes_outlined,
  ),
  ExportFormatOption(
    format: ExportFormat.jpg,
    label: 'JPG',
    description: 'One image per page',
    icon: Icons.image_outlined,
  ),
  ExportFormatOption(
    format: ExportFormat.png,
    label: 'PNG',
    description: 'One image per page, lossless',
    icon: Icons.image_outlined,
  ),
];

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
            Text(
              'Export as',
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...kExportFormatOptions.map(
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
            children: <Widget>[
              Icon(option.icon, color: accent, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
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
