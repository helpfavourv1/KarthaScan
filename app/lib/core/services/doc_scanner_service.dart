// lib/core/services/doc_scanner_service.dart
import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../utils/constants.dart';

class DocScannerUnsupportedException implements Exception {
  const DocScannerUnsupportedException(this.message);
  final String message;
  @override
  String toString() => 'DocScannerUnsupportedException: $message';
}

class DocScannerFailedException implements Exception {
  const DocScannerFailedException(this.message);
  final String message;
  @override
  String toString() => 'DocScannerFailedException: $message';
}

class DocScanResult {
  const DocScanResult({required this.pageImagePaths});
  final List<String> pageImagePaths;
}

class DocScannerService {
  final FlutterDocScanner _scanner = FlutterDocScanner();

  /// Last raw debug output from the scanner. Read by UI when scan fails.
  static String lastRawDebug = '';

  Future<DocScanResult> scan({int maxPages = 20}) async {
    lastRawDebug = '';

    // Attempt 1: getScannedDocumentAsImages (preferred — returns image paths)
    try {
      final dynamic raw = await _scanner.getScannedDocumentAsImages(page: maxPages);
      lastRawDebug = 'ImagesMethod: type=${raw.runtimeType} value=$raw';
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        final List<String> finalPaths = await _ensureImages(paths);
        return DocScanResult(pageImagePaths: finalPaths);
      }
    } on PlatformException catch (error, stackTrace) {
      _logError('getScannedDocumentAsImages', error, stackTrace);
      if (error.code == 'UNSUPPORTED') {
        throw const DocScannerUnsupportedException(
          AppPluginFailureCopy.docScannerUnsupportedMessage,
        );
      }
    } catch (error, stackTrace) {
      _logError('getScannedDocumentAsImages', error, stackTrace);
    }

