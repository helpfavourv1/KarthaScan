// lib/core/providers/scan_provider.dart
//
// ValueNotifier<List<ScanDocument>> + activeScan + CRUD operations
// (Section 16 file #21). Orchestrates DocScannerService (capture),
// OcrService (text extraction), and LocalStorageService (persistence)
// into the app's core "scan a document" flow.
//
// REACTIVITY: ValueNotifier + ListenableBuilder only, per the MANDATORY
// constraint in constants.dart.

import 'dart:async' show unawaited;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;

import '../models/scan_document.dart';
import '../services/doc_scanner_service.dart';
import '../services/local_storage.dart';
import '../services/ocr_service.dart';

enum ScanFlowState { idle, scanning, recognizingText, saving, error, unsupported }

class ScanProvider {
  ScanProvider({
    required LocalStorageService storage,
    required DocScannerService docScanner,
    required OcrService ocr,
  })  : _storage = storage,
        _docScanner = docScanner,
        _ocr = ocr {
    unawaited(_loadAll());
  }

  final LocalStorageService _storage;
  final DocScannerService _docScanner;
  final OcrService _ocr;
  final Random _random = Random();

  final ValueNotifier<List<ScanDocument>> documents =
      ValueNotifier<List<ScanDocument>>(const <ScanDocument>[]);
  final ValueNotifier<ScanDocument?> activeScan =
      ValueNotifier<ScanDocument?>(null);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<ScanFlowState> scanFlowState =
      ValueNotifier<ScanFlowState>(ScanFlowState.idle);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  final ValueNotifier<bool> ocrUnavailable = ValueNotifier<bool>(false);

  Future<void> _loadAll() async {
    isLoading.value = true;
    try {
      documents.value = await _storage.getAllDocuments();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refresh() async {
    documents.value = await _storage.getAllDocuments();
  }

  // Issue 6: Accept ocrScript parameter instead of hardcoded Latin
  Future<ScanDocument?> captureNewDocument({
    String? title,
    OcrScript ocrScript = OcrScript.latin,
  }) async {
    scanFlowState.value = ScanFlowState.scanning;
    lastError.value = null;
    try {
      final DocScanResult scanResult = await _docScanner.scan();
      if (scanResult.pageImagePaths.isEmpty) {
        scanFlowState.value = ScanFlowState.idle;
        return null;
      }

      scanFlowState.value = ScanFlowState.recognizingText;
      final String ocrText =
          await _recognizeAllPages(scanResult.pageImagePaths, ocrScript);

      scanFlowState.value = ScanFlowState.saving;
      final DateTime now = DateTime.now();
      final ScanDocument document = ScanDocument(
        id: _generateId(),
        title: (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : _defaultTitle(now),
        pageCount: scanResult.pageImagePaths.length,
        pagePaths: scanResult.pageImagePaths,
        createdAt: now,
        updatedAt: now,
        ocrText: ocrText,
        thumbnailPath: scanResult.pageImagePaths.first,
      );

      await _storage.saveDocument(document);
      documents.value = <ScanDocument>[document, ...documents.value];
      activeScan.value = document;
      scanFlowState.value = ScanFlowState.idle;
      return document;
    } on DocScannerUnsupportedException catch (error) {
      debugPrint('MAIN SCANNER UNSUPPORTED: ${error.message}');
      scanFlowState.value = ScanFlowState.unsupported;
      lastError.value = error.message;
      return null;
    } on DocScannerFailedException catch (error) {
      debugPrint('MAIN SCANNER FAILED: ${error.message}');
      scanFlowState.value = ScanFlowState.error;
      lastError.value = error.message;
      return null;
    } catch (e, stackTrace) {
      debugPrint('MAIN SCANNER UNHANDLED EXCEPTION: $e\n$stackTrace');
      scanFlowState.value = ScanFlowState.error;
      lastError.value = 'Scan crash: $e';
      return null;
    }
  }

  Future<String> _recognizeAllPages(
    List<String> pagePaths,
    OcrScript script,
  ) async {
    final StringBuffer combined = StringBuffer();
    for (final String path in pagePaths) {
      try {
        final OcrResult result = await _ocr.recognizeText(
          imagePath: path,
          script: script,
        );
        if (combined.isNotEmpty) combined.writeln();
        combined.write(result.fullText);
      } on OcrUnavailableException {
        ocrUnavailable.value = true;
        break;
      } catch (e) {
        debugPrint('OCR ERROR on $path: $e');
      }
    }
    return combined.toString();
  }

  Future<bool> renameDocument(String id, String newTitle) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final ScanDocument updated = existing.copyWith(
      title: newTitle.trim(),
      updatedAt: DateTime.now(),
    );
    return _replaceAndSave(updated);
  }

  Future<bool> updateTags(String id, List<String> tags) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final ScanDocument updated = existing.copyWith(
      tags: tags,
      updatedAt: DateTime.now(),
    );
    return _replaceAndSave(updated);
  }

  Future<bool> toggleFavorite(String id) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final ScanDocument updated = existing.copyWith(
      isFavorite: !existing.isFavorite,
      updatedAt: DateTime.now(),
    );
    return _replaceAndSave(updated);
  }

  Future<bool> deleteDocument(String id) async {
    final bool success = await _storage.deleteDocument(id);
    if (success) {
      documents.value =
          documents.value.where((ScanDocument d) => d.id != id).toList();
      if (activeScan.value?.id == id) {
        activeScan.value = null;
      }
    } else {
      lastError.value = 'Could not delete the document.';
    }
    return success;
  }

  Future<List<ScanDocument>> search(String query) =>
      _storage.searchDocuments(query);

  Future<bool> importDocument(ScanDocument document) async {
    final bool success = await _storage.saveDocument(document);
    if (success) {
      final bool alreadyPresent =
          documents.value.any((ScanDocument d) => d.id == document.id);
      documents.value = alreadyPresent
          ? documents.value
              .map((ScanDocument d) => d.id == document.id ? document : d)
              .toList()
          : <ScanDocument>[document, ...documents.value];
    } else {
      lastError.value = 'Could not import "${document.title}".';
    }
    return success;
  }

  void setActiveScan(String? id) {
    activeScan.value = id == null ? null : _findById(id);
  }

  ScanDocument? _findById(String id) {
    for (final ScanDocument doc in documents.value) {
      if (doc.id == id) return doc;
    }
    return null;
  }

  Future<bool> _replaceAndSave(ScanDocument updated) async {
    final bool success = await _storage.saveDocument(updated);
    if (success) {
      documents.value = documents.value
          .map((ScanDocument d) => d.id == updated.id ? updated : d)
          .toList();
      if (activeScan.value?.id == updated.id) {
        activeScan.value = updated;
      }
    } else {
      lastError.value = 'Could not save changes to this document.';
    }
    return success;
  }

  String _generateId() {
    final int ts = DateTime.now().microsecondsSinceEpoch;
    final int rand = _random.nextInt(0x7fffffff);
    return '$ts-$rand';
  }

  String _defaultTitle(DateTime when) {
    final String date =
        '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    final String time =
        '${when.hour.toString().padLeft(2, '0')}.${when.minute.toString().padLeft(2, '0')}';
    return 'Scan $date $time';
  }

  void dispose() {
    documents.dispose();
    activeScan.dispose();
    isLoading.dispose();
    scanFlowState.dispose();
    lastError.dispose();
    ocrUnavailable.dispose();
  }
}
