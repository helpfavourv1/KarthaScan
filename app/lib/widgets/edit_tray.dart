import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'ios_pressable.dart';

class EditTray extends StatelessWidget {
  const EditTray({
    super.key,
    required this.onMarkup,
    required this.onSign,
    required this.onWatermark,
    required this.onOcr,
    required this.onConvert,
    required this.onCompress,
    required this.onRotate,
    required this.onResize,
    required this.onPages,
    required this.onFilter,
    required this.onCrop,
    required this.onText,
    required this.onNote,
    required this.onDate,
    required this.onCheckbox,
    required this.onPrint,
    required this.onEmail,
    required this.onErase,
  });

  final VoidCallback onMarkup;
  final VoidCallback onSign;
  final VoidCallback onWatermark;
  final VoidCallback onOcr;
  final VoidCallback onConvert;
  final VoidCallback onCompress;
  final VoidCallback onRotate;
  final VoidCallback onResize;
  final VoidCallback onPages;
  final VoidCallback onFilter;
  final VoidCallback onCrop;
  final VoidCallback onText;
  final VoidCallback onNote;
  final VoidCallback onDate;
  final VoidCallback onCheckbox;
  final VoidCallback onPrint;
  final VoidCallback onEmail;
  final VoidCallback onErase;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.85),
            border: Border(top: BorderSide(color: border, width: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _item(Icons.mode_edit_outline, 'Annotate', onMarkup, textPrimary, textSecondary),
                _item(Icons.draw_outlined, 'Sign', onSign, textPrimary, textSecondary),
                _item(Icons.text_fields, 'Watermark', onWatermark, textPrimary, textSecondary),
                _item(Icons.crop, 'OCR', onOcr, textPrimary, textSecondary),
                _item(Icons.file_download_outlined, 'Convert', onConvert, textPrimary, textSecondary),
                _item(Icons.compress, 'Compress', onCompress, textPrimary, textSecondary),
                _item(Icons.rotate_90_degrees_ccw, 'Rotate', onRotate, textPrimary, textSecondary),
                _item(Icons.aspect_ratio, 'Resize', onResize, textPrimary, textSecondary),
                _item(Icons.reorder, 'Pages', onPages, textPrimary, textSecondary),
                _item(Icons.filter_alt_outlined, 'Filter', onFilter, textPrimary, textSecondary),
                _item(Icons.crop_free, 'Crop', onCrop, textPrimary, textSecondary),
                _item(Icons.title, 'Text', onText, textPrimary, textSecondary),
                _item(Icons.note_outlined, 'Note', onNote, textPrimary, textSecondary),
                _item(Icons.date_range, 'Date', onDate, textPrimary, textSecondary),
                _item(Icons.check_box_outlined, 'Check', onCheckbox, textPrimary, textSecondary),
                _item(Icons.print_outlined, 'Print', onPrint, textPrimary, textSecondary),
                _item(Icons.mail_outline, 'Email', onEmail, textPrimary, textSecondary),
                _item(Icons.brush_outlined, 'Eraser', onErase, textPrimary, textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap, Color iconColor, Color textColor) {
    return IOSPressable(
      onTap: onTap,
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
