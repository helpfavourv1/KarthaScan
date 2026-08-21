// lib/core/services/doc_scanner_service.dart
import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
      final dynamic raw = await _scanner.getScannedDocumentAsImages();
      lastRawDebug = 'ImagesMethod: type=${raw.runtimeType} value=$raw';
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        return DocScanResult(pageImagePaths: paths);
      }
    } on PlatformException catch (error, stackTrace) {
      _logError('getScannedDocumentAsImages', error, stackTrace);
      if (error.code == 'UNSUPPORTED') {
        throw const DocScannerUnsupportedException(
          AppPluginFailureCopy.docScannerUnsupportedMessage,
        );
      }
      // Fall through to attempt 2
    } catch (error, stackTrace) {
      _logError('getScannedDocumentAsImages', error, stackTrace);
      // Fall through to attempt 2
    }

    // Attempt 2: getScanDocumentsUri (fallback — returns URI list)
    try {
      final dynamic raw = await _scanner.getScanDocumentsUri();
      lastRawDebug = 'UriMethod: type=${raw.runtimeType} value=$raw';
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        return DocScanResult(pageImagePaths: paths);
      }
    } catch (error, stackTrace) {
      _logError('getScanDocumentsUri', error, stackTrace);
      // Fall through to attempt 3
    }

    // Attempt 3: getScanDocuments (last resort — may return PDF or images)
    try {
      final dynamic raw = await _scanner.getScanDocuments();
      lastRawDebug = 'DocsMethod: type=${raw.runtimeType} value=$raw';
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        return DocScanResult(pageImagePaths: paths);
      }
    } catch (error, stackTrace) {
      _logError('getScanDocuments', error, stackTrace);
    }

    // All attempts exhausted
    throw DocScannerFailedException(
      lastRawDebug.isNotEmpty
          ? 'Scanner failed. $lastRawDebug'
          : 'Document scanner returned no images.',
    );
  }

  /// Normalizes flutter_doc_scanner's untyped return value to
  /// `List<String>` of file paths. Also handles raw bytes by saving
  /// them to disk.
  Future<List<String>> _extractPaths(dynamic raw) async {
    if (raw == null) return const <String>[];

    // Direct List<String>
    if (raw is List) {
      if (raw.isEmpty) return const <String>[];

      // List of Strings (file paths)
      final List<String> strings = raw.whereType<String>().toList();
      if (strings.isNotEmpty) return strings;

      // List of Maps (each containing a path/uri key)
      final List<String> fromMaps = raw
          .whereType<Map>()
          .map((dynamic m) => _extractStringFromMap(m as Map))
          .where((String? s) => s != null)
          .cast<String>()
          .toList();
      if (fromMaps.isNotEmpty) return fromMaps;

      // List of Uint8List (raw image bytes) — save each to disk
      final List<Uint8List> byteArrays = raw.whereType<Uint8List>().toList();
      if (byteArrays.isNotEmpty) {
        return _saveByteArrays(byteArrays);
      }
    }

    // Map wrapper — try every known key
    if (raw is Map) {
      const List<String> candidateKeys = <String>[
        'images',
        'Images',
        'imagePaths',
        'scannedImages',
        'Uri',
        'uri',
        'uris',
        'paths',
        'path',
        'files',
        'imageUris',
        'result',
        'data',
        'pdf',
        'PDF',
        'document',
        'documents',
        'pages',
        'image',
      ];

      for (final String key in candidateKeys) {
        final Object? value = raw[key];
        if (value == null) continue;

        if (value is String) {
          return <String>[value];
        }

        if (value is List) {
          final List<String> strings = value.whereType<String>().toList();
          if (strings.isNotEmpty) return strings;

          final List<String> fromMaps = value
              .whereType<Map>()
              .map((dynamic m) => _extractStringFromMap(m as Map))
              .where((String? s) => s != null)
              .cast<String>()
              .toList();
          if (fromMaps.isNotEmpty) return fromMaps;

          final List<Uint8List> byteArrays =
              value.whereType<Uint8List>().toList();
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
      return <String>[raw];
    }

    // Single Uint8List (raw bytes)
    if (raw is Uint8List) {
      return _saveByteArrays(<Uint8List>[raw]);
    }

    return const <String>[];
  }

  String? _extractStringFromMap(Map map) {
    for (final String key in const <String>[
      'uri',
      'path',
      'filePath',
      'url',
      'imagePath',
      'imageUri',
      'fileUri',
      'pdfUri',
      'pdfPath',
    ]) {
      final Object? value = map[key];
      if (value is String && value.isNotEmpty) return value;
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
