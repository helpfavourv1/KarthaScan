import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'filter_service.dart' show FilterService;
import 'export_service.dart' show FilterType;
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

abstract final class PrintService {
  static Future<Uint8List> buildPdfBytes(
    List<String> pagePaths, {
    List<int>? pageIndices,
    FilterType filter = FilterType.none,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final pdf = pw.Document(creator: 'KatharScan');
    final indices = pageIndices ?? List<int>.generate(pagePaths.length, (i) => i);
    for (final idx in indices) {
      if (idx < 0 || idx >= pagePaths.length) continue;
      final file = File(pagePaths[idx]);
      if (!await file.exists()) continue;
      Uint8List bytes = await file.readAsBytes();
      if (filter != FilterType.none) {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final filtered = FilterService.applyToImage(decoded, filter);
            bytes = Uint8List.fromList(img.encodeJpg(filtered, quality: 92));
          }
        } catch (_) {}
      }
      final image = pw.MemoryImage(bytes);
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return await pdf.save();
  }
}