    // Attempt 2: getScanDocumentsUri (fallback — returns URI list)
    try {
      final dynamic raw = await _scanner.getScanDocumentsUri(page: maxPages);
      lastRawDebug = 'UriMethod: type=${raw.runtimeType} value=$raw';
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        final List<String> finalPaths = await _ensureImages(paths);
        return DocScanResult(pageImagePaths: finalPaths);
      }
    } catch (error, stackTrace) {
      _logError('getScanDocumentsUri', error, stackTrace);
    }

    // Attempt 3: getScanDocuments (last resort — may return PDF or images)
    try {
      final dynamic raw = await _scanner.getScanDocuments(page: maxPages);
      lastRawDebug = 'DocsMethod: type=${raw.runtimeType} value=$raw';
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        final List<String> finalPaths = await _ensureImages(paths);
        return DocScanResult(pageImagePaths: finalPaths);
      }
    } catch (error, stackTrace) {
      _logError('getScanDocuments', error, stackTrace);
    }

    // All attempts exhausted
    throw const DocScannerUnsupportedException(
      AppPluginFailureCopy.docScannerUnsupportedMessage,
    );
  }

  /// Intercepts paths before returning them. If a path is a PDF, it routes it
  /// through the renderer to convert its pages into JPGs. 
  /// Standard image paths pass through untouched.
  Future<List<String>> _ensureImages(List<String> paths) async {
    final List<String> finalPaths = <String>[];
    
    for (final String path in paths) {
      if (path.toLowerCase().endsWith('.pdf')) {
        try {
          finalPaths.addAll(await _convertPdfToImages(path));
        } catch (error, stackTrace) {
          _logError('PDF Conversion', error, stackTrace);
        }
      } else {
        finalPaths.add(path);
      }
    }
    return finalPaths;
  }

  /// Uses `pdfx` to crack open a PDF and render its pages to disk as JPGs.
  Future<List<String>> _convertPdfToImages(String pdfPath) async {
    final List<String> outputPaths = <String>[];
    final PdfDocument document = await PdfDocument.openFile(pdfPath); //
    
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory scansDir = Directory(p.join(appDir.path, 'scanner_converted_pages'));
    await scansDir.create(recursive: true);

    // pdfx uses 1-based indexing
    for (int i = 1; i <= document.pagesCount; i++) {
      final PdfPage page = await document.getPage(i); //
      
      // Render at 2x resolution to maintain document crispness for OCR/cropping
      final PdfPageImage? pageImage = await page.render(
        width: page.width * 2, //
        height: page.height * 2, //
        format: PdfPageImageFormat.jpeg, //
      );

      if (pageImage != null) {
        final String outPath = p.join(
          scansDir.path,
          'converted_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
        );
        await File(outPath).writeAsBytes(pageImage.bytes); //
        outputPaths.add(outPath);
      }
      await page.close(); //
    }
    
    await document.close(); //
    return outputPaths;
  }

  Future<List<String>> _extractPaths(dynamic raw) async {
    if (raw == null) return const <String>[];

    // Direct List<String>
    if (raw is List) {
      if (raw.isEmpty) return const <String>[];

      final List<String> strings = raw.whereType<String>().toList();
      if (strings.isNotEmpty) return strings.map((s) => s.replaceFirst('file://', '')).toList();

      final List<String> fromMaps = raw
          .whereType<Map>()
          .map((dynamic m) => _extractStringFromMap(m as Map))
          .where((String? s) => s != null)
          .cast<String>()
          .toList();
      if (fromMaps.isNotEmpty) return fromMaps;

      final List<Uint8List> byteArrays = raw.whereType<Uint8List>().toList();
      if (byteArrays.isNotEmpty) {
        return _saveByteArrays(byteArrays);
      }
    }

    // Map wrapper — try every known key
    if (raw is Map) {
      // Direct check for root keys like 'pdfUri'
      final String? directPath = _extractStringFromMap(raw);
      if (directPath != null) return <String>[directPath];

      const List<String> candidateKeys = <String>[
        'images', 'Images', 'imagePaths', 'scannedImages', 'Uri', 'uri', 'uris',
        'paths', 'path', 'files', 'imageUris', 'result', 'data', 'pdf', 'PDF',
        'document', 'documents', 'pages', 'image',
      ];

      for (final String key in candidateKeys) {
        final Object? value = raw[key];
        if (value == null) continue;

        if (value is String) {
          return <String>[value.replaceFirst('file://', '')];
        }

        if (value is List) {
          final List<String> strings = value.whereType<String>().toList();
          if (strings.isNotEmpty) return strings.map((s) => s.replaceFirst('file://', '')).toList();

          final List<String> fromMaps = value
              .whereType<Map>()
              .map((dynamic m) => _extractStringFromMap(m as Map))
              .where((String? s) => s != null)
              .cast<String>()
              .toList();
          if (fromMaps.isNotEmpty) return fromMaps;

          final List<Uint8List> byteArrays = value.whereType<Uint8List>().toList();
          if (byteArrays.isNotEmpty) {
            return _saveByteArrays(byteArrays);
          }
        }

        if (value is Map) {
          final String? nested = _extractStringFromMap(value);
          if (nested != null) return <String>[nested];
        }

        if (value is Uint8List) {
          return _saveByteArrays(<Uint8List>[value]);
        }
      }
    }

    // Single String path
    if (raw is String) {
      return <String>[raw.replaceFirst('file://', '')];
    }

    // Single Uint8List (raw bytes)
    if (raw is Uint8List) {
      return _saveByteArrays(<Uint8List>[raw]);
    }

    return const <String>[];
  }

  String? _extractStringFromMap(Map map) {
    for (final String key in const <String>[
      'uri', 'path', 'filePath', 'url', 'imagePath', 'imageUri', 'fileUri', 'pdfUri', 'pdfPath',
    ]) {
      final Object? value = map[key];
      if (value is String && value.isNotEmpty) {
        // Automatically strips the file:// prefix to prevent File() crashes on Android
        return value.replaceFirst('file://', '');
      }
    }
    return null;
  }

  Future<List<String>> _saveByteArrays(List<Uint8List> byteArrays) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory scansDir =
        Directory(p.join(appDir.path, 'scanner_fallback_pages'));
    await scansDir.create(recursive: true);

    final List<String> paths = <String>[];
    for (int i = 0; i < byteArrays.length; i++) {
      final String outPath = p.join(
        scansDir.path,
        'scan_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
      );
      await File(outPath).writeAsBytes(byteArrays[i]);
      paths.add(outPath);
    }
    return paths;
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[DocScannerService] $operation failed: $error');
  }
}
