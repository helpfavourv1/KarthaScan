// lib/core/services/doc_scanner_service.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';

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
    try {
      final dynamic raw =
          await _scanner.getScannedDocumentAsImages(page: maxPages);
      final List<String> paths = _extractPaths(raw);
      return DocScanResult(pageImagePaths: paths);
    } on PlatformException catch (error, stackTrace) {
      lastRawDebug = 'PlatformException: code=${error.code} message=${error.message}';
      _logError('scan', error, stackTrace);
      if (error.code == 'UNSUPPORTED') {
        throw const DocScannerUnsupportedException(
          AppPluginFailureCopy.docScannerUnsupportedMessage,
        );
      }
      throw DocScannerFailedException(
        error.message ?? 'Document scanning failed.',
      );
    } catch (error, stackTrace) {
      lastRawDebug = 'Exception: $error';
      _logError('scan', error, stackTrace);
      throw const DocScannerFailedException('Document scanning failed.');
    }
  }

  List<String> _extractPaths(dynamic raw) {
    lastRawDebug = 'type=${raw.runtimeType} value=$raw';
    debugPrint('[DocScannerService] RAW RETURN: $lastRawDebug');

    if (raw == null) return const <String>[];

    if (raw is List) {
      final List<String> direct = raw.whereType<String>().toList();
      if (direct.isNotEmpty) return direct;

      final List<String> fromMaps = raw
          .whereType<Map>()
          .map((dynamic m) => _extractStringFromMap(m as Map))
          .where((String? s) => s != null)
          .cast<String>()
          .toList();
      if (fromMaps.isNotEmpty) return fromMaps;
    }

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
      ];

      for (final String key in candidateKeys) {
        final Object? value = raw[key];
        if (value == null) continue;

        if (value is String) {
          return <String>[value];
        }

        if (value is List) {
          final List<String> direct = value.whereType<String>().toList();
          if (direct.isNotEmpty) return direct;

          final List<String> fromMaps = value
              .whereType<Map>()
              .map((dynamic m) => _extractStringFromMap(m as Map))
              .where((String? s) => s != null)
              .cast<String>()
              .toList();
          if (fromMaps.isNotEmpty) return fromMaps;
        }
      }
    }

    if (raw is String) {
      return <String>[raw];
    }

    lastRawDebug = 'Unrecognized return shape: ${raw.runtimeType}';
    debugPrint(
      '[DocScannerService] Unrecognized return shape from '
      'getScannedDocumentAsImages(): ${raw.runtimeType}',
    );
    throw const DocScannerFailedException(
      'Scanner returned data in an unexpected format.',
    );
  }

  String? _extractStringFromMap(Map map) {
    for (final String key in const <String>['uri', 'path', 'filePath', 'url']) {
      final Object? value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[DocScannerService] $operation failed: $error');
  }
}
