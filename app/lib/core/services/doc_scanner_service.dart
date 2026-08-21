// lib/core/services/doc_scanner_service.dart
import 'dart:io' show Directory, File;
import 'dart:typed_data';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'debug_log_service.dart';
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
  final DebugLogService _log = DebugLogService();

  Future<DocScanResult> scan({int maxPages = 20}) async {
    _log.log('SCANNER', 'Starting scan flow (maxPages=$maxPages)');

    try {
      _log.log('SCANNER', 'Attempt 1: getScannedDocumentAsImages');
      final dynamic raw = await _scanner.getScannedDocumentAsImages(page: maxPages);
      _log.log('SCANNER', 'Attempt 1 raw: type=${raw.runtimeType} value=$raw');
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        _log.log('SCANNER', 'Attempt 1 SUCCESS: ${paths.length} paths');
        return DocScanResult(pageImagePaths: paths);
      }
      _log.log('SCANNER', 'Attempt 1 returned empty paths');
    } on PlatformException catch (error) {
      _log.log('SCANNER', 'Attempt 1 PlatformException: ${error.code} | ${error.message}');
      if (error.code == 'UNSUPPORTED') {
        throw const DocScannerUnsupportedException(
          AppPluginFailureCopy.docScannerUnsupportedMessage,
        );
      }
    } catch (error) {
      _log.log('SCANNER', 'Attempt 1 error: $error');
    }

    try {
      _log.log('SCANNER', 'Attempt 2: getScanDocumentsUri');
      final dynamic raw = await _scanner.getScanDocumentsUri(page: maxPages);
      _log.log('SCANNER', 'Attempt 2 raw: type=${raw.runtimeType} value=$raw');
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        _log.log('SCANNER', 'Attempt 2 SUCCESS: ${paths.length} paths');
        return DocScanResult(pageImagePaths: paths);
      }
      _log.log('SCANNER', 'Attempt 2 returned empty paths');
    } catch (error) {
      _log.log('SCANNER', 'Attempt 2 error: $error');
    }

    try {
      _log.log('SCANNER', 'Attempt 3: getScanDocuments');
      final dynamic raw = await _scanner.getScanDocuments(page: maxPages);
      _log.log('SCANNER', 'Attempt 3 raw: type=${raw.runtimeType} value=$raw');
      final List<String> paths = await _extractPaths(raw);
      if (paths.isNotEmpty) {
        _log.log('SCANNER', 'Attempt 3 SUCCESS: ${paths.length} paths');
        return DocScanResult(pageImagePaths: paths);
      }
      _log.log('SCANNER', 'Attempt 3 returned empty paths');
    } catch (error) {
      _log.log('SCANNER', 'Attempt 3 error: $error');
    }

    _log.log('SCANNER', 'All attempts exhausted → throwing UnsupportedException');
    throw const DocScannerUnsupportedException(
      AppPluginFailureCopy.docScannerUnsupportedMessage,
    );
  }

  Future<List<String>> _extractPaths(dynamic raw) async {
    if (raw == null) return const <String>[];

    if (raw is List) {
      if (raw.isEmpty) return const <String>[];
      final List<String> strings = raw.whereType<String>().toList();
      if (strings.isNotEmpty) {
        return strings.map((s) => s.replaceFirst('file://', '')).toList();
      }
      final List<String> fromMaps = raw
          .whereType<Map>()
          .map((dynamic m) => _extractStringFromMap(m as Map))
          .where((String? s) => s != null)
          .cast<String>()
          .toList();
      if (fromMaps.isNotEmpty) return fromMaps;
      final List<Uint8List> byteArrays = raw.whereType<Uint8List>().toList();
      if (byteArrays.isNotEmpty) return _saveByteArrays(byteArrays);
    }

    if (raw is Map) {
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
        if (value is String) return <String>[value.replaceFirst('file://', '')];
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
          if (byteArrays.isNotEmpty) return _saveByteArrays(byteArrays);
        }
        if (value is Map) {
          final String? nested = _extractStringFromMap(value);
          if (nested != null) return <String>[nested];
        }
        if (value is Uint8List) return _saveByteArrays(<Uint8List>[value]);
      }
    }

    if (raw is String) return <String>[raw.replaceFirst('file://', '')];
    if (raw is Uint8List) return _saveByteArrays(<Uint8List>[raw]);
    return const <String>[];
  }

  String? _extractStringFromMap(Map map) {
    for (final String key in const <String>[
      'uri', 'path', 'filePath', 'url', 'imagePath', 'imageUri', 'fileUri', 'pdfUri', 'pdfPath',
    ]) {
      final Object? value = map[key];
      if (value is String && value.isNotEmpty) return value.replaceFirst('file://', '');
    }
    return null;
  }

  Future<List<String>> _saveByteArrays(List<Uint8List> byteArrays) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory scansDir = Directory(p.join(appDir.path, 'scanner_fallback_pages'));
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
    _log.log('SCANNER', 'Saved ${paths.length} byte arrays to disk');
    return paths;
  }
}
