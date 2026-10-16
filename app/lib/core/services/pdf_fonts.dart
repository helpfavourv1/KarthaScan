import 'dart:io' show File;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'remote_fonts.dart';

/// Bundled Noto fonts for generated PDFs, so Cyrillic, Greek and Arabic text
/// is not drawn as empty boxes. The default PDF fonts only cover Latin.
/// Chinese, Japanese and Korean fonts are downloaded the first time the text
/// needs them (see [RemoteFonts]).
class PdfFonts {
  PdfFonts._();

  static pw.Font? _latin;
  static pw.Font? _arabic;
  static final Map<String, pw.Font> _remote = <String, pw.Font>{};

  /// [text] is everything the PDF is going to draw, used to pick the fonts.
  static Future<pw.ThemeData> theme({String text = ''}) async {
    try {
      final pw.Font latin = _latin ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final pw.Font arabic = _arabic ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      final List<pw.Font> fallback = <pw.Font>[arabic];
      for (final RemoteFont f in RemoteFonts.neededFor(text)) {
        final pw.Font? font = await _remoteFont(f);
        if (font != null) fallback.add(font);
      }
      return pw.ThemeData.withFont(
        base: latin,
        bold: latin,
        italic: latin,
        boldItalic: latin,
        fontFallback: fallback,
      );
    } catch (_) {
      // Export must never fail because a font could not load.
      return pw.ThemeData.base();
    }
  }

  static Future<pw.Font?> _remoteFont(RemoteFont f) async {
    final pw.Font? cached = _remote[f.fileName];
    if (cached != null) return cached;
    final File? file = await RemoteFonts.ensure(f);
    if (file == null) return null;
    try {
      final pw.Font font = pw.Font.ttf((await file.readAsBytes()).buffer.asByteData());
      return _remote[f.fileName] = font;
    } catch (_) {
      return null;
    }
  }
}
