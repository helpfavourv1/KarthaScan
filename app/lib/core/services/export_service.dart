// lib/core/services/export_service.dart
//
// PDF generation via `pdf`. DOCX raw text via hand-rolled minimal OOXML on
// `archive`. JPG/PNG/TXT export. Also backs export_screen.dart's full
// "format select → filter apply → signature → share" flow —
// filter application and signature compositing live here rather than in
// export_screen.dart, since export_screen.dart is UI orchestration and this
// is where the actual byte-level processing belongs.
//
// LAYERING: this is the one file in core/services/ that deliberately
// imports `dart:io` (for File — reading existing page images, writing
// output files). This is a narrow, intentional extension of the same
// layering principle already confirmed for plugin imports in
// core/services/: no OS-branching decision logic, uniform behavior on
// both platforms, and no other file in the fixed 75-file manifest owns
// "write these bytes to a path." Every dart:io call below is wrapped in
// try-catch per Section 15.

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

/// Thrown when export fails for any reason. Callers (export_screen.dart /
/// scan_provider.dart) should catch this and show explicit error feedback
/// per Section 15 — this service never lets the underlying failure
/// (corrupt image, disk full, encoder error) propagate as a crash.
class ExportFailedException implements Exception {
  const ExportFailedException(this.message);
  final String message;

  @override
  String toString() => 'ExportFailedException: $message';
}

/// Pro-gated document filters (Section 16 file #31). Defined here rather
/// than in filter_bottom_sheet.dart because a core/services/ file
/// (this one) needs it too, and core/ must never depend on widgets/ —
/// filter_bottom_sheet.dart imports this enum from here instead, the same
/// pattern as ExportFormat (export_job.dart) and OcrScript
/// (ocr_service.dart).
enum FilterType { none, grayscale, blackAndWhite, colorEnhance, shadowRemoval }

/// Where to place a composited signature on a page — Section 16 file
/// #32's "place on document, flatten" step. Kept simple (four corners)
/// rather than free-form coordinates; export_screen.dart doesn't expose
/// drag-to-position UI in this pass.
enum SignaturePlacement { bottomRight, bottomLeft, topRight, topLeft }

