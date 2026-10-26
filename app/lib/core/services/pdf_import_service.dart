import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_render_plus/pdf_render.dart';

import 'pdf_text_extractor.dart';
import 'pdf_text_reader.dart';
import 'pdf_to_images_service.dart';

class PdfImportProgress {
  const PdfImportProgress({required this.page, required this.total, this.eta});
  final int page;
  final int total;
  final Duration? eta;
}

class PdfImportResult {
  const PdfImportResult({required this.pagePaths, required this.text, required this.pagesNeedingOcr, required this.cancelled});

  /// One picture per page, in order.
  final List<String> pagePaths;

  /// Text read from the PDF itself, available immediately (empty for pure scans).
  final String text;

  /// Page numbers (1-based) that had no text and still need OCR.
  final List<int> pagesNeedingOcr;
  final bool cancelled;
}

/// Imports a PDF as page pictures. Pages are rendered one at a time, so memory
/// stays flat, and the text the PDF already contains is read in the same pass,
/// so a text PDF is searchable the moment it opens and never needs OCR.
class PdfImportService {
  PdfImportService({PdfToImagesService? renderer}) : _renderer = renderer ?? PdfToImagesService();
  final PdfToImagesService _renderer;

  Future<PdfImportResult> importPages(
    String pdfPath, {
    String? outDir,
    void Function(PdfImportProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final String dirPath = outDir ?? p.join((await getApplicationDocumentsDirectory()).path, 'pdf_import_pages');
    await Directory(dirPath).create(recursive: true);
    final doc = await PdfDocument.openFile(pdfPath);
    final PdfTextReader? reader = await PdfTextReader.open(pdfPath);
    final List<String> paths = <String>[];
    final List<int> needOcr = <int>[];
    final StringBuffer text = StringBuffer();
    final String stamp = '${DateTime.now().microsecondsSinceEpoch}';
    final Stopwatch watch = Stopwatch()..start();
    bool cancelled = false;
    try {
      final int total = doc.pageCount;
      for (int n = 1; n <= total; n++) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        onProgress?.call(PdfImportProgress(
          page: n,
          total: total,
          eta: PdfTextExtractor.estimateRemaining(spent: watch.elapsed, worked: n - 1, remaining: total - n + 1),
        ));
        final page = await doc.getPage(n);
        final String? pageText = await reader?.pageText(n);
        if (pageText != null && PdfTextExtractor.hasEnoughText(pageText)) {
          if (text.isNotEmpty) text.writeln();
          text.write(pageText);
        } else {
          needOcr.add(n);
        }
        paths.add(await _renderer.renderPageToFile(page, p.join(dirPath, 'pdf_${stamp}_${n.toString().padLeft(4, '0')}.png')));
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      doc.dispose();
      await reader?.dispose();
    }
    if (cancelled) {
      // A cancelled import leaves nothing behind.
      for (final String f in paths) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
      return const PdfImportResult(pagePaths: <String>[], text: '', pagesNeedingOcr: <int>[], cancelled: true);
    }
    return PdfImportResult(pagePaths: paths, text: text.toString(), pagesNeedingOcr: needOcr, cancelled: false);
  }
}
