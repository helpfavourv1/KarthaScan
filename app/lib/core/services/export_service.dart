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
              signatureOffsetX: signatureOffsetX,
              signatureOffsetY: signatureOffsetY,
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
            signatureOffsetX: signatureOffsetX,
            signatureOffsetY: signatureOffsetY,
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
    double offsetY,
  ) {
    final targetWidth = (page.width * 0.28).round();
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
      final effectiveSignaturePage = signaturePageIndex ?? (totalPages - 1);
      if (signatureBytes != null && pageIndex == effectiveSignaturePage) {
        final signatureImage = img.decodePng(signatureBytes);
        if (signatureImage != null) {
          decoded = _compositeSignature(
            decoded,
            signatureImage,
            signatureOffsetX ?? 0.6,
            signatureOffsetY ?? 0.8,
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
      );
      final image = pw.MemoryImage(bytes);
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

  Future<String> _exportDocx(ScanDocument document, String outDir) async {
    final archive = Archive();

    void addXmlFile(String path, String xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addXmlFile('[Content_Types].xml', _docxContentTypesXml);
    addXmlFile('_rels/.rels', _docxRelsXml);
    addXmlFile('word/document.xml', _docxDocumentXml(document.ocrText));
    addXmlFile('docProps/core.xml', _docxCoreXml(document));
    addXmlFile('docProps/app.xml', _docxAppXml);

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const ExportFailedException('Could not build the DOCX file.');
    }

    final outPath = _outputPath(document, outDir, 'docx');
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
      );
      final decoded = img.decodeImage(processedBytes);
      if (decoded == null) {
        throw ExportFailedException(
          'Could not read page ${i + 1} of "${document.title}".',
        );
      }
      final reencoded = targetExtension == 'png'
          ? img.encodePng(decoded)
          : img.encodeJpg(decoded, quality: 92);
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
