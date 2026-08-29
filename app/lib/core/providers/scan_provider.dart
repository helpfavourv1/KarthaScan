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
import 'dart:io' show File, Directory;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scan_document.dart';
import '../models/signature_placement.dart';
import '../services/doc_scanner_service.dart';
import '../services/local_storage.dart';
import '../services/ocr_service.dart';
import 'settings_provider.dart';

enum ScanFlowState { idle, scanning, recognizingText, saving, error, unsupported }

class ScanProvider {
  ScanProvider({
    required LocalStorageService storage,
    required DocScannerService docScanner,
    required OcrService ocr,
    required SettingsProvider settings,
  })  : _storage = storage,
        _docScanner = docScanner,
        _ocr = ocr,
        _settings = settings {
    unawaited(_loadAll());
  }

  final LocalStorageService _storage;
  final DocScannerService _docScanner;
  final OcrService _ocr;
  final SettingsProvider _settings;
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

  // OcrScript is now only latin; no need to expose it
  Future<ScanDocument?> captureNewDocument({
    String? title,
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
          await _recognizeAllPages(scanResult.pageImagePaths, OcrScript.latin);

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
    final String result = combined.toString();
    if (result.isNotEmpty && _settings.settings.value.autoCopyOcr) {
      Clipboard.setData(ClipboardData(text: result));
    }
    return result;
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

  Future<bool> updateDocumentPages(String id, List<String> newPagePaths) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final ScanDocument updated = existing.copyWith(
      pagePaths: newPagePaths,
      pageCount: newPagePaths.length,
      updatedAt: DateTime.now(),
    );
    return _replaceAndSave(updated);
  }

  /// Copies a source image into the app's managed pages directory.
  /// Prevents double-free if the source is already managed elsewhere.
  Future<String> _copyToManaged(String sourcePath) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory managedDir = Directory(p.join(appDir.path, 'managed_pages'));
    await managedDir.create(recursive: true);
    final String ext = p.extension(sourcePath);
    final String safeExt = ext.isEmpty ? '.jpg' : ext;
    final String outPath = p.join(
      managedDir.path,
      'managed_${DateTime.now().microsecondsSinceEpoch}$safeExt',
    );
    await File(sourcePath).copy(outPath);
    return outPath;
  }

  Future<bool> duplicatePageAt(String id, int pageIndex) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    if (pageIndex < 0 || pageIndex >= existing.pagePaths.length) return false;
    final String copied = await _copyToManaged(existing.pagePaths[pageIndex]);
    final List<String> newPaths = List<String>.from(existing.pagePaths);
    newPaths.insert(pageIndex + 1, copied);
    return updateDocumentPages(id, newPaths);
  }

  Future<bool> insertPageAt(String id, int pageIndex, String sourcePath) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final String copied = await _copyToManaged(sourcePath);
    final List<String> newPaths = List<String>.from(existing.pagePaths);
    final int insertAt = pageIndex.clamp(0, newPaths.length);
    newPaths.insert(insertAt, copied);
    return updateDocumentPages(id, newPaths);
  }

  Future<bool> replacePageAt(String id, int pageIndex, String sourcePath) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    if (pageIndex < 0 || pageIndex >= existing.pagePaths.length) return false;
    final String copied = await _copyToManaged(sourcePath);
    final List<String> newPaths = List<String>.from(existing.pagePaths);
    newPaths[pageIndex] = copied;
    return updateDocumentPages(id, newPaths);
  }

  /// Creates a new document from a subset of pages of an existing document.
  /// Pages are copied into the managed directory so the new document is
  /// independent of the source.
  Future<ScanDocument?> extractToNewDocument(
    String id,
    List<int> pageIndices,
    String? title,
  ) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return null;
    if (pageIndices.isEmpty) return null;
    final List<String> copiedPaths = <String>[];
    for (final int idx in pageIndices) {
      if (idx < 0 || idx >= existing.pagePaths.length) continue;
      copiedPaths.add(await _copyToManaged(existing.pagePaths[idx]));
    }
    if (copiedPaths.isEmpty) return null;
    final DateTime now = DateTime.now();
    final ScanDocument newDoc = ScanDocument(
      id: _generateId(),
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : _defaultTitle(now),
      pageCount: copiedPaths.length,
      pagePaths: copiedPaths,
      createdAt: now,
      updatedAt: now,
      ocrText: '',
      thumbnailPath: copiedPaths.first,
    );
    final bool success = await importDocument(newDoc);
    return success ? newDoc : null;
  }

  /// Appends region-OCR text to a document's combined [ScanDocument.ocrText],
  /// separated by a blank line so per-region extracts remain distinguishable.
  Future<bool> appendOcrText(String id, String text) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    final String combined = existing.ocrText.isEmpty
        ? trimmed
        : '${existing.ocrText}\n\n$trimmed';
    final ScanDocument updated = existing.copyWith(
      ocrText: combined,
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

  Future<bool> addSignatureLayer(String id, int pageIndex, SignaturePlacement placement) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    // Replace existing layer for this page, or add new
    final filtered = existing.signatureLayers.where((l) => l.pageIndex != pageIndex).toList();
    filtered.add(SignatureLayer(pageIndex: pageIndex, placement: placement));
    final updated = existing.copyWith(signatureLayers: filtered, updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> updateSignatureLayer(String id, int pageIndex, SignaturePlacement placement) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.signatureLayers
        .map((l) => l.pageIndex == pageIndex ? l.copyWith(placement: placement) : l)
        .toList();
    final updated = existing.copyWith(signatureLayers: newLayers, updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> removeSignatureLayer(String id, int pageIndex) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.signatureLayers.where((l) => l.pageIndex != pageIndex).toList();
    final updated = existing.copyWith(signatureLayers: newLayers, updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> clearSignatureLayers(String id) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(signatureLayers: const [], updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> addAnnotateLayer(String id, AnnotateLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = [...existing.annotateLayers, layer];
    final updated = existing.copyWith(annotateLayers: newLayers, updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> updateAnnotateLayer(String id, AnnotateLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.annotateLayers
        .map((l) => l.pageIndex == layer.pageIndex && l.bytesPath == layer.bytesPath ? layer : l)
        .toList();
    final updated = existing.copyWith(annotateLayers: newLayers, updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> removeAnnotateLayer(String id, int pageIndex, String bytesPath) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.annotateLayers
        .where((l) => !(l.pageIndex == pageIndex && l.bytesPath == bytesPath))
        .toList();
    final updated = existing.copyWith(annotateLayers: newLayers, updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> clearAnnotateLayers(String id) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(annotateLayers: const [], updatedAt: DateTime.now());
    return _replaceAndSave(updated);
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
