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

class ExportFailedException implements Exception {
  const ExportFailedException(this.message);
  final String message;
  @override
  String toString() => 'ExportFailedException: $message';
}

enum FilterType { none, grayscale, blackAndWhite, colorEnhance, shadowRemoval }
enum ExportSignatureScope { placed, all, first, last }

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
    int? signaturePageIndex,
    double? signatureOffsetX,
    double? signatureOffsetY,
    double? signatureRotation,
    ExportSignatureScope signatureScope = ExportSignatureScope.placed,
    double signatureScale = 1.0,
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
              signaturePageIndex: signaturePageIndex,
              signatureOffsetX: signatureOffsetX,
              signatureOffsetY: signatureOffsetY,
              signatureRotation: signatureRotation,
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
            signaturePageIndex: signaturePageIndex,
            signatureOffsetX: signatureOffsetX,
            signatureOffsetY: signatureOffsetY,
            signatureRotation: signatureRotation,
            compression: compression,
          targetBytes: targetBytes,
            signatureScope: signatureScope,
            signatureScale: signatureScale,
        );
        case ExportFormat.png:
          return await _exportImages(
            document,
            outputDirectoryPath,
            targetExtension: 'png',
            filter: filter,
            signatureBytes: signatureBytes,
            signaturePageIndex: signaturePageIndex,
            signatureOffsetX: signatureOffsetX,
            signatureOffsetY: signatureOffsetY,
            signatureRotation: signatureRotation,
            compression: compression,
          targetBytes: targetBytes,
            signatureScope: signatureScope,
            signatureScale: signatureScale,
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
    double offsetX,
    double offsetY, {
    double rotationDegrees = 0,
    double scale = 1.0,
  }) {
    if (rotationDegrees != 0) {
      signature = img.copyRotate(signature, angle: rotationDegrees);
    }
    final targetWidth = (page.width * 0.28 * scale).round();
    final targetHeight = (signature.height * targetWidth / signature.width).round();
    final resizedSignature = img.copyResize(
      signature,
      width: targetWidth,
      height: targetHeight,
    );
    final dstX = (offsetX * page.width).round();
    final dstY = (offsetY * page.height).round();
    return img.compositeImage(page, resizedSignature, dstX: dstX, dstY: dstY);
  }

  Future<Uint8List> _processPage(
    String pagePath, {
    required FilterType filter,
    required int pageIndex,
    required int totalPages,
    Uint8List? signatureBytes,
    int? signaturePageIndex,
    double? signatureOffsetX,
    double? signatureOffsetY,
    double? signatureRotation,
    ExportSignatureScope signatureScope = ExportSignatureScope.placed,
    double signatureScale = 1.0,
  }) async {
    final original = await _readBytes(pagePath);
    if (filter == FilterType.none && signatureBytes == null) {
      return original;
    }
    try {
      img.Image? decoded = img.decodeImage(original);
      if (decoded == null) return original;
      if (filter != FilterType.none) {
        decoded = _applyFilter(decoded, filter);
      }
      bool shouldApplySig = false;
      if (signatureBytes != null) {
        switch (signatureScope) {
          case ExportSignatureScope.placed: shouldApplySig = (pageIndex == (signaturePageIndex ?? totalPages - 1)); break;
          case ExportSignatureScope.all: shouldApplySig = true; break;
          case ExportSignatureScope.first: shouldApplySig = (pageIndex == 0); break;
          case ExportSignatureScope.last: shouldApplySig = (pageIndex == totalPages - 1); break;
        }
      }
      if (shouldApplySig) {
        final signatureImage = img.decodePng(signatureBytes!);
        if (signatureImage != null) {
          decoded = _compositeSignature(
            decoded,
            signatureImage,
            signatureOffsetX ?? 0.6,
            signatureOffsetY ?? 0.8,
            rotationDegrees: signatureRotation ?? 0,
            scale: signatureScale,
          );
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
    int? signaturePageIndex,
    double? signatureOffsetX,
    double? signatureOffsetY,
    double? signatureRotation,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    ExportSignatureScope signatureScope = ExportSignatureScope.placed,
    double signatureScale = 1.0,
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
        totalPages: document.pagePaths.length,
        signatureBytes: signatureBytes,
        signaturePageIndex: signaturePageIndex,
        signatureOffsetX: signatureOffsetX,
        signatureOffsetY: signatureOffsetY,
        signatureRotation: signatureRotation,
        signatureScope: signatureScope,
        signatureScale: signatureScale,
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
    int? signaturePageIndex,
    double? signatureOffsetX,
    double? signatureOffsetY,
    double? signatureRotation,
    CompressionTier compression = CompressionTier.original,
      int? targetBytes,
    ExportSignatureScope signatureScope = ExportSignatureScope.placed,
    double signatureScale = 1.0,
  }) async {
    final outputPaths = <String>[];
    final isMultiPage = document.pagePaths.length > 1;
    for (int i = 0; i < document.pagePaths.length; i++) {
      final processedBytes = await _processPage(
        document.pagePaths[i],
        filter: filter,
        pageIndex: i,
        totalPages: document.pagePaths.length,
        signatureBytes: signatureBytes,
        signaturePageIndex: signaturePageIndex,
        signatureOffsetX: signatureOffsetX,
        signatureOffsetY: signatureOffsetY,
        signatureRotation: signatureRotation,
        signatureScope: signatureScope,
        signatureScale: signatureScale,
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
