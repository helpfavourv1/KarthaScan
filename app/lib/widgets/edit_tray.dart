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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.fab,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(Icons.mode_edit_outline, 'Annotate', onMarkup),
            _item(Icons.draw_outlined, 'Sign', onSign),
            _item(Icons.text_fields, 'Watermark', onWatermark),
            _item(Icons.crop, 'OCR', onOcr),
            _item(Icons.file_download_outlined, 'Convert', onConvert),
            _item(Icons.compress, 'Compress', onCompress),
            _item(Icons.rotate_90_degrees_ccw, 'Rotate', onRotate),
            _item(Icons.aspect_ratio, 'Resize', onResize),
            _item(Icons.reorder, 'Pages', onPages),
            _item(Icons.filter_alt_outlined, 'Filter', onFilter),
            _item(Icons.crop_free, 'Crop', onCrop),
            _item(Icons.title, 'Text', onText),
            _item(Icons.note_outlined, 'Note', onNote),
            _item(Icons.date_range, 'Date', onDate),
            _item(Icons.check_box_outlined, 'Check', onCheckbox),
            _item(Icons.print_outlined, 'Print', onPrint),
            _item(Icons.mail_outline, 'Email', onEmail),
            _item(Icons.brush_outlined, 'Eraser', onErase),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap) {
    return IOSPressable(
      onTap: onTap,
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
