import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The PDF library cannot shape Hindi and other joined scripts, and the
/// bundled fonts have no Hebrew or Thai. Lines in those scripts are drawn with
/// the phone's own text engine and placed in the PDF as pictures.
class ComplexScriptText {
  ComplexScriptText._();

  static bool isComplexRune(int c) =>
      (c >= 0x0590 && c <= 0x05FF) || // Hebrew
      (c >= 0x0600 && c <= 0x06FF) || // Arabic (needs joining; checked on a device: the PDF library draws it reversed and unjoined)
      (c >= 0x0750 && c <= 0x077F) || // Arabic Supplement
      (c >= 0x08A0 && c <= 0x08FF) || // Arabic Extended-A
      (c >= 0xFB50 && c <= 0xFDFF) || // Arabic presentation forms A
      (c >= 0xFE70 && c <= 0xFEFF) || // Arabic presentation forms B
      (c >= 0x0900 && c <= 0x0DFF) || // Devanagari .. Malayalam
      (c >= 0x0E00 && c <= 0x0EFF) || // Thai, Lao
      (c >= 0xFB1D && c <= 0xFB4F); // Hebrew presentation forms

  static bool hasComplex(String text) {
    for (final int c in text.runes) {
      if (c >= 0x0590 && isComplexRune(c)) return true;
    }
    return false;
  }

  static bool _isRtl(String text) {
    for (final int c in text.runes) {
      if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF)) return true;
      if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || isComplexRune(c)) return false;
    }
    return false;
  }

  /// A picture of [text] wrapped to [maxWidth] PDF points, or null when it
  /// cannot be drawn (the caller then falls back to plain text).
  static Future<pw.Widget?> render(String text, {required double fontSize, required double maxWidth, double scale = 2.5}) async {
    try {
      final bool rtl = _isRtl(text);
      final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        textAlign: rtl ? ui.TextAlign.right : ui.TextAlign.left,
        fontSize: fontSize * scale,
      ))
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: fontSize * scale))
        ..addText(text);
      final ui.Paragraph paragraph = builder.build()..layout(ui.ParagraphConstraints(width: maxWidth * scale));
      final int w = (maxWidth * scale).ceil();
      final int h = paragraph.height.ceil().clamp(1, 20000);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawParagraph(paragraph, ui.Offset.zero);
      final ui.Image image = await recorder.endRecording().toImage(w, h);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      return pw.Image(
        pw.MemoryImage(data.buffer.asUint8List()),
        width: w / scale,
        height: h / scale,
      );
    } catch (_) {
      return null;
    }
  }

  /// A paragraph or table cell: a picture when [text] has joined scripts,
  /// ordinary selectable text otherwise.
  static Future<pw.Widget> paragraph(String text, {double fontSize = 12, double maxWidth = 480}) async {
    if (hasComplex(text)) {
      final pw.Widget? picture = await render(text, fontSize: fontSize, maxWidth: maxWidth);
      if (picture != null) return pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: picture);
    }
    return pw.Paragraph(text: text, style: pw.TextStyle(fontSize: fontSize));
  }

  /// Width available for text on an A4 page with its default margins.
  static double get a4TextWidth => PdfPageFormat.a4.availableWidth;
}
