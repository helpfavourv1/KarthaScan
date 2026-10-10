import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Bundled Noto fonts for generated PDFs, so Cyrillic, Greek and Arabic text
/// is not drawn as empty boxes. The default PDF fonts only cover Latin.
class PdfFonts {
  PdfFonts._();

  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> theme() async {
    final cached = _theme;
    if (cached != null) return cached;
    try {
      final base = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final arabic = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      return _theme = pw.ThemeData.withFont(
        base: base,
        bold: base,
        italic: base,
        boldItalic: base,
        fontFallback: [arabic],
      );
    } catch (_) {
      // Export must never fail because a font could not load.
      return pw.ThemeData.base();
    }
  }
}
