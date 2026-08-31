import '../utils/seal_draw.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/export_job.dart';
import '../models/scan_document.dart';
import '../models/page_transform.dart';
import '../models/signature_placement.dart';

class ExportFailedException implements Exception {
  const ExportFailedException(this.message);
  final String message;
  @override
  String toString() => 'ExportFailedException: $message';
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

class ExportService {
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
      );
    }
  }

  img.Image _applyFilter(img.Image source, FilterType filter) {
    switch (filter) {
      case FilterType.none:
        return source;
      case FilterType.grayscale:
        return img.grayscale(source);
      case FilterType.blackAndWhite:
        final gray = img.grayscale(source);
        return img.adjustColor(gray, contrast: 3.0, brightness: 1.05);
      case FilterType.colorEnhance:
        return img.adjustColor(source, contrast: 1.15, saturation: 1.2, brightness: 1.05);
      case FilterType.shadowRemoval:
        return img.adjustColor(source, contrast: 1.2, brightness: 1.15, gamma: 0.9);
    }
  }

  img.Image _compositeSignature(
    img.Image page,
    img.Image signature,
    SignaturePlacement placement,
  ) {
    final targetWidth = (page.width * 0.28 * placement.scale).round();
    final targetHeight = (signature.height * targetWidth / signature.width).round();
    var sig = img.copyResize(signature, width: targetWidth, height: targetHeight);
    if (placement.rotationDegrees != 0) {
      sig = img.copyRotate(sig, angle: placement.rotationDegrees);
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
    final hasTransform = pageTransform != null && (pageTransform.filter != FilterType.none || pageTransform.rotationTurns != 0 || pageTransform.cropRect != null || pageTransform.resizeWidth != null);
    if (filter == FilterType.none && !hasTransform && layers.isEmpty && annotateLayers.isEmpty && watermarkLayers.isEmpty && stampLayers.isEmpty) {
      return original;
    }
    try {
      final decodedOriginal = img.decodeImage(original);
      if (decodedOriginal == null) return original;
      img.Image decoded = decodedOriginal;
      final effectiveFilter = (pageTransform != null && pageTransform.filter != FilterType.none)
          ? pageTransform.filter
          : filter;
      if (pageTransform != null && pageTransform.cropRect != null && pageTransform.cropRect!.width > 0 && pageTransform.cropRect!.height > 0) {
        final r = pageTransform.cropRect!;
        decoded = img.copyCrop(decoded, x: r.left.round(), y: r.top.round(), width: r.width.round(), height: r.height.round());
      }
      if (pageTransform != null && pageTransform.resizeWidth != null && pageTransform.resizeHeight != null) {
        decoded = img.copyResize(decoded, width: pageTransform.resizeWidth!, height: pageTransform.resizeHeight!);
      }
      if (effectiveFilter != FilterType.none) {
        decoded = _applyFilter(decoded, effectiveFilter);
      }
      if (pageTransform != null && pageTransform.rotationTurns != 0) {
        decoded = img.copyRotate(decoded, angle: pageTransform.rotationTurns * 90);
      }
      for (final layer in layers) {
        final ink = inkMap[layer.inkId];
        final bytes = ink?.bytes ?? signatureBytes;
        if (bytes != null) {
          final sigImage = img.decodePng(bytes);
          if (sigImage != null) {
            decoded = _compositeSignature(decoded, sigImage, layer.placement);
          }
        }
      }
      for (final annotate in annotateLayers) {
        final annotateBytes = await _readBytes(annotate.bytesPath);
        final annotateImage = img.decodePng(annotateBytes);
        if (annotateImage != null) {
          decoded = _compositeSignature(decoded, annotateImage, annotate.placement);
        }
      }
      for (final wm in watermarkLayers) {
        final wmBytes = await _renderWatermarkText(wm, decoded.width);
        if (wmBytes != null) {
          final wmImage = img.decodePng(wmBytes);
          if (wmImage != null) {
            decoded = _compositeSignature(decoded, wmImage, wm.placement);
          }
        }
      }
      for (final st in stampLayers) {
        final stBytes = st.kind == 'checkbox'
            ? await _renderCheckbox(st)
            : (st.kind == 'seal' ? await _renderSeal(st) : await _renderStampText(st, decoded.width));
        if (stBytes != null) {
          final stImage = img.decodePng(stBytes);
          if (stImage != null) {
            decoded = _compositeSignature(decoded, stImage, st.placement);
          }
        }
      }
      return Uint8List.fromList(img.encodePng(decoded));
    } catch (error, stackTrace) {
      _logError('_processPage', error, stackTrace);
      return original;
    }
  }

  Future<String> _exportPdf(
    ScanDocument document,
    String outDir, {
    required FilterType filter,
    Uint8List? signatureBytes,
    Map<int, SignaturePlacement>? signaturePlacements,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final pw.Document pdfDoc = pw.Document(
      title: document.title,
      creator: 'KatharScan',
    );

    for (int i = 0; i < document.pagePaths.length; i++) {
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
      final image = pw.MemoryImage(bytes);
      pdfDoc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    if (document.pagePaths.isEmpty) {
      pdfDoc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (pw.Context context) => pw.Center(
            child: pw.Text('This document has no pages.'),
          ),
        ),
      );
    }

    final pdfBytes = await pdfDoc.save();
    final outPath = _outputPath(document, outDir, 'pdf');
    await _writeBytes(outPath, pdfBytes);
    return outPath;
  }

  Future<String> _exportTxt(ScanDocument document, String outDir) async {
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
    return _exportDocx(doc, outDir, mode: ExportDocxMode.textOnly);
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
    final archive = Archive();

    void addFile(String path, List<int> bytes) {
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    final List<List<int>> pageJpgs = <List<int>>[];
    if (mode == ExportDocxMode.imageEmbedded) {
      for (final path in document.pagePaths) {
        try {
          final bytes = await _readBytes(path);
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            pageJpgs.add(img.encodeJpg(decoded, quality: 92));
          }
        } catch (_) {}
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
        : _docxDocumentXml(document.ocrText),
    ));
    addFile('docProps/core.xml', utf8.encode(_docxCoreXml(document)));
    addFile('docProps/app.xml', utf8.encode(_docxAppXml));

    if (mode == ExportDocxMode.imageEmbedded) {
      addFile('word/_rels/document.xml.rels', utf8.encode(_docxDocumentRelsXml(pageJpgs.length)));
      for (int i = 0; i < pageJpgs.length; i++) {
        addFile('word/media/image${i + 1}.jpeg', pageJpgs[i]);
      }
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
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
      final int widthEmu = 5486400;  // 6 inches
      final int heightEmu = 7315200; // 8 inches
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

  String _docxDocumentXml(String text) {
    final lines = text.isEmpty ? [''] : text.split('\n');
    final paragraphs = StringBuffer();
    for (final line in lines) {
      if (line.isEmpty) {
        paragraphs.writeln('<w:p/>');
      } else {
        paragraphs.writeln(
          '<w:p><w:r><w:t xml:space="preserve">${_xmlEscape(line)}</w:t></w:r></w:p>',
        );
      }
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $paragraphs
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';
  }

  String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
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
      final String escaped = document.ocrText.replaceAll('"', '""');
      await File(outPath).writeAsString('"$escaped"');
      return outPath;
    } catch (error, stackTrace) {
      _logError('_exportCsv', error, stackTrace);
      throw const ExportFailedException('Could not write the CSV file.');
    }
  }

  Future<String> exportIdCardPdf({
    required String frontPath,
    required String backPath,
    required String title,
    required String outputDirectoryPath,
  }) async {
    try {
      final pw.Document pdfDoc = pw.Document(title: title, creator: 'KatharScan');
      final Uint8List frontBytes = await _readBytes(frontPath);
      final Uint8List backBytes = await _readBytes(backPath);
      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Image(pw.MemoryImage(frontBytes), fit: pw.BoxFit.contain, height: 380),
                pw.SizedBox(height: 30),
                pw.Image(pw.MemoryImage(backBytes), fit: pw.BoxFit.contain, height: 380),
              ],
            );
          },
        ),
      );
      final Uint8List pdfBytes = await pdfDoc.save();
      final String safeTitle = _sanitizeFileName(title);
      final String outPath = p.join(outputDirectoryPath, '$safeTitle.pdf');
      await _writeBytes(outPath, pdfBytes);
      return outPath;
    } catch (error, stackTrace) {
      _logError('exportIdCardPdf', error, stackTrace);
      throw ExportFailedException('Could not build the ID card PDF.');
    }
  }

  Future<Uint8List?> _renderWatermarkText(WatermarkLayer layer, int pageW) async {
    final fontSize = layer.fontSize * layer.placement.scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: layer.align == 'left' ? ui.TextAlign.left : (layer.align == 'right' ? ui.TextAlign.right : ui.TextAlign.center),
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
      ..layout(ui.ParagraphConstraints(width: pageW * 0.3 * layer.placement.scale));
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(paragraph.width.round(), paragraph.height.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<Uint8List?> _renderStampText(StampLayer layer, int pageW) async {
    final fontSize = layer.fontSize * layer.placement.scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final shadows = layer.halo
        ? [
            for (final o in const [ui.Offset(2, 0), ui.Offset(-2, 0), ui.Offset(0, 2), ui.Offset(0, -2), ui.Offset(2, 2), ui.Offset(-2, -2), ui.Offset(2, -2), ui.Offset(-2, 2)])
              ui.Shadow(offset: o, color: const ui.Color(0xFFFFFFFF), blurRadius: 0),
          ]
        : null;
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: layer.align == 'left' ? ui.TextAlign.left : (layer.align == 'right' ? ui.TextAlign.right : ui.TextAlign.center),
      fontSize: fontSize,
      fontWeight: ui.FontWeight.values.firstWhere((w) => w.value == layer.fontWeight, orElse: () => ui.FontWeight.w700),
      fontFamily: layer.fontFamily,
    ))
      ..pushStyle(ui.TextStyle(
        color: ui.Color(layer.color).withValues(alpha: layer.opacity),
        shadows: shadows,
      ))
      ..addText(layer.text);
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: pageW * 0.3 * layer.placement.scale));
    final double pad = (layer.kind == 'note' ? 40.0 : 8.0) * (fontSize / 72.0);
    final int w = (paragraph.longestLine + pad * 2).ceil();
    final int h = (paragraph.height + pad * 2).ceil();
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

  Future<Uint8List?> _renderSeal(StampLayer layer) async {
    const double s = 480;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    drawSeal(canvas, s, layer);
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
  }
}