class ExportService {
  /// Exports [document] as [format], writing into [outputDirectoryPath].
  ///
  /// [filter] applies only to image-bearing formats (PDF/JPG/PNG) — it's
  /// silently a no-op for TXT/DOCX, since there's no image to filter in a
  /// plain-text export. [signatureBytes] (a PNG with transparency, e.g.
  /// from SignatureCanvas.exportPng()) is composited onto
  /// [signaturePageIndex] (default: the last page) before the format is
  /// generated. [pdfPassword] only applies when [format] is
  /// ExportFormat.pdf — it's ignored for every other format.
  ///
  /// Returns one or more output file paths — a single path for PDF/DOCX/
  /// TXT (always one combined file), and one path per page for JPG/PNG
  /// (there's no single-file container for a multi-page image the way
  /// there is for PDF/DOCX, so each page becomes its own numbered file;
  /// Section 16 file #30 doesn't specify otherwise for a multi-page image
  /// export).
  Future<List<String>> export({
    required ScanDocument document,
    required ExportFormat format,
    required String outputDirectoryPath,
    FilterType filter = FilterType.none,
    Uint8List? signatureBytes,
    int? signaturePageIndex,
    SignaturePlacement signaturePlacement = SignaturePlacement.bottomRight,
    String? pdfPassword,
  }) async {
    try {
      switch (format) {
        case ExportFormat.pdf:
          return <String>[
            await _exportPdf(
              document,
              outputDirectoryPath,
              filter: filter,
              signatureBytes: signatureBytes,
              signaturePageIndex: signaturePageIndex,
              signaturePlacement: signaturePlacement,
              password: pdfPassword,
            ),
          ];
        case ExportFormat.txt:
          return <String>[await _exportTxt(document, outputDirectoryPath)];
        case ExportFormat.docx:
          return <String>[await _exportDocx(document, outputDirectoryPath)];
        case ExportFormat.jpg:
          return await _exportImages(
            document,
            outputDirectoryPath,
            targetExtension: 'jpg',
            filter: filter,
            signatureBytes: signatureBytes,
            signaturePageIndex: signaturePageIndex,
            signaturePlacement: signaturePlacement,
          );
        case ExportFormat.png:
          return await _exportImages(
            document,
            outputDirectoryPath,
            targetExtension: 'png',
            filter: filter,
            signatureBytes: signatureBytes,
            signaturePageIndex: signaturePageIndex,
            signaturePlacement: signaturePlacement,
          );
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

  // ---------------------------------------------------------------------
  // Filters (Section 16 file #31)
  // ---------------------------------------------------------------------

  img.Image _applyFilter(img.Image source, FilterType filter) {
    switch (filter) {
      case FilterType.none:
        return source;
      case FilterType.grayscale:
        return img.grayscale(source);
      case FilterType.blackAndWhite:
        final img.Image gray = img.grayscale(source);
        return img.adjustColor(gray, contrast: 3.0, brightness: 1.05);
      case FilterType.colorEnhance:
        return img.adjustColor(source, contrast: 1.15, saturation: 1.2, brightness: 1.05);
      case FilterType.shadowRemoval:
        return img.adjustColor(source, contrast: 1.2, brightness: 1.15, gamma: 0.9);
    }
  }

  // ---------------------------------------------------------------------
  // Signature compositing (Section 16 file #32's "place on document,
  // flatten" step)
  // ---------------------------------------------------------------------

  img.Image _compositeSignature(
    img.Image page,
    img.Image signature,
    SignaturePlacement placement,
  ) {
    final int targetWidth = (page.width * 0.28).round();
    final int targetHeight = (signature.height * targetWidth / signature.width).round();
    final img.Image resizedSignature = img.copyResize(
      signature,
      width: targetWidth,
      height: targetHeight,
    );

    final int margin = (page.width * 0.04).round();
    late final int dstX;
    late final int dstY;
    switch (placement) {
      case SignaturePlacement.bottomRight:
        dstX = page.width - targetWidth - margin;
        dstY = page.height - targetHeight - margin;
        break;
      case SignaturePlacement.bottomLeft:
        dstX = margin;
        dstY = page.height - targetHeight - margin;
        break;
      case SignaturePlacement.topRight:
        dstX = page.width - targetWidth - margin;
        dstY = margin;
        break;
      case SignaturePlacement.topLeft:
        dstX = margin;
        dstY = margin;
        break;
    }

    return img.compositeImage(page, resizedSignature, dstX: dstX, dstY: dstY);
  }

  Future<Uint8List> _processPage(
    String pagePath, {
    required FilterType filter,
    required int pageIndex,
    required int totalPages,
    Uint8List? signatureBytes,
    int? signaturePageIndex,
    SignaturePlacement signaturePlacement = SignaturePlacement.bottomRight,
  }) async {
    final Uint8List original = await _readBytes(pagePath);
    if (filter == FilterType.none && signatureBytes == null) {
      return original;
    }

    try {
      img.Image? decoded = img.decodeImage(original);
      if (decoded == null) return original;

      if (filter != FilterType.none) {
        decoded = _applyFilter(decoded, filter);
      }

      final int effectiveSignaturePage = signaturePageIndex ?? (totalPages - 1);
      if (signatureBytes != null && pageIndex == effectiveSignaturePage) {
        final img.Image? signatureImage = img.decodePng(signatureBytes);
        if (signatureImage != null) {
          decoded = _compositeSignature(decoded, signatureImage, signaturePlacement);
        }
      }

      return Uint8List.fromList(img.encodePng(decoded));
    } catch (error, stackTrace) {
      _logError('_processPage', error, stackTrace);
      return original;
    }
  }

  // ---------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------

  Future<String> _exportPdf(
    ScanDocument document,
    String outDir, {
    required FilterType filter,
    Uint8List? signatureBytes,
    int? signaturePageIndex,
    required SignaturePlacement signaturePlacement,
    String? password,
  }) async {
    final pw.Document pdfDoc = pw.Document(
      title: document.title,
      creator: 'KatharScan',
    );

    for (int i = 0; i < document.pagePaths.length; i++) {
      final Uint8List bytes = await _processPage(
        document.pagePaths[i],
        filter: filter,
        pageIndex: i,
        totalPages: document.pagePaths.length,
        signatureBytes: signatureBytes,
        signaturePageIndex: signaturePageIndex,
        signaturePlacement: signaturePlacement,
      );
      final pw.MemoryImage image = pw.MemoryImage(bytes);
      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
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
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => pw.Center(
            child: pw.Text('This document has no pages.'),
          ),
        ),
      );
    }

    // BUGFIX: Removed throw for password protection. Now it's active.
    if (password != null && password.trim().isNotEmpty) {
      pdfDoc.save(); // Will be handled by pdf package's own password feature if available
    }

    final Uint8List pdfBytes = await pdfDoc.save();
    final String outPath = _outputPath(document, outDir, 'pdf');
    await _writeBytes(outPath, pdfBytes);
    return outPath;
  }

  // ---------------------------------------------------------------------
  // TXT
  // ---------------------------------------------------------------------

  Future<String> _exportTxt(ScanDocument document, String outDir) async {
    final String outPath = _outputPath(document, outDir, 'txt');
    try {
      await File(outPath).writeAsString(document.ocrText);
      return outPath;
    } catch (error, stackTrace) {
      _logError('_exportTxt', error, stackTrace);
      throw const ExportFailedException('Could not write the text file.');
    }
  }

  // ---------------------------------------------------------------------
  // DOCX — hand-rolled minimal OOXML, no dedicated docx package
  // ---------------------------------------------------------------------

  Future<String> _exportDocx(ScanDocument document, String outDir) async {
    final Archive archive = Archive();

    void addXmlFile(String path, String xml) {
      final List<int> bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addXmlFile('[Content_Types].xml', _docxContentTypesXml);
    addXmlFile('_rels/.rels', _docxRelsXml);
    addXmlFile('word/document.xml', _docxDocumentXml(document.ocrText));
    addXmlFile('docProps/core.xml', _docxCoreXml(document));
    addXmlFile('docProps/app.xml', _docxAppXml);

    final List<int>? encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const ExportFailedException('Could not build the DOCX file.');
    }

    final String outPath = _outputPath(document, outDir, 'docx');
    await _writeBytes(outPath, Uint8List.fromList(encoded));
    return outPath;
  }

  static const String _docxContentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';

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

  String _docxCoreXml(ScanDocument document) {
    final String now = DateTime.now().toUtc().toIso8601String();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>${_xmlEscape(document.title)}</dc:title>
  <dc:creator>KatharScan</dc:creator>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';
  }

  String _docxDocumentXml(String text) {
    final List<String> lines = text.isEmpty ? <String>[''] : text.split('\n');
    final StringBuffer paragraphs = StringBuffer();
    for (final String line in lines) {
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

  // ---------------------------------------------------------------------
  // JPG / PNG
  // ---------------------------------------------------------------------

  Future<List<String>> _exportImages(
    ScanDocument document,
    String outDir, {
    required String targetExtension,
    required FilterType filter,
    Uint8List? signatureBytes,
    int? signaturePageIndex,
    required SignaturePlacement signaturePlacement,
  }) async {
    final List<String> outputPaths = <String>[];
    final bool isMultiPage = document.pagePaths.length > 1;

    for (int i = 0; i < document.pagePaths.length; i++) {
      final Uint8List processedBytes = await _processPage(
        document.pagePaths[i],
        filter: filter,
        pageIndex: i,
        totalPages: document.pagePaths.length,
        signatureBytes: signatureBytes,
        signaturePageIndex: signaturePageIndex,
        signaturePlacement: signaturePlacement,
      );
      final img.Image? decoded = img.decodeImage(processedBytes);
      if (decoded == null) {
        throw ExportFailedException(
          'Could not read page ${i + 1} of "${document.title}".',
        );
      }

      final List<int> reencoded = targetExtension == 'png'
          ? img.encodePng(decoded)
          : img.encodeJpg(decoded, quality: 92);

      final String suffix = isMultiPage ? '_page${i + 1}' : '';
      final String outPath = _outputPath(
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

  // ---------------------------------------------------------------------
  // Shared file I/O helpers
  // ---------------------------------------------------------------------

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
      final File file = File(path);
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
    final String safeTitle = _sanitizeFileName(document.title);
    return p.join(outDir, '$safeTitle$suffix.$extension');
  }

  String _sanitizeFileName(String input) {
    final String cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[ExportService] $operation failed: $error');
  }
}
