import '../utils/perspective.dart';
import '../utils/smooth_resize.dart';
import '../utils/csv_utils.dart';
import '../utils/seal_draw.dart';
import '../utils/watermark_draw.dart';
import 'debug_log_service.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/export_job.dart';
import '../models/scan_document.dart';
import '../models/ocr_block.dart';
import '../models/page_transform.dart';
import '../models/signature_placement.dart';
import 'filter_service.dart' show FilterService;
import 'pdf_fonts.dart';
import '../../l10n/app_localizations.dart';

/// The document has no recognized text, so a text export would be empty.
class ExportNoTextException extends ExportFailedException {
  const ExportNoTextException() : super('This document has no text to export.');
}

class ExportFailedException implements Exception {
  const ExportFailedException(this.message, {this.cause});
  final String message;

  /// The underlying error, kept for diagnostics. Never shown to the person.
  final Object? cause;
  @override
  String toString() => cause == null ? 'ExportFailedException: $message' : 'ExportFailedException: $message (cause: $cause)';
}

/// How the two sides of an ID card are placed on the A4 page.
enum IdCardLayout {
  /// Each side at its real size (85.6 mm wide), centred, front above back.
  realSize,

  /// Both sides scaled to the full page width (for viewing on a screen).
  fullWidth,
}

enum FilterType { none, grayscale, blackAndWhite, colorEnhance, shadowRemoval }

// SignaturePlacement is now in models/signature_placement.dart

enum ExportDocxMode { textOnly, imageEmbedded }

enum ExportPageFormat { a4, letter }

PdfPageFormat _toPdfFormat(ExportPageFormat f) {
  switch (f) {
    case ExportPageFormat.a4: return PdfPageFormat.a4;
    case ExportPageFormat.letter: return PdfPageFormat.letter;
  }
}

/// Width and height of an encoded image without decoding all its pixels.
(int, int)? _probeImageSize(List<int> bytes) {
  try {
    final Uint8List data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final img.DecodeInfo? info = img.findDecoderForData(data)?.startDecode(data);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    return (info.width, info.height);
  } catch (_) {
    return null;
  }
}

/// Pages above this many pixels (about 24 MP) are decoded at reduced size so
/// a 48 MP or larger photo does not run the phone out of memory while it is
/// edited and exported. Layer positions are fractions of the page, so they
/// land in the same place.
const int _kMaxEditPixels = 24000000;
const int _kCappedLongSide = 6000;

Future<img.Image?> _decodeForEdit(Uint8List bytes) async {
  final (int, int)? size = _probeImageSize(bytes);
  if (size == null || size.$1 * size.$2 <= _kMaxEditPixels) return Isolate.run(() => img.decodeImage(bytes));
  final double k = _kCappedLongSide / (size.$1 > size.$2 ? size.$1 : size.$2);
  final ui.Codec codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: (size.$1 * k).round(),
    targetHeight: (size.$2 * k).round(),
  );
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? raw = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final int w = frame.image.width;
    final int h = frame.image.height;
    frame.image.dispose();
    if (raw == null) return null;
    return img.Image.fromBytes(width: w, height: h, bytes: raw.buffer, numChannels: 4);
  } finally {
    codec.dispose();
  }
}

/// Plain data for one PDF page (everything here can cross to another isolate).
class _PdfPageData {
  const _PdfPageData({
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.format,
    required this.blocks,
  });
  /// The page picture, staged on disk so 100 pages are never all in memory
  /// (or copied to the background isolate) at once.
  final String imagePath;
  final int? imageWidth;
  final int? imageHeight;
  final PdfPageFormat format;
  final List<(String, double, double, double, double)> blocks;
}

class _PdfJob {
  const _PdfJob({
    required this.title,
    required this.pages,
    required this.emptyMessage,
    required this.pageFormat,
    required this.fonts,
  });
  final String title;
  final List<_PdfPageData> pages;
  final String emptyMessage;
  final PdfPageFormat pageFormat;
  final PdfFontBytes fonts;
}

