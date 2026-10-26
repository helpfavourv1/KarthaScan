import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdf_render_plus/pdf_render.dart';

import 'conversion_workspace.dart';
import 'ocr_service.dart';
import 'pdf_to_images_service.dart';

class PdfTextProgress {
  const PdfTextProgress({required this.page, required this.total, required this.done, this.eta});

  /// The page being worked on, counted within the chosen range (1-based).
  final int page;
  final int total;
  final int done;
  final Duration? eta;
}

class PdfTextResult {
  const PdfTextResult({required this.pages, required this.embedded, required this.ocr, required this.resumed, required this.cancelled});

  /// Text of each page in the chosen range, in order.
  final List<String> pages;

  /// Pages whose text was read from the PDF itself (exact, no OCR).
  final int embedded;

  /// Pages that had to be read by OCR (scans and pictures).
  final int ocr;

  /// Pages taken from a checkpoint of an earlier, interrupted run.
  final int resumed;
  final bool cancelled;

  String get text => pages.join('\n');
}

/// Text of a PDF, the cheapest correct way: real text is read from the file
/// instantly and exactly; only pages without text (scans) go through OCR. Every
/// finished page is checkpointed to disk, so a cancelled or killed job resumes
/// where it stopped.
class PdfTextExtractor {
  PdfTextExtractor({OcrService? ocr, PdfToImagesService? renderer})
      : _ocr = ocr ?? OcrService(),
        _renderer = renderer ?? PdfToImagesService();

  final OcrService _ocr;
  final PdfToImagesService _renderer;

  /// A page with fewer visible characters than this is treated as a picture.
  static const int minEmbeddedChars = 20;

  /// Folder name of the checkpoints for one PDF. The same file gives the same key.
  static String checkpointKey(String pdfPath, int length, DateTime modified) =>
      'ocr_${p.basename(pdfPath).replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_${length}_${modified.millisecondsSinceEpoch}';

  /// Clamps a requested range to the document: 1 <= first <= last <= [count].
  static (int, int) normalizeRange(int count, int? first, int? last) {
    final int f = (first ?? 1).clamp(1, count < 1 ? 1 : count);
    final int l = (last ?? count).clamp(f, count < 1 ? 1 : count);
    return (f, l);
  }

  static bool hasEnoughText(String? text) => text != null && text.replaceAll(RegExp(r'\s+'), '').length >= minEmbeddedChars;

  /// Estimated time left, from the average time per page so far.
  static Duration? estimateRemaining({required Duration spent, required int worked, required int remaining}) {
    if (worked <= 0 || remaining <= 0) return null;
    return Duration(milliseconds: (spent.inMilliseconds / worked * remaining).round());
  }

  Future<PdfTextResult> extract(
    String pdfPath, {
    required ConversionWorkspace workspace,
    required ConversionJob job,
    int? firstPage,
    int? lastPage,
    void Function(PdfTextProgress)? onProgress,
    bool Function()? isCancelled,
    bool keepCheckpointsOnCancel = true,
  }) async {
    final File file = File(pdfPath);
    final Directory checkpoints = Directory(p.join(workspace.workDir.path, checkpointKey(pdfPath, await file.length(), await file.lastModified())));
    await checkpoints.create(recursive: true);

    final doc = await PdfDocument.openFile(pdfPath);
    final List<String> pages = <String>[];
    int embedded = 0, ocr = 0, resumed = 0;
    bool cancelled = false;
    final Stopwatch watch = Stopwatch()..start();
    int worked = 0;
    try {
      final (int first, int last) = normalizeRange(doc.pageCount, firstPage, lastPage);
      final int total = last - first + 1;
      for (int n = first; n <= last; n++) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        final int index = n - first;
        onProgress?.call(PdfTextProgress(
          page: index + 1,
          total: total,
          done: index,
          eta: estimateRemaining(spent: watch.elapsed, worked: worked, remaining: total - index),
        ));
        final File cp = File(p.join(checkpoints.path, 'p_${n.toString().padLeft(5, '0')}.txt'));
        if (await cp.exists()) {
          pages.add(await cp.readAsString());
          resumed++;
          continue;
        }
        final page = await doc.getPage(n);
        String? text;
        try {
          text = (await page.loadText()).fullText;
        } catch (_) {}
        if (hasEnoughText(text)) {
          embedded++;
        } else {
          final String png = p.join(job.dir.path, 'page_$n.png');
          try {
            await _renderer.renderPageToFile(page, png);
            text = (await _ocr.recognizeTextAuto(imagePath: png)).fullText;
            ocr++;
          } finally {
            try {
              await File(png).delete();
            } catch (_) {}
          }
        }
        await cp.writeAsString(text);
        pages.add(text);
        worked++;
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      doc.dispose();
      await _ocr.dispose();
    }
    // A finished job leaves nothing behind; a cancelled one keeps its pages for resuming.
    if (!cancelled || !keepCheckpointsOnCancel) {
      try {
        await checkpoints.delete(recursive: true);
      } catch (_) {}
    }
    return PdfTextResult(pages: pages, embedded: embedded, ocr: ocr, resumed: resumed, cancelled: cancelled);
  }
}
