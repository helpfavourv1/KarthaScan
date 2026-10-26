import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_render_plus/pdf_render.dart';

import 'debug_log_service.dart';

enum PageImageFormat { png, jpg }

/// Renders a PDF to one picture per page, one page at a time: each page is
/// rendered, encoded straight to its final format, written, and released before
/// the next one starts, so memory stays flat whatever the page count.
class PdfToImagesService {
  final DebugLogService _log = DebugLogService();

  /// Longest side, in pixels, a rendered page may have. A poster-size PDF page
  /// would otherwise need hundreds of megabytes.
  static const int maxSide = 3000;

  /// Pixel size for a page of [width] x [height] points: [scale] times the size,
  /// shrunk (keeping the aspect ratio) so the longest side never exceeds [maxSide].
  static (int, int) targetSize(double width, double height, {double scale = 2, int maxSide = PdfToImagesService.maxSide}) {
    double w = width * scale;
    double h = height * scale;
    final double longest = w > h ? w : h;
    if (longest > maxSide) {
      final double k = maxSide / longest;
      w *= k;
      h *= k;
    }
    return (w.round().clamp(1, maxSide), h.round().clamp(1, maxSide));
  }

  Future<List<String>> convertToImages(
    String pdfPath, {
    void Function(double, String)? onProgress,
    String? outDir,
    PageImageFormat format = PageImageFormat.png,
    int jpgQuality = 90,
    double scale = 2,
    bool Function()? isCancelled,
  }) async {
    _log.log('PDF_TO_IMAGES', 'Starting: $pdfPath');
    final doc = await PdfDocument.openFile(pdfPath);
    final String dirPath = outDir ?? p.join((await getApplicationDocumentsDirectory()).path, 'converted_images');
    final Directory outputDir = Directory(dirPath);
    await outputDir.create(recursive: true);
    final String ext = format == PageImageFormat.png ? 'png' : 'jpg';
    final String stamp = '${DateTime.now().microsecondsSinceEpoch}';

    final List<String> paths = [];
    try {
      for (int i = 1; i <= doc.pageCount; i++) {
        if (isCancelled?.call() ?? false) break;
        onProgress?.call((i - 1) / doc.pageCount, 'Rendering page $i of ${doc.pageCount}…');
        final page = await doc.getPage(i);
        paths.add(await renderPageToFile(
          page,
          p.join(outputDir.path, 'pdf_${stamp}_${i.toString().padLeft(4, '0')}.$ext'),
          format: format,
          jpgQuality: jpgQuality,
          scale: scale,
        ));
        // Let the engine reclaim the page before the next render starts.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      doc.dispose();
    }
    onProgress?.call(1.0, 'Done');
    _log.log('PDF_TO_IMAGES', 'Done: ${paths.length} pages');
    return paths;
  }

  /// Renders one page to [outPath] and releases the page's pixels again.
  Future<String> renderPageToFile(
    PdfPage page,
    String outPath, {
    PageImageFormat format = PageImageFormat.png,
    int jpgQuality = 90,
    double scale = 2,
  }) async {
    final (int w, int h) = targetSize(page.width, page.height, scale: scale);
    final rendered = await page.render(width: w, height: h);
    try {
      final Uint8List bytes = format == PageImageFormat.png
          ? await _encodePng(rendered.pixels, rendered.width, rendered.height)
          : _encodeJpg(rendered.pixels, rendered.width, rendered.height, jpgQuality);
      await File(outPath).writeAsBytes(bytes, flush: false);
    } finally {
      rendered.dispose();
    }
    return outPath;
  }

  Uint8List _encodeJpg(Uint8List rgba, int w, int h, int quality) {
    final img.Image im = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4);
    return Uint8List.fromList(img.encodeJpg(im, quality: quality));
  }

  /// PNG encoding in the engine's native codec: much faster than Dart code and
  /// without the large temporary buffers.
  Future<Uint8List> _encodePng(Uint8List rgba, int w, int h) async {
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final ui.ImageDescriptor desc = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
      final ui.Codec codec = await desc.instantiateCodec();
      try {
        final ui.FrameInfo frame = await codec.getNextFrame();
        final ByteData? data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        if (data != null) return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        codec.dispose();
        desc.dispose();
        buffer.dispose();
      }
    } catch (_) {}
    final img.Image im = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4);
    return Uint8List.fromList(img.encodePng(im));
  }
}