/// Builds the PDF file. Runs on a background isolate.
Future<Uint8List> _assemblePdf(_PdfJob job) async {
  pw.ThemeData theme;
  try {
    final pw.Font latin = pw.Font.ttf(ByteData.sublistView(job.fonts.latin));
    theme = pw.ThemeData.withFont(
      base: latin,
      bold: latin,
      italic: latin,
      boldItalic: latin,
      fontFallback: <pw.Font>[for (final Uint8List b in job.fonts.fallback) pw.Font.ttf(ByteData.sublistView(b))],
    );
  } catch (_) {
    theme = pw.ThemeData.base();
  }
  final pw.Document pdfDoc = pw.Document(title: job.title, creator: 'KatharScan');

  for (final _PdfPageData pg in job.pages) {
    final String imagePath = pg.imagePath;
    final PdfPageFormat pageFmt = pg.format;
    final blocks = pg.blocks;
    final int? w = pg.imageWidth;
    final int? h = pg.imageHeight;
    pdfDoc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: pageFmt,
        build: (pw.Context context) {
          final image = pw.MemoryImage(File(imagePath).readAsBytesSync());
          if (w == null || h == null || blocks.isEmpty) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          }
          final imgW = w.toDouble();
          final imgH = h.toDouble();
          final imgAspect = imgW / imgH;
          final pageW = pageFmt.width;
          final pageH = pageFmt.height;
          final pageAspect = pageW / pageH;

          final double renderW, renderH, renderX, renderY;
          if (imgAspect > pageAspect) {
            renderW = pageW;
            renderH = renderW / imgAspect;
            renderX = 0;
            renderY = (pageH - renderH) / 2;
          } else {
            renderH = pageH;
            renderW = renderH * imgAspect;
            renderX = (pageW - renderW) / 2;
            renderY = 0;
          }

          return pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
              ),
              ...blocks.map((block) {
                final x = renderX + (block.$2 / imgW) * renderW;
                final y = renderY + (block.$3 / imgH) * renderH;
                final bw = (block.$4 / imgW) * renderW;
                final bh = (block.$5 / imgH) * renderH;
                final fontSize = bh * 0.8;
                return pw.Positioned(
                  left: x,
                  top: y,
                  child: pw.SizedBox(
                    width: bw,
                    height: bh,
                    child: pw.Text(
                      block.$1,
                      style: pw.TextStyle(
                        fontSize: fontSize,
                        color: const PdfColor(0, 0, 0, 0),
                        renderingMode: PdfTextRenderingMode.invisible,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  if (job.pages.isEmpty) {
    pdfDoc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: job.pageFormat,
        build: (pw.Context context) => pw.Center(child: pw.Text(job.emptyMessage)),
      ),
    );
  }
  return pdfDoc.save();
}

class ExportService {
  /// One page exactly as it is exported (crop, filter, layers and all), for
  /// printing so the paper copy matches what the person sees and exports.
  Future<Uint8List> renderPageForOutput(
    ScanDocument document,
    int pageIndex, {
    FilterType filter = FilterType.none,
  }) {
    return _processPage(
      document.pagePaths[pageIndex],
      filter: filter,
      pageIndex: pageIndex,
      documentLayers: document.signatureLayers,
      documentInks: document.signatureInks,
      documentAnnotateLayers: document.annotateLayers,
      documentWatermarkLayers: document.watermarkLayers,
      documentStampLayers: document.stampLayers,
      pageTransform: document.pageTransforms[pageIndex],
    );
  }

  /// True when the page has any edit that changes what is exported.
  bool pageHasEdits(ScanDocument document, int pageIndex) {
    final PageTransform? t = document.pageTransforms[pageIndex];
    final bool transformed = t != null &&
        (t.filter != FilterType.none || t.rotationTurns != 0 || t.cropRect != null || t.resizeWidth != null || t.eraserStrokes.isNotEmpty);
    return transformed ||
        document.signatureLayers.any((l) => l.pageIndex == pageIndex) ||
        document.annotateLayers.any((l) => l.pageIndex == pageIndex) ||
        document.watermarkLayers.any((l) => l.pageIndex == pageIndex) ||
        document.stampLayers.any((l) => l.pageIndex == pageIndex);
  }

  /// Files to share or email: pages without edits are sent as they are, edited
  /// pages are rendered exactly as Export renders them (JPG, quality 92).
  Future<List<String>> renderPagesForShare(ScanDocument document) async {
    final Directory dir = Directory(p.join(
      (await getTemporaryDirectory()).path,
      'share_${DateTime.now().microsecondsSinceEpoch}',
    ));
    await dir.create(recursive: true);
    final List<String> out = <String>[];
    for (int i = 0; i < document.pagePaths.length; i++) {
      if (!pageHasEdits(document, i)) {
        out.add(document.pagePaths[i]);
        continue;
      }
      final Uint8List bytes = await renderPageForOutput(document, i);
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw ExportFailedException('Could not read page ${i + 1}.');
      }
      final String path = p.join(dir.path, 'page_${i + 1}.jpg');
      await File(path).writeAsBytes(img.encodeJpg(decoded, quality: 92), flush: true);
      out.add(path);
    }
    return out;
  }

  Future<List<String>> export({
    required ScanDocument document,
    required ExportFormat format,
    required String outputDirectoryPath,
    FilterType filter = FilterType.none,
    Uint8List? signatureBytes,
    Map<int, SignaturePlacement>? signaturePlacements,
    CompressionTier compression = CompressionTier.original,
    ExportDocxMode docxMode = ExportDocxMode.textOnly,
    ExportPageFormat pageFormat = ExportPageFormat.a4,
    int? targetBytes,
  }) async {
    try {
      switch (format) {
        case ExportFormat.pdf:
          return <String>[
            await _exportPdf(
              document,
              outputDirectoryPath,
              pageFormat: _toPdfFormat(pageFormat),
              filter: filter,
              signatureBytes: signatureBytes,
              signaturePlacements: signaturePlacements,
              compression: compression,
            ),
          ];
        case ExportFormat.txt:
          return <String>[await _exportTxt(document, outputDirectoryPath)];
        case ExportFormat.docx:
          return <String>[await _exportDocx(document, outputDirectoryPath, mode: docxMode, pageFormat: _toPdfFormat(pageFormat))];
        case ExportFormat.jpg:
          return await _exportImages(
            document,
            outputDirectoryPath,
            targetExtension: 'jpg',
            filter: filter,
            signatureBytes: signatureBytes,
            signaturePlacements: signaturePlacements,
            compression: compression,
            targetBytes: targetBytes,
        );
        case ExportFormat.png:
          return await _exportImages(
            document,
            outputDirectoryPath,
            targetExtension: 'png',
            filter: filter,
            signatureBytes: signatureBytes,
            signaturePlacements: signaturePlacements,
            compression: compression,
            targetBytes: targetBytes,
        );
        case ExportFormat.csv:
          return <String>[await _exportCsv(document, outputDirectoryPath)];
      }
    } on ExportFailedException {
      rethrow;
    } catch (error, stackTrace) {
      _logError('export(${format.name})', error, stackTrace);
      throw ExportFailedException(
        'Could not export "${document.title}" as ${format.name.toUpperCase()}.',
        cause: error,
      );
    }
  }

  img.Image _compositeSignature(
    img.Image page,
    img.Image signature,
    SignaturePlacement placement, {
    double widthFraction = 0.28,
    double? boxHeightFraction,
  }) {
    int targetWidth;
    int targetHeight;
    if (boxHeightFraction != null) {
      final boxW = page.width * widthFraction * placement.scale;
      final boxH = page.width * boxHeightFraction * placement.scale;
      final f = boxW / signature.width < boxH / signature.height ? boxW / signature.width : boxH / signature.height;
      targetWidth = (signature.width * f).round().clamp(1, page.width);
      targetHeight = (signature.height * f).round().clamp(1, page.height);
    } else {
      targetWidth = (page.width * widthFraction * placement.scale).round();
      targetHeight = (signature.height * targetWidth / signature.width).round();
    }
    var sig = resizeSmooth(signature, width: targetWidth, height: targetHeight);
    if (placement.rotationDegrees != 0) {
      sig = rotateSmooth(sig, placement.rotationDegrees);
    }
    final dstX = (placement.pctX * page.width).round() - (sig.width ~/ 2);
    final dstY = (placement.pctY * page.height).round() - (sig.height ~/ 2);
    return img.compositeImage(page, sig, dstX: dstX, dstY: dstY);
  }

  List<SignatureLayer> _findLayersForPage(int pageIndex, Map<int, SignaturePlacement>? exportPlacements, List<SignatureLayer>? docLayers) {
    final layers = <SignatureLayer>[];
    if (exportPlacements != null) {
      final fromExport = exportPlacements[pageIndex];
      if (fromExport != null) {
        layers.add(SignatureLayer(pageIndex: pageIndex, placement: fromExport, inkId: 'default'));
      }
    }
    if (docLayers != null) {
      for (final layer in docLayers) {
        if (layer.pageIndex == pageIndex) layers.add(layer);
      }
    }
    return layers;
  }

  Future<Uint8List> _processPage(
    String pagePath, {
    required FilterType filter,
    required int pageIndex,
    Uint8List? signatureBytes,
    Map<int, SignaturePlacement>? signaturePlacements,
    List<SignatureLayer>? documentLayers,
    List<SignatureInk>? documentInks,
    List<AnnotateLayer>? documentAnnotateLayers,
    List<WatermarkLayer>? documentWatermarkLayers,
    List<StampLayer>? documentStampLayers,
    PageTransform? pageTransform,
  }) async {
    final original = await _readBytes(pagePath);
    final layers = _findLayersForPage(pageIndex, signaturePlacements, documentLayers);
    final annotateLayers = documentAnnotateLayers?.where((l) => l.pageIndex == pageIndex).toList() ?? const <AnnotateLayer>[];
    final watermarkLayers = documentWatermarkLayers?.where((l) => l.pageIndex == pageIndex).toList() ?? const <WatermarkLayer>[];
    final stampLayers = documentStampLayers?.where((l) => l.pageIndex == pageIndex).toList() ?? const <StampLayer>[];
    final inkMap = <String, SignatureInk>{
      if (documentInks != null) for (final ink in documentInks) ink.id: ink,
    };
    final hasTransform = pageTransform != null && (pageTransform.filter != FilterType.none || pageTransform.rotationTurns != 0 || pageTransform.cropRect != null || pageTransform.resizeWidth != null || pageTransform.eraserStrokes.isNotEmpty);
    if (filter == FilterType.none && !hasTransform && layers.isEmpty && annotateLayers.isEmpty && watermarkLayers.isEmpty && stampLayers.isEmpty) {
      return original;
    }
    try {
      final decodedOriginal = await _decodeForEdit(original);
      if (decodedOriginal == null) {
        throw ExportFailedException('Could not read page ${pageIndex + 1}.');
      }
      img.Image decoded = decodedOriginal;
      // A filter chosen on the export screen replaces the page's own filter;
      // "Original" there keeps whatever the editor set for the page.
      final bool useExportFilter = filter != FilterType.none;
      final effectiveFilter = useExportFilter
          ? filter
          : (pageTransform != null ? pageTransform.filter : FilterType.none);
      // Erasing is drawn on the full original (the eraser sheet shows the
      // uncropped page), then crop/resize/filter follow, same as the preview.
      if (pageTransform != null && pageTransform.eraserStrokes.isNotEmpty) {
        for (final s in pageTransform.eraserStrokes) {
          final pts = (s['points'] as List<dynamic>)
              .map((e) => (e as List<dynamic>).map((v) => (v as num).toDouble()).toList())
              .toList();
          final colorInt = s['color'] as int;
          final color = img.ColorRgba8((colorInt >> 16) & 0xFF, (colorInt >> 8) & 0xFF, colorInt & 0xFF, (colorInt >> 24) & 0xFF);
          final wf = (s['width'] as num).toDouble();
          final thickness = (wf * decoded.width).clamp(1.0, decoded.width / 2).round();
          final isRect = s['rect'] as bool? ?? false;
          if (isRect && pts.length >= 2) {
            final x1 = (pts[0][0] * decoded.width).round();
            final y1 = (pts[0][1] * decoded.height).round();
            final x2 = (pts[1][0] * decoded.width).round();
            final y2 = (pts[1][1] * decoded.height).round();
            img.fillRect(decoded, x1: x1, y1: y1, x2: x2, y2: y2, color: color);
          } else {
            for (int i = 0; i < pts.length - 1; i++) {
              final x1 = (pts[i][0] * decoded.width).round();
              final y1 = (pts[i][1] * decoded.height).round();
              final x2 = (pts[i + 1][0] * decoded.width).round();
              final y2 = (pts[i + 1][1] * decoded.height).round();
              img.drawLine(decoded, x1: x1, y1: y1, x2: x2, y2: y2, color: color, thickness: thickness, antialias: true);
            }
          }
        }
      }
      if (pageTransform != null && pageTransform.cropQuad != null) {
        // A page photographed at an angle: straighten the marked four corners.
        final img.Image forWarp = decoded;
        final List<ui.Offset> quad = pageTransform.cropQuad!;
        final double? aspect = pageTransform.cropAspect;
        final img.Image? straight = await Isolate.run(() => warpQuad(forWarp, quad, aspect: aspect));
        if (straight == null) throw ExportFailedException('Could not straighten page ${pageIndex + 1}.');
        decoded = straight;
      } else if (pageTransform != null && pageTransform.cropRect != null && pageTransform.cropRect!.width > 0 && pageTransform.cropRect!.height > 0) {
        final r = pageTransform.cropRect!;
        decoded = img.copyCrop(decoded, x: r.left.round(), y: r.top.round(), width: r.width.round(), height: r.height.round());
      }
      if (pageTransform != null && (pageTransform.resizeWidth ?? 0) > 0 && (pageTransform.resizeHeight ?? 0) > 0) {
        decoded = resizeSmooth(decoded, width: pageTransform.resizeWidth!, height: pageTransform.resizeHeight!);
      }
      if (pageTransform != null && pageTransform.straightenDegrees != 0) {
        final img.Image forTilt = decoded;
        final double tilt = pageTransform.straightenDegrees;
        decoded = await Isolate.run(() => straightenFill(forTilt, tilt));
      }
      if (effectiveFilter != FilterType.none) {
        final img.Image forFilter = decoded;
        final double intensity = (!useExportFilter && pageTransform != null) ? pageTransform.filterIntensity : 1.0;
        // Heavy pixel work runs on a background isolate so the screen keeps moving.
        decoded = await Isolate.run(() => FilterService.applyToImage(forFilter, effectiveFilter, intensity: intensity));
      }
      for (final layer in layers) {
        final ink = inkMap[layer.inkId];
        final bytes = ink?.bytes ?? signatureBytes;
        if (bytes != null) {
          final sigImage = img.decodePng(bytes);
          if (sigImage != null) {
            decoded = _compositeSignature(decoded, sigImage, layer.placement, widthFraction: 0.28);
          }
        }
      }
      for (final annotate in annotateLayers) {
        final annotateBytes = await _readBytes(annotate.bytesPath);
        final annotateImage = img.decodePng(annotateBytes);
        if (annotateImage != null) {
          decoded = _compositeSignature(decoded, annotateImage, annotate.placement, widthFraction: 0.28);
        }
      }
      for (final wm in watermarkLayers) {
        if (wm.isTiled) {
          decoded = await _compositeWatermarkTiles(decoded, wm);
          continue;
        }
        if (wm.isImage) {
          final logo = await _readWatermarkLogo(wm);
          decoded = _compositeSignature(decoded, logo, wm.placement, widthFraction: 0.30, boxHeightFraction: 0.30);
          continue;
        }
        final wmBytes = await _renderWatermarkText(wm, decoded.width);
        if (wmBytes != null) {
          final wmImage = img.decodePng(wmBytes);
          if (wmImage != null) {
            decoded = _compositeSignature(decoded, wmImage, wm.placement, widthFraction: 0.30, boxHeightFraction: 0.10);
          }
        }
      }
      for (final st in stampLayers) {
        final stBytes = st.kind == 'checkbox'
            ? await _renderCheckbox(st)
            : (st.kind == 'seal'
                ? await _renderSeal(st, (decoded.width * 0.25 * st.placement.scale * 1.5).round())
                : (st.isFlowFill ? await _renderFillText(st, decoded.width) : await _renderStampText(st, decoded.width)));
        if (stBytes != null) {
          final stImage = img.decodePng(stBytes);
          if (stImage != null) {
            if (st.isFlowFill) {
              // Fill text keeps its real size: the picture is already the exact size
              // it has on the page, so it is placed without being fitted into a box.
              decoded = _compositeSignature(decoded, stImage, st.placement, widthFraction: stImage.width / decoded.width);
            } else {
              final frac = st.kind == 'checkbox' ? 0.15 : (st.kind == 'seal' ? 0.25 : 0.30);
              final boxH = (st.kind == 'checkbox' || st.kind == 'seal') ? null : 0.10;
              decoded = _compositeSignature(decoded, stImage, st.placement, widthFraction: frac, boxHeightFraction: boxH);
            }
          }
        }
      }
      // Rotate last. Erasing and every layer position are stored in the
      // unrotated page frame (the preview rotates the whole stack together),
      // so they must be applied before the page is turned.
      if (pageTransform != null && pageTransform.rotationTurns != 0) {
        final img.Image forRotate = decoded;
        final int turns = pageTransform.rotationTurns;
        decoded = await Isolate.run(() => img.copyRotate(forRotate, angle: turns * 90));
      }
      final img.Image forEncode = decoded;
      return await Isolate.run(() => Uint8List.fromList(img.encodePng(forEncode)));
    } catch (error, stackTrace) {
      _logError('_processPage', error, stackTrace);
      // Never hand back the unedited original: erased or redacted content
      // would silently reappear in the exported or shared file.
      if (error is ExportFailedException) rethrow;
      throw ExportFailedException('Could not render page ${pageIndex + 1} with its edits.');
    }
  }

  /// Re-encodes a page as a smaller JPG for PDF output: capped longest side
  /// and the tier's quality. Falls back to the original bytes if it fails.
  Future<Uint8List> _compressForPdf(Uint8List bytes, CompressionTier tier) async {
    try {
      return await Isolate.run(() => _compressForPdfSync(bytes, tier));
    } catch (_) {
      return bytes;
    }
  }

  Uint8List _compressForPdfSync(Uint8List bytes, CompressionTier tier) {
    try {
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      if (decoded.hasAlpha) {
        final img.Image white = img.Image(width: decoded.width, height: decoded.height, numChannels: 3);
        img.fill(white, color: img.ColorRgb8(255, 255, 255));
        decoded = img.compositeImage(white, decoded);
      }
      if (tier == CompressionTier.original) {
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
      }
      final int cap = tier == CompressionTier.small ? 1400 : 2000;
      final int longest = decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longest > cap) {
        decoded = decoded.width >= decoded.height
            ? resizeSmooth(decoded, width: cap)
            : resizeSmooth(decoded, height: cap);
      }
      return Uint8List.fromList(img.encodeJpg(decoded, quality: _qualityFor(tier)));
    } catch (_) {
      return bytes;
    }
  }

  Future<String> _exportPdf(
    ScanDocument document,
    String outDir, {
    required FilterType filter,
    Uint8List? signatureBytes,
    Map<int, SignaturePlacement>? signaturePlacements,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    CompressionTier compression = CompressionTier.original,
  }) async {
    final List<_PdfPageData> pages = <_PdfPageData>[];
    final Directory stage = await Directory(p.join(outDir, '.pdf_stage_${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);
    try {
    for (int i = 0; i < document.pagePaths.length; i++) {
      // Let the screen draw a frame between pages so the app stays responsive.
      await Future<void>.delayed(Duration.zero);
      final bytes = await _processPage(
        document.pagePaths[i],
        filter: filter,
        pageIndex: i,
        signatureBytes: signatureBytes,
        signaturePlacements: signaturePlacements,
        documentLayers: document.signatureLayers,
        documentInks: document.signatureInks,
        documentAnnotateLayers: document.annotateLayers,
        documentWatermarkLayers: document.watermarkLayers,
        documentStampLayers: document.stampLayers,
        pageTransform: document.pageTransforms[i],
      );
      // Size of the page picture before any compression; the invisible OCR
      // text is positioned against this.
      final (int, int)? probed = _probeImageSize(bytes);
      // Every page goes in as a JPEG: the PDF library passes JPEG through, but
      // unpacks a PNG into raw pixels, which for many large pages runs a phone
      // out of memory. At the original tier the size is untouched and quality is 95.
      final Uint8List embedBytes = await _compressForPdf(bytes, compression);
      final String stagedPath = p.join(stage.path, 'p$i.jpg');
      await File(stagedPath).writeAsBytes(embedBytes);
      final blocks = document.pageOcrBlocks[i] ?? const <OcrBlock>[];
      // A wide scan gets a landscape page instead of a tiny letterboxed one.
      final PdfPageFormat pageFmt =
          (probed != null && probed.$1 > probed.$2) ? pageFormat.landscape : pageFormat;
      pages.add(_PdfPageData(
        imagePath: stagedPath,
        imageWidth: probed?.$1,
        imageHeight: probed?.$2,
        format: pageFmt,
        blocks: <(String, double, double, double, double)>[
          for (final OcrBlock b in blocks)
            (b.text, b.boundingBox.left, b.boundingBox.top, b.boundingBox.width, b.boundingBox.height),
        ],
      ));
    }

    String emptyMsg = '';
    if (document.pagePaths.isEmpty) {
      final deviceLocale = ui.PlatformDispatcher.instance.locale;
      final matchLocale = AppLocalizations.supportedLocales.firstWhere(
        (l) => l.languageCode == deviceLocale.languageCode,
        orElse: () => AppLocalizations.supportedLocales.first,
      );
      emptyMsg = lookupAppLocalizations(matchLocale).emptyDocumentMessage;
    }

    // The fonts the text needs, as bytes, so a background isolate can build the file.
    final String allText = <String>[
      emptyMsg,
      for (final _PdfPageData pg in pages) ...pg.blocks.map(((String, double, double, double, double) b) => b.$1),
    ].join(' ');
    final PdfFontBytes fonts = await PdfFonts.bytesFor(allText);

    // Laying out and compressing the pages is the heaviest step; it runs off the
    // screen thread so the app keeps responding during a long export.
    final _PdfJob job = _PdfJob(
      title: document.title,
      pages: pages,
      emptyMessage: emptyMsg,
      pageFormat: pageFormat,
      fonts: fonts,
    );
    final Uint8List pdfBytes = await Isolate.run(() => _assemblePdf(job));
    final outPath = _outputPath(document, outDir, 'pdf');
    await _writeBytes(outPath, pdfBytes);
    return outPath;
    } finally {
      try {
        await stage.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<String> _exportTxt(ScanDocument document, String outDir) async {
    if (document.ocrText.trim().isEmpty) throw const ExportNoTextException();
    final outPath = _outputPath(document, outDir, 'txt');
    try {
      await File(outPath).writeAsString(document.ocrText);
      return outPath;
    } catch (error, stackTrace) {
      _logError('_exportTxt', error, stackTrace);
      throw const ExportFailedException('Could not write the text file.');
    }
  }

  Future<String> buildDocxFromText(String text, String outDir, String baseName) {
    final now = DateTime.now();
    final doc = ScanDocument(
      id: '${now.microsecondsSinceEpoch}',
      title: baseName,
      pageCount: 0,
      pagePaths: const <String>[],
      createdAt: now,
      updatedAt: now,
      ocrText: text,
      thumbnailPath: '',
    );
    // Keep this helper on Letter, the size it always used.
    return _exportDocx(doc, outDir, mode: ExportDocxMode.textOnly, pageFormat: PdfPageFormat.letter);
  }

  Future<String> buildDocxFromImages(List<String> imagePaths, String outDir, String baseName) {
    final now = DateTime.now();
    final doc = ScanDocument(
      id: '${now.microsecondsSinceEpoch}',
      title: baseName,
      pageCount: imagePaths.length,
      pagePaths: imagePaths,
      createdAt: now,
      updatedAt: now,
      ocrText: '',
      thumbnailPath: imagePaths.isEmpty ? '' : imagePaths.first,
    );
    return _exportDocx(doc, outDir, mode: ExportDocxMode.imageEmbedded);
  }

  Future<String> _exportDocx(ScanDocument document, String outDir, {
    ExportDocxMode mode = ExportDocxMode.textOnly,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    if (mode == ExportDocxMode.textOnly && document.ocrText.trim().isEmpty) {
      throw const ExportNoTextException();
    }
    final archive = Archive();

    void addFile(String path, List<int> bytes) {
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    final List<List<int>> pageJpgs = <List<int>>[];
    if (mode == ExportDocxMode.imageEmbedded) {
      for (int pageIdx = 0; pageIdx < document.pagePaths.length; pageIdx++) {
        try {
          final bytes = await renderPageForOutput(document, pageIdx);
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            pageJpgs.add(img.encodeJpg(decoded, quality: 92));
          }
        } catch (_) {
          throw const ExportFailedException('Could not build the DOCX file.');
        }
      }
    }

    // Content types: add jpeg for image mode
    final contentTypesBuf = StringBuffer();
    contentTypesBuf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    contentTypesBuf.writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
    contentTypesBuf.writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
    contentTypesBuf.writeln('  <Default Extension="xml" ContentType="application/xml"/>');
    if (mode == ExportDocxMode.imageEmbedded) {
      contentTypesBuf.writeln('  <Default Extension="jpeg" ContentType="image/jpeg"/>');
    }
    contentTypesBuf.writeln('  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>');
    contentTypesBuf.writeln('  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>');
    contentTypesBuf.writeln('  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>');
    contentTypesBuf.writeln('</Types>');
    addFile('[Content_Types].xml', utf8.encode(contentTypesBuf.toString()));

    addFile('_rels/.rels', utf8.encode(_docxRelsXml));
    addFile('word/document.xml', utf8.encode(
      mode == ExportDocxMode.imageEmbedded
        ? _docxDocumentXmlWithImages(document, pageJpgs, pageFormat)
        : _docxDocumentXml(document.ocrText, pageFormat),
    ));
    addFile('docProps/core.xml', utf8.encode(_docxCoreXml(document)));
    addFile('docProps/app.xml', utf8.encode(_docxAppXml));

    if (mode == ExportDocxMode.imageEmbedded) {
      addFile('word/_rels/document.xml.rels', utf8.encode(_docxDocumentRelsXml(pageJpgs.length)));
      for (int i = 0; i < pageJpgs.length; i++) {
        addFile('word/media/image${i + 1}.jpeg', pageJpgs[i]);
      }
    }

    final List<int> encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw const ExportFailedException('Could not build the DOCX file.');
    }

    final outPath = _outputPath(document, outDir, 'docx');
    await _writeBytes(outPath, Uint8List.fromList(encoded));
    return outPath;
  }



  static const String _docxRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

  static const String _docxAppXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  <Application>KatharScan</Application>
</Properties>''';

  String _docxDocumentRelsXml(int imageCount) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (int i = 0; i < imageCount; i++) {
      buf.writeln('  <Relationship Id="rImg${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image${i + 1}.jpeg"/>');
    }
    buf.writeln('</Relationships>');
    return buf.toString();
  }

  String _docxDocumentXmlWithImages(ScanDocument document, List<List<int>> pageJpgs, PdfPageFormat pageFormat) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<w:document xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">');
    buf.writeln('<w:body>');
    for (int i = 0; i < pageJpgs.length; i++) {
      // Fit the page image inside the text area (page minus 1" margins)
      // keeping its own proportions.
      final double areaW = (pageFormat.width - 144) * 12700;
      final double areaH = (pageFormat.height - 144) * 12700;
      final (int, int)? size = _probeImageSize(pageJpgs[i]);
      final double aspect = size == null ? 0.75 : size.$1 / size.$2;
      int widthEmu = areaW.round();
      int heightEmu = (areaW / aspect).round();
      if (heightEmu > areaH) {
        heightEmu = areaH.round();
        widthEmu = (areaH * aspect).round();
      }
      buf.writeln('  <w:p>');
      buf.writeln('    <w:r>');
      buf.writeln('      <w:drawing>');
      buf.writeln('        <wp:inline distT="0" distB="0" distL="0" distR="0">');
      buf.writeln('          <wp:extent cx="$widthEmu" cy="$heightEmu"/>');
      buf.writeln('          <wp:docPr id="${i + 1}" name="Page${i + 1}"/>');
      buf.writeln('          <a:graphic>');
      buf.writeln('            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">');
      buf.writeln('              <pic:pic>');
      buf.writeln('                <pic:nvPicPr>');
      buf.writeln('                  <pic:cNvPr id="${i + 1}" name="Page${i + 1}"/>');
      buf.writeln('                  <pic:cNvPicPr/>');
      buf.writeln('                </pic:nvPicPr>');
      buf.writeln('                <pic:blipFill>');
      buf.writeln('                  <a:blip r:embed="rImg${i + 1}"/>');
      buf.writeln('                  <a:stretch><a:fillRect/></a:stretch>');
      buf.writeln('                </pic:blipFill>');
      buf.writeln('                <pic:spPr>');
      buf.writeln('                  <a:xfrm><a:off x="0" y="0"/><a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm>');
      buf.writeln('                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>');
      buf.writeln('                </pic:spPr>');
      buf.writeln('              </pic:pic>');
      buf.writeln('            </a:graphicData>');
      buf.writeln('          </a:graphic>');
      buf.writeln('        </wp:inline>');
      buf.writeln('      </w:drawing>');
      buf.writeln('    </w:r>');
      buf.writeln('  </w:p>');
    }
    final int w = (pageFormat.width * 20).round();
    final int h = (pageFormat.height * 20).round();
    buf.writeln('  <w:sectPr>');
    buf.writeln('    <w:pgSz w:w="$w" w:h="$h"/>');
    buf.writeln('    <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/>');
    buf.writeln('  </w:sectPr>');
    buf.writeln('</w:body>');
    buf.writeln('</w:document>');
    return buf.toString();
  }

  String _docxCoreXml(ScanDocument document) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>${_xmlEscape(document.title)}</dc:title>
  <dc:creator>KatharScan</dc:creator>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';
  }

  String _docxDocumentXml(String text, PdfPageFormat pageFormat) {
    // Word page size is in twentieths of a point.
    final int pageW = (pageFormat.width * 20).round();
    final int pageH = (pageFormat.height * 20).round();
    final lines = text.isEmpty ? [''] : text.split('\n');
    final paragraphs = StringBuffer();
    for (final line in lines) {
      if (line.isEmpty) {
        paragraphs.writeln('<w:p/>');
      } else {
        // Arabic/Hebrew lines are laid out right-to-left in Word.
        final bool rtl = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]').hasMatch(line);
        paragraphs.writeln(
          '<w:p>${rtl ? '<w:pPr><w:bidi/></w:pPr>' : ''}<w:r>${rtl ? '<w:rPr><w:rtl/></w:rPr>' : ''}<w:t xml:space="preserve">${_xmlEscape(line)}</w:t></w:r></w:p>',
        );
      }
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $paragraphs
    <w:sectPr>
      <w:pgSz w:w="$pageW" w:h="$pageH"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';
  }

  String _xmlEscape(String input) {
    // XML 1.0 forbids most control characters; OCR output can contain them
    // and Word then reports the whole file as corrupt.
    return input
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]'), '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  Future<List<String>> _exportImages(
    ScanDocument document,
    String outDir, {
    required String targetExtension,
    required FilterType filter,
    Uint8List? signatureBytes,
    Map<int, SignaturePlacement>? signaturePlacements,
    CompressionTier compression = CompressionTier.original,
    int? targetBytes,
  }) async {
    final outputPaths = <String>[];
    final isMultiPage = document.pagePaths.length > 1;
    for (int i = 0; i < document.pagePaths.length; i++) {
      await Future<void>.delayed(Duration.zero);
      final processedBytes = await _processPage(
        document.pagePaths[i],
        filter: filter,
        pageIndex: i,
        signatureBytes: signatureBytes,
        signaturePlacements: signaturePlacements,
        documentLayers: document.signatureLayers,
        documentInks: document.signatureInks,
        documentAnnotateLayers: document.annotateLayers,
        documentWatermarkLayers: document.watermarkLayers,
        documentStampLayers: document.stampLayers,
        pageTransform: document.pageTransforms[i],
      );
      final decoded = img.decodeImage(processedBytes);
      if (decoded == null) {
        throw ExportFailedException(
          'Could not read page ${i + 1} of "${document.title}".',
        );
      }
      final int quality = targetBytes != null ? _findQualityForTarget(decoded, targetBytes) : _qualityFor(compression);
        final reencoded = targetExtension == 'png'
            ? img.encodePng(decoded)
            : img.encodeJpg(decoded, quality: quality);
      final suffix = isMultiPage ? '_page${i + 1}' : '';
      final outPath = _outputPath(
        document,
        outDir,
        targetExtension,
        suffix: suffix,
      );
      await _writeBytes(outPath, Uint8List.fromList(reencoded));
      outputPaths.add(outPath);
    }
    if (outputPaths.isEmpty) {
      throw const ExportFailedException('This document has no pages to export.');
    }
    return outputPaths;
  }

  /// Real file size of each compression level for a PDF or JPG export: the first
  /// page is rendered exactly as the export renders it (edits, filter, layers),
  /// encoded at every level, and scaled by the page count. Other formats return
  /// an empty map.
  Future<Map<CompressionTier, int>> estimateSizes(
    ScanDocument document,
    ExportFormat format, {
    FilterType filter = FilterType.none,
  }) async {
    if ((format != ExportFormat.pdf && format != ExportFormat.jpg) || document.pagePaths.isEmpty) {
      return <CompressionTier, int>{};
    }
    final Uint8List page = await renderPageForOutput(document, 0, filter: filter);
    final int pages = document.pagePaths.length;
    final Map<CompressionTier, int> out = <CompressionTier, int>{};
    for (final CompressionTier tier in CompressionTier.values) {
      final int one = format == ExportFormat.pdf
          ? (await _compressForPdf(page, tier)).length
          : await Isolate.run(() {
              final img.Image? d = img.decodeImage(page);
              return d == null ? 0 : img.encodeJpg(d, quality: _qualityFor(tier)).length;
            });
      out[tier] = one * pages;
    }
    return out;
  }

  int _qualityFor(CompressionTier tier) {
    switch (tier) {
      case CompressionTier.original:
        return 92;
      case CompressionTier.medium:
        return 60;
      case CompressionTier.small:
        return 30;
    }
  }

  /// Binary-searches JPG quality to land as close to [targetBytes] as possible.
  int _findQualityForTarget(img.Image source, int targetBytes) {
    int lo = 20;
    int hi = 92;
    int bestQ = lo;
    int bestDiff = (img.encodeJpg(source, quality: lo).length - targetBytes).abs();
    while (lo <= hi) {
      final int mid = (lo + hi) ~/ 2;
      final int size = img.encodeJpg(source, quality: mid).length;
      final int diff = (size - targetBytes).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestQ = mid;
      }
      if (size < targetBytes) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return bestQ;
  }

  Future<String> _exportCsv(ScanDocument document, String outDir) async {
    final outPath = _outputPath(document, outDir, 'csv');
    try {
      // One row per OCR line, formula-safe, with a BOM so Excel reads UTF-8.
      await File(outPath).writeAsString(csvFromText(document.ocrText));
      return outPath;
    } catch (error, stackTrace) {
      _logError('_exportCsv', error, stackTrace);
      throw const ExportFailedException('Could not write the CSV file.');
    }
  }

    img.Image _trimNearBlackBorders(img.Image source) {
    double lumaOf(img.Color p) => 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    img.Image cur = source;
    for (final dark in const [false, true, true]) {
      bool colIs(int x) {
        int hit = 0, total = 0;
        for (int y = 0; y < cur.height; y += 4) {
          final l = lumaOf(cur.getPixel(x, y));
          total++;
          if (dark ? l < 60 : l > 220) hit++;
        }
        return total > 0 && hit / total > 0.85;
      }
      bool rowIs(int y) {
        int hit = 0, total = 0;
        for (int x = 0; x < cur.width; x += 4) {
          final l = lumaOf(cur.getPixel(x, y));
          total++;
          if (dark ? l < 60 : l > 220) hit++;
        }
        return total > 0 && hit / total > 0.85;
      }
      int left = 0, right = cur.width - 1, top = 0, bottom = cur.height - 1;
      // A border is never more than a small strip: a dark card or passport cover must
      // not be mistaken for a black border and trimmed away.
      final int maxX = (cur.width * 0.15).floor(), maxY = (cur.height * 0.15).floor();
      while (left < right && left < maxX && colIs(left)) {
        left++;
      }
      while (right > left && cur.width - 1 - right < maxX && colIs(right)) {
        right--;
      }
      while (top < bottom && top < maxY && rowIs(top)) {
        top++;
      }
      while (bottom > top && cur.height - 1 - bottom < maxY && rowIs(bottom)) {
        bottom--;
      }
      final w = right - left + 1, h = bottom - top + 1;
      if (w <= 0 || h <= 0 || (w == cur.width && h == cur.height)) continue;
      cur = img.copyCrop(cur, x: left, y: top, width: w, height: h);
    }
    return cur;
  }

  Future<Map<String, String>> exportIdCardPdf({
    required String frontPath,
    required String backPath,
    required String title,
    required String outputDirectoryPath,
    IdCardLayout layout = IdCardLayout.realSize,
  }) async {
    try {
      img.Image front = _trimNearBlackBorders(img.decodeImage(await _readBytes(frontPath))!);
      img.Image back = _trimNearBlackBorders(img.decodeImage(await _readBytes(backPath))!);

      final img.Image canvas;
      if (layout == IdCardLayout.realSize) {
        // A4 at 300 dpi; each side 85.6 mm wide (ISO card size), 10 mm apart.
        const int pageW = 2480, pageH = 3508;
        const int margin = 120;
        int cardW = (85.6 / 25.4 * 300).round();
        const int gap = 118;
        int frontH = (front.height * cardW / front.width).round();
        int backH = (back.height * cardW / back.width).round();
        // An unusually tall pair is shrunk (same factor on both) so it still fits the page.
        final int room = pageH - 2 * margin;
        if (frontH + gap + backH > room) {
          final double k = (room - gap) / (frontH + backH);
          cardW = (cardW * k).round();
          frontH = (front.height * cardW / front.width).round();
          backH = (back.height * cardW / back.width).round();
        }
        final int total = frontH + gap + backH;
        final int x = (pageW - cardW) ~/ 2;
        // 30 mm from the top when it fits, otherwise centred.
        final int top = (354 + total + margin <= pageH) ? 354 : ((pageH - total) ~/ 2);
        canvas = img.Image(width: pageW, height: pageH);
        img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(canvas, resizeSmooth(front, width: cardW, height: frontH), dstX: x, dstY: top);
        img.compositeImage(canvas, resizeSmooth(back, width: cardW, height: backH), dstX: x, dstY: top + frontH + gap);
      } else {
        const int canvasWidth = 1200;
        const int gap = 40;
        final int frontH = (front.height * canvasWidth / front.width).round();
        final int backH = (back.height * canvasWidth / back.width).round();
        canvas = img.Image(width: canvasWidth, height: frontH + gap + backH);
        img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(canvas, resizeSmooth(front, width: canvasWidth, height: frontH), dstX: 0, dstY: 0);
        img.compositeImage(canvas, resizeSmooth(back, width: canvasWidth, height: backH), dstX: 0, dstY: frontH + gap);
      }
      final Uint8List combinedBytes = Uint8List.fromList(img.encodePng(canvas));

      final String safeTitle = _sanitizeFileName(title);
      final String combinedPath = p.join(outputDirectoryPath, '$safeTitle.png');
      await _writeBytes(combinedPath, combinedBytes);

      final pw.Document pdfDoc = pw.Document(title: title, creator: 'KatharScan');
      pdfDoc.addPage(
        pw.Page(
          theme: await PdfFonts.theme(),
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Container(
              width: PdfPageFormat.a4.width,
              height: PdfPageFormat.a4.height,
              color: PdfColors.white,
              child: pw.Center(child: pw.Image(pw.MemoryImage(combinedBytes), fit: pw.BoxFit.contain)),
            );
          },
        ),
      );
      final pdfBytes = await pdfDoc.save();
      final String outPath = p.join(outputDirectoryPath, '$safeTitle.pdf');
      await _writeBytes(outPath, pdfBytes);
      return {'pdf': outPath, 'image': combinedPath};
    } catch (error, stackTrace) {
      _logError('exportIdCardPdf', error, stackTrace);
      throw ExportFailedException('Could not build the ID card PDF.');
    }
  }

  /// A logo watermark's picture with its opacity applied. A missing or unreadable
  /// logo stops the export: a page must never leave without the watermark it was
  /// given (it may be there to mark the file confidential).
  Future<img.Image> _readWatermarkLogo(WatermarkLayer wm) async {
    final Uint8List bytes = await _readBytes(wm.imagePath!);
    final img.Image? logo = img.decodeImage(bytes);
    if (logo == null) throw ExportFailedException('Could not read the watermark picture.');
    final img.Image rgba = logo.numChannels == 4 ? logo : logo.convert(numChannels: 4);
    if (wm.opacity < 1) {
      for (final img.Pixel px in rgba) {
        px.a = px.a * wm.opacity;
      }
    }
    return rgba;
  }

  /// A repeated watermark: drawn once over a page-sized transparent picture with
  /// the same code the preview uses, then laid over the page.
  Future<img.Image> _compositeWatermarkTiles(img.Image page, WatermarkLayer wm) async {
    ui.Image? logo;
    try {
      if (wm.isImage) {
        final Uint8List bytes = await _readBytes(wm.imagePath!);
        final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
        logo = (await codec.getNextFrame()).image;
      }
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      paintWatermarkTiles(canvas, ui.Size(page.width.toDouble(), page.height.toDouble()), wm, logo: logo);
      final ui.Image over = await recorder.endRecording().toImage(page.width, page.height);
      final ByteData? data = await over.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      over.dispose();
      if (data == null) return page;
      final img.Image layer = img.Image.fromBytes(
        width: page.width,
        height: page.height,
        bytes: data.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return img.compositeImage(page, layer);
    } catch (error, stackTrace) {
      _logError('_compositeWatermarkTiles', error, stackTrace);
      if (error is ExportFailedException) rethrow;
      throw ExportFailedException('Could not draw the watermark.');
    } finally {
      logo?.dispose();
    }
  }

  Future<Uint8List?> _renderWatermarkText(WatermarkLayer layer, int pageW) async {
    const double fontSize = 100;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Force LEFT align: the finished image is centered on the placement
    // by the compositor, so layer.align is meaningless for single-line text.
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ui.TextAlign.left,
      fontSize: fontSize,
      fontWeight: layer.bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
      fontStyle: layer.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
      fontFamily: layer.fontFamily,
    ))
      ..pushStyle(ui.TextStyle(
        color: ui.Color(layer.color).withValues(alpha: layer.opacity),
        decoration: layer.underline ? ui.TextDecoration.underline : ui.TextDecoration.none,
        shadows: layer.shadowColor != null
            ? [ui.Shadow(offset: ui.Offset(layer.shadowOffsetX, layer.shadowOffsetY), color: ui.Color(layer.shadowColor!), blurRadius: 2)]
            : null,
      ))
      ..addText(layer.text);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 100000));
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    // Use longestLine (actual text width), not paragraph.width (constraint 100000).
    final int iw = paragraph.longestLine.ceil().clamp(1, 32767);
    final int ih = paragraph.height.ceil().clamp(1, 32767);
    final image = await picture.toImage(iw, ih);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  /// Fill text: wraps inside a box [StampLayer.boxWidth] wide and is drawn at
  /// [StampLayer.fillSize] of the page width, so what is typed is the size it prints.
  Future<Uint8List?> _renderFillText(StampLayer layer, int pageW) async {
    if (layer.text.isEmpty) return null;
    final double fontPx = (layer.fillSize * pageW).clamp(6.0, 600.0).toDouble();
    final double width = (layer.boxWidth * pageW).clamp(20.0, pageW.toDouble()).toDouble();
    final double halo = fontPx * 0.03 < 1 ? 1 : fontPx * 0.03;
    final shadows = layer.halo
        ? [
            for (final o in <ui.Offset>[ui.Offset(halo, 0), ui.Offset(-halo, 0), ui.Offset(0, halo), ui.Offset(0, -halo), ui.Offset(halo, halo), ui.Offset(-halo, -halo), ui.Offset(halo, -halo), ui.Offset(-halo, halo)])
              ui.Shadow(offset: o, color: const ui.Color(0xFFFFFFFF), blurRadius: 0),
          ]
        : null;
    final ui.TextAlign align = layer.align == 'right'
        ? ui.TextAlign.right
        : (layer.align == 'center' ? ui.TextAlign.center : ui.TextAlign.left);
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align,
      fontSize: fontPx,
      fontWeight: ui.FontWeight.values.firstWhere((w) => w.value == layer.fontWeight, orElse: () => ui.FontWeight.w400),
      fontFamily: layer.fontFamily,
    ))
      ..pushStyle(ui.TextStyle(color: ui.Color(layer.color).withValues(alpha: layer.opacity), shadows: shadows))
      ..addText(layer.text);
    final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: width));
    final int w = width.ceil();
    final int h = (paragraph.height.ceil() + 2).clamp(1, 20000);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<Uint8List?> _renderStampText(StampLayer layer, int pageW) async {
    double fontSize = 100;
    // A picture wider than this cannot be created reliably. Very long text is
    // drawn smaller instead of failing the whole export.
    const double maxSide = 8000;
    final shadows = layer.halo
        ? [
            for (final o in const [ui.Offset(2, 0), ui.Offset(-2, 0), ui.Offset(0, 2), ui.Offset(0, -2), ui.Offset(2, 2), ui.Offset(-2, -2), ui.Offset(2, -2), ui.Offset(-2, 2)])
              ui.Shadow(offset: o, color: const ui.Color(0xFFFFFFFF), blurRadius: 0),
          ]
        : null;
    final ui.TextAlign align = layer.align == 'right'
        ? ui.TextAlign.right
        : (layer.align == 'center' ? ui.TextAlign.center : ui.TextAlign.left);

    ui.Paragraph build(double size) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: align,
        fontSize: size,
        fontWeight: ui.FontWeight.values.firstWhere((w) => w.value == layer.fontWeight, orElse: () => ui.FontWeight.w700),
        fontFamily: layer.fontFamily,
      ))
        ..pushStyle(ui.TextStyle(
          color: ui.Color(layer.color).withValues(alpha: layer.opacity),
          shadows: shadows,
        ))
        ..addText(layer.text);
      final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 100000));
      // Lay out again at the longest line's width so left/centre/right
      // alignment applies between the lines of a multi-line text.
      paragraph.layout(ui.ParagraphConstraints(width: paragraph.longestLine.ceilToDouble() + 1));
      return paragraph;
    }

    ui.Paragraph paragraph = build(fontSize);
    double pad = (layer.kind == 'note' ? 40.0 : 8.0) * (fontSize / 72.0);
    final double widest = paragraph.longestLine + pad * 2;
    final double tallest = paragraph.height + pad * 2;
    final double over = widest > tallest ? widest : tallest;
    if (over > maxSide) {
      fontSize = fontSize * maxSide / over;
      paragraph = build(fontSize);
      pad = (layer.kind == 'note' ? 40.0 : 8.0) * (fontSize / 72.0);
    }
    final int w = (paragraph.longestLine + pad * 2).ceil() + 1;
    final int h = (paragraph.height + pad * 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (layer.kind == 'note' && layer.noteBgColor != null) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), const ui.Radius.circular(16)),
        ui.Paint()..color = ui.Color(layer.noteBgColor!).withValues(alpha: layer.opacity),
      );
    }
    canvas.drawParagraph(paragraph, ui.Offset(pad, pad));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  /// [pixels] is roughly how wide the seal will be on the page; it is drawn at
  /// least that large (never below 480, never above 2048) so it is not enlarged,
  /// and so it stays sharp when the page is printed.
  Future<Uint8List?> _renderSeal(StampLayer layer, [int pixels = 480]) async {
    final double s = pixels.clamp(480, 2048).toDouble();
    
    // Decode center image if present
    ui.Image? centerImage;
    if (layer.sealCenter == 'image' && layer.sealImageBytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(layer.sealImageBytes!);
        final frame = await codec.getNextFrame();
        centerImage = frame.image;
      } catch (_) {}
    }
    
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    drawSeal(canvas, s, layer, centerImage: centerImage);
    final picture = recorder.endRecording();
    final image = await picture.toImage(s.round(), s.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<Uint8List?> _renderCheckbox(StampLayer layer) async {
    const double size = 240;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final shape = layer.checkShape ?? 'rounded';
    final boxColor = ui.Color(layer.boxColor ?? 0xFF111111).withValues(alpha: layer.opacity);
    final tickColor = ui.Color(layer.tickColor ?? 0xFF007AFF).withValues(alpha: layer.opacity);
    final checked = layer.checked ?? true;
    final box = ui.Paint()..color = boxColor..style = ui.PaintingStyle.stroke..strokeWidth = size * 0.067;
    if (shape == 'circle') {
      canvas.drawCircle(ui.Offset(size / 2, size / 2), size / 2 - size * 0.067, box);
    } else {
      final radius = shape == 'rounded' ? const ui.Radius.circular(24) : ui.Radius.zero;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(size * 0.033, size * 0.033, size - size * 0.067, size - size * 0.067), radius),
        box,
      );
    }
    if (checked) {
      final check = ui.Paint()
        ..color = tickColor
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = size * 0.1
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
      final path = ui.Path()
        ..moveTo(size * 0.25, size * 0.54)
        ..lineTo(size * 0.44, size * 0.73)
        ..lineTo(size * 0.77, size * 0.31);
      canvas.drawPath(path, check);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.round(), size.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<Uint8List> _readBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (error, stackTrace) {
      _logError('_readBytes', error, stackTrace);
      throw ExportFailedException('Could not read a source page ($path).');
    }
  }

  Future<void> _writeBytes(String path, Uint8List bytes) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    } catch (error, stackTrace) {
      _logError('_writeBytes', error, stackTrace);
      throw ExportFailedException('Could not write the exported file.');
    }
  }

  String _outputPath(
    ScanDocument document,
    String outDir,
    String extension, {
    String suffix = '',
  }) {
    final safeTitle = _sanitizeFileName(document.title);
    return p.join(outDir, '$safeTitle$suffix.$extension');
  }

  String _sanitizeFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[ExportService] $operation failed: $error');
    DebugLogService().log('EXPORT', '$operation failed: $error');
  }
}
