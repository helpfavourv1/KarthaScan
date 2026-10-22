// lib/core/providers/scan_provider.dart
//
// ValueNotifier<List<ScanDocument>> + activeScan + CRUD operations
// (Section 16 file #21). Orchestrates DocScannerService (capture),
// OcrService (text extraction), and LocalStorageService (persistence)
// into the app's core "scan a document" flow.
//
// REACTIVITY: ValueNotifier + ListenableBuilder only, per the MANDATORY
// constraint in constants.dart.

import 'dart:async' show Completer, unawaited;
import 'dart:io' show File, Directory;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, listEquals;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scan_document.dart';
import '../models/signature_placement.dart';
import '../models/ocr_block.dart';
import '../models/page_transform.dart';
import '../services/doc_scanner_service.dart';
import '../services/local_storage.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import 'settings_provider.dart';
import '../undo/undo_manager.dart';
import '../utils/crop_convert.dart';
import '../utils/page_remap.dart';

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

  /// Overlay undo/redo stack (E2). Recorded by every layer mutation below.
  final UndoManager undoManager = UndoManager();

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
      final (String ocrText, Map<int, List<OcrBlock>> pageBlocks) =
          await _recognizeAllPages(scanResult.pageImagePaths);

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
        pageOcrBlocks: pageBlocks,
      );

      final bool saved = await _storage.saveDocument(document);
      if (!saved) {
        scanFlowState.value = ScanFlowState.error;
        lastError.value = 'Could not save the document.';
        return null;
      }
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

  Future<(String, Map<int, List<OcrBlock>>)> _recognizeAllPages(
    List<String> pagePaths,
  ) async {
    final StringBuffer combined = StringBuffer();
    final Map<int, List<OcrBlock>> pageBlocks = <int, List<OcrBlock>>{};
    for (int i = 0; i < pagePaths.length; i++) {
      final String path = pagePaths[i];
      try {
        // Latin first; Chinese, Japanese, Korean and Devanagari are tried when
        // Latin finds almost nothing.
        final OcrResult result = await _ocr.recognizeTextAuto(imagePath: path);
        if (combined.isNotEmpty) combined.writeln();
        combined.write(result.fullText);
        if (result.blocks.isNotEmpty) {
          pageBlocks[i] = result.blocks;
        }
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
    return (result, pageBlocks);
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

  /// Saves a new page list. Per-page edits (transforms, layers, OCR blocks)
  /// follow their pages: by default a page keeps its edits when its file path
  /// is unchanged; pass [sourceIndices] to say which old page each new page
  /// came from (null = a brand new page with no edits).
  Future<bool> updateDocumentPages(
    String id,
    List<String> newPagePaths, {
    List<int?>? sourceIndices,
    Map<int, int>? addTurns,
  }) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final List<int?> map =
        sourceIndices ?? matchPagesByPath(existing.pagePaths, newPagePaths);
    ScanDocument remapped = remapPageEdits(existing, map);
    // Quarter turns added in the Pages manager are kept as an edit on the
    // page, so the page keeps all its other edits.
    if (addTurns != null && addTurns.isNotEmpty) {
      final Map<int, PageTransform> transforms = Map<int, PageTransform>.from(remapped.pageTransforms);
      addTurns.forEach((int index, int turns) {
        if (index < 0 || index >= newPagePaths.length || turns % 4 == 0) return;
        final PageTransform t = transforms[index] ?? const PageTransform();
        transforms[index] = t.copyWith(rotationTurns: (t.rotationTurns + turns) % 4);
      });
      remapped = remapped.copyWith(pageTransforms: transforms);
    }
    // The cover follows the first page, as long as it was the first page.
    final bool coverWasFirstPage = existing.pagePaths.isNotEmpty && existing.thumbnailPath == existing.pagePaths.first;
    final ScanDocument updated = remapped.copyWith(
      pagePaths: newPagePaths,
      pageCount: newPagePaths.length,
      thumbnailPath: (coverWasFirstPage && newPagePaths.isNotEmpty) ? newPagePaths.first : null,
      updatedAt: DateTime.now(),
    );
    final bool pagesAddedOrRemoved =
        !(existing.pagePaths.toSet().length == newPagePaths.toSet().length &&
            existing.pagePaths.toSet().containsAll(newPagePaths));
    // Undo history refers to page numbers, so it ends when the pages change.
    if (!listEquals(existing.pagePaths, newPagePaths) || (addTurns != null && addTurns.isNotEmpty)) {
      undoManager.clear();
    }
    final bool saved = await _replaceAndSave(updated);
    // Search text must follow the pages: removed pages stop matching and
    // added pages start matching. Runs in the background.
    if (saved && pagesAddedOrRemoved) unawaited(refreshOcrText(id));
    return saved;
  }

  /// Reads the text of every page again and stores it as the document's
  /// search text. Does nothing when the reader finds no text at all.
  Future<void> refreshOcrText(String id) async {
    final ScanDocument? doc = _findById(id);
    if (doc == null) return;
    final List<String> paths = List<String>.from(doc.pagePaths);
    String text;
    try {
      text = await _ocr.recognizeTextForPages(paths);
    } catch (_) {
      return;
    }
    if (text.trim().isEmpty) return;
    final ScanDocument? current = _findById(id);
    if (current == null || !listEquals(current.pagePaths, paths)) return;
    await _replaceAndSave(current.copyWith(ocrText: text));
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
    // Same page, new picture: keep its crop, layers and other edits.
    return updateDocumentPages(
      id,
      newPaths,
      sourceIndices: List<int?>.generate(newPaths.length, (int i) => i),
    );
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
    final List<int> valid = <int>[
      for (final int idx in pageIndices)
        if (idx >= 0 && idx < existing.pagePaths.length) idx,
    ];
    if (valid.isEmpty) return null;
    final List<String> copiedPaths = <String>[];
    for (final int idx in valid) {
      copiedPaths.add(await _copyToManaged(existing.pagePaths[idx]));
    }
    // The new document keeps each page's crop, rotation, erasing, filter and
    // layers. Annotation pictures are copied so deleting one document never
    // removes the other's drawings.
    final ScanDocument remapped = remapPageEdits(existing, valid);
    final Map<String, String> annotateCopies = <String, String>{};
    final List<AnnotateLayer> annotateLayers = <AnnotateLayer>[];
    for (final AnnotateLayer layer in remapped.annotateLayers) {
      String path = annotateCopies[layer.bytesPath] ?? layer.bytesPath;
      if (!annotateCopies.containsKey(layer.bytesPath)) {
        try {
          final Directory appDir = await getApplicationDocumentsDirectory();
          final Directory dir = Directory(p.join(appDir.path, 'annotate_pages'));
          await dir.create(recursive: true);
          path = p.join(dir.path, 'ann_${DateTime.now().microsecondsSinceEpoch}_${annotateCopies.length}.png');
          await File(layer.bytesPath).copy(path);
        } catch (_) {
          path = layer.bytesPath;
        }
        annotateCopies[layer.bytesPath] = path;
      }
      annotateLayers.add(layer.copyWith(bytesPath: path));
    }
    final DateTime now = DateTime.now();
    final ScanDocument newDoc = remapped.copyWith(
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
      tags: const <String>[],
      isFavorite: false,
      annotateLayers: annotateLayers,
    );
    final bool success = await importDocument(newDoc);
    if (success) unawaited(refreshOcrText(newDoc.id));
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
    final ScanDocument? doomed = _findById(id);
    // Stop queued edits first: one saved after the delete would bring the
    // document back.
    _deleting.add(id);
    _pendingWrites.remove(id);
    for (final Completer<bool> w in _writeWaiters.remove(id) ?? <Completer<bool>>[]) {
      w.complete(false);
    }
    while (_writerRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final bool success = await _storage.deleteDocument(id);
    _deleting.remove(id);
    if (success) {
      documents.value =
          documents.value.where((ScanDocument d) => d.id != id).toList();
      if (activeScan.value?.id == id) {
        activeScan.value = null;
      }
      if (doomed != null) unawaited(_deleteOwnedFiles(doomed));
    } else {
      lastError.value = 'Could not delete the document.';
    }
    return success;
  }

  /// Removes the page, thumbnail and annotation files of a deleted document.
  /// Only files inside the app's own documents folder are touched, and a file
  /// that another document still uses is kept.
  Future<void> _deleteOwnedFiles(ScanDocument doomed) async {
    try {
      final String root = (await getApplicationDocumentsDirectory()).path;
      final Set<String> stillUsed = <String>{};
      for (final ScanDocument d in documents.value) {
        stillUsed
          ..addAll(d.pagePaths)
          ..add(d.thumbnailPath)
          ..addAll(d.annotateLayers.map((AnnotateLayer l) => l.bytesPath));
      }
      final Set<String> candidates = <String>{
        ...doomed.pagePaths,
        doomed.thumbnailPath,
        ...doomed.annotateLayers.map((AnnotateLayer l) => l.bytesPath),
      };
      for (final String path in candidates) {
        if (path.isEmpty || stillUsed.contains(path)) continue;
        if (!p.isWithin(root, path)) continue;
        final File file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (error) {
      debugPrint('Could not remove files of a deleted document: $error');
    }
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
      
      // Schedule export reminder in 48 hours
      await NotificationService.instance.scheduleExportReminder(
        documentId: document.id,
        documentTitle: document.title,
        scheduledTime: DateTime.now().add(const Duration(hours: 48)),
      );
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

  Future<bool> addSignatureInk(String id, String inkId, Uint8List bytes, String label, double aspect) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newInk = SignatureInk(id: inkId, bytes: bytes, label: label, aspect: aspect);
    final updated = existing.copyWith(signatureInks: [...existing.signatureInks, newInk], updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  Future<bool> removeSignatureInk(String id, String inkId) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newInks = existing.signatureInks.where((i) => i.id != inkId).toList();
    final newLayers = existing.signatureLayers.where((l) => l.inkId != inkId).toList();
    final updated = existing.copyWith(signatureInks: newInks, signatureLayers: newLayers, updatedAt: DateTime.now());
    return _replaceAndSave(updated);
  }

  /// Puts the overlay edits (signatures, annotations, watermarks, stamps and
  /// page edits) of [snapshot] onto the document as it is now. Undo used to put
  /// back a whole old copy of the document, which also undid a rename, new
  /// tags, or a deleted page made after the edit.
  ScanDocument _withOverlaysOf(ScanDocument now, ScanDocument snapshot) {
    return now.copyWith(
      signatureInks: snapshot.signatureInks,
      signatureLayers: snapshot.signatureLayers,
      annotateLayers: snapshot.annotateLayers,
      watermarkLayers: snapshot.watermarkLayers,
      stampLayers: snapshot.stampLayers,
      pageTransforms: snapshot.pageTransforms,
      updatedAt: DateTime.now(),
    );
  }

  void _recordOverlayUndo(ScanDocument before, ScanDocument after, String? coalesceKey) {
    final String id = before.id;
    undoManager.record(UndoCommand(
      coalesceKey: coalesceKey,
      undo: () async {
        final ScanDocument? now = _findById(id);
        if (now != null) await _replaceAndSave(_withOverlaysOf(now, before));
      },
      redo: () async {
        final ScanDocument? now = _findById(id);
        if (now != null) await _replaceAndSave(_withOverlaysOf(now, after));
      },
    ));
  }

  Future<bool> addSignatureLayer(String id, int pageIndex, SignaturePlacement placement, {String inkId = 'default'}) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayer = SignatureLayer(pageIndex: pageIndex, placement: placement, inkId: inkId);
    final updated = existing.copyWith(signatureLayers: [...existing.signatureLayers, newLayer], updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> updateSignatureLayer(String id, SignatureLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final exists = existing.signatureLayers
        .any((l) => l.pageIndex == layer.pageIndex && l.inkId == layer.inkId);
    final newLayers = exists
        ? existing.signatureLayers
            .map((l) => (l.pageIndex == layer.pageIndex && l.inkId == layer.inkId) ? layer : l)
            .toList()
        : [...existing.signatureLayers, layer];
    final updated = existing.copyWith(signatureLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, 'sigupd:${layer.inkId}:${layer.pageIndex}');
    return _replaceAndSave(updated);
  }

  Future<bool> removeSignatureLayer(String id, int pageIndex, {String? inkId}) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.signatureLayers
        .where((l) => !(l.pageIndex == pageIndex && (inkId == null || l.inkId == inkId)))
        .toList();
    final updated = existing.copyWith(signatureLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> clearSignatureLayers(String id) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(signatureLayers: const [], updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> setSignatureState(String id, List<SignatureInk> inks, List<SignatureLayer> layers) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(signatureInks: inks, signatureLayers: layers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, 'sig:$id');
    return _replaceAndSave(updated);
  }

  int _annSeq = 0;
  String newAnnotateId() => 'ann-${DateTime.now().microsecondsSinceEpoch}-${_annSeq++}';

  Future<bool> addAnnotateLayer(String id, AnnotateLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final AnnotateLayer added = layer.id.isEmpty ? layer.copyWith(id: newAnnotateId()) : layer;
    final newLayers = [...existing.annotateLayers.where((l) => l.id != added.id), added];
    final updated = existing.copyWith(annotateLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> updateAnnotateLayer(String id, AnnotateLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.annotateLayers
        .map((l) => l.id == layer.id ? layer : l)
        .toList();
    final updated = existing.copyWith(annotateLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, 'annupd:${layer.id}');
    return _replaceAndSave(updated);
  }

  Future<bool> removeAnnotateLayer(String id, String layerId) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.annotateLayers
        .where((l) => l.id != layerId)
        .toList();
    final updated = existing.copyWith(annotateLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> clearAnnotateLayers(String id) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(annotateLayers: const [], updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  int _wmSeq = 0;
  String newWatermarkId() => 'wm-${DateTime.now().microsecondsSinceEpoch}-${_wmSeq++}';

  Future<bool> addWatermarkLayer(String id, WatermarkLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    // Several watermarks may carry the same text, even on one page (for
    // example "CONFIDENTIAL" at the top and at the bottom); each has its own id.
    final WatermarkLayer added = layer.id.isEmpty ? layer.copyWith(id: newWatermarkId()) : layer;
    final List<WatermarkLayer> kept = existing.watermarkLayers.where((l) => l.id != added.id).toList();
    final updated = existing.copyWith(watermarkLayers: [...kept, added], updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> updateWatermarkLayer(String id, WatermarkLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.watermarkLayers.map((l) => l.id == layer.id ? layer : l).toList();
    final updated = existing.copyWith(watermarkLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, 'wmupd:${layer.id}');
    return _replaceAndSave(updated);
  }

  Future<bool> removeWatermarkLayer(String id, String layerId) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.watermarkLayers.where((l) => l.id != layerId).toList();
    final updated = existing.copyWith(watermarkLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  /// Swaps one watermark for an edited version in a single save and a single
  /// undo step. The edited version keeps the old one's id.
  Future<bool> replaceWatermarkLayer(String id, WatermarkLayer old, WatermarkLayer updatedLayer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final WatermarkLayer next = updatedLayer.copyWith(id: old.id);
    final updated = existing.copyWith(
      watermarkLayers: existing.watermarkLayers.map((l) => l.id == old.id ? next : l).toList(),
      updatedAt: DateTime.now(),
    );
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  /// Puts a copy of [layer] on every listed page in one save and one undo step.
  Future<bool> addWatermarkLayerToPages(String id, WatermarkLayer layer, Iterable<int> pages) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(
      watermarkLayers: [
        ...existing.watermarkLayers,
        for (final int p in pages.toSet()) layer.copyWith(id: newWatermarkId(), pageIndex: p),
      ],
      updatedAt: DateTime.now(),
    );
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  /// Removes every watermark on one page in one save and one undo step.
  Future<bool> clearWatermarksOnPage(String id, int pageIndex) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(
      watermarkLayers: existing.watermarkLayers.where((l) => l.pageIndex != pageIndex).toList(),
      updatedAt: DateTime.now(),
    );
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> clearWatermarkLayers(String id) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(watermarkLayers: const [], updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> addStampLayer(String id, StampLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(stampLayers: [...existing.stampLayers, layer], updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> updateStampLayer(String id, StampLayer layer) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.stampLayers.map((l) => l.id == layer.id ? layer : l).toList();
    final updated = existing.copyWith(stampLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, 'stupd:${layer.id}');
    return _replaceAndSave(updated);
  }

  Future<bool> removeStampLayer(String id, String layerId) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final newLayers = existing.stampLayers.where((l) => l.id != layerId).toList();
    final updated = existing.copyWith(stampLayers: newLayers, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }

  Future<bool> clearStampLayers(String id) async {
    final ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    final updated = existing.copyWith(stampLayers: const [], updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, null);
    return _replaceAndSave(updated);
  }


  /// Visible area of the whole photo, in pixels (read from the file header).
  Future<Rect?> _photoRect(String path) async {
    try {
      final Uint8List bytes = await File(path).readAsBytes();
      final img.DecodeInfo? info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      return Rect.fromLTWH(0, 0, info.width.toDouble(), info.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  bool _hasLayersOnPage(ScanDocument d, int pageIndex) =>
      d.signatureLayers.any((l) => l.pageIndex == pageIndex) ||
      d.annotateLayers.any((l) => l.pageIndex == pageIndex) ||
      d.watermarkLayers.any((l) => l.pageIndex == pageIndex) ||
      d.stampLayers.any((l) => l.pageIndex == pageIndex);

  Future<bool> updatePageTransform(String id, int pageIndex, PageTransform transform) async {
    ScanDocument? existing = _findById(id);
    if (existing == null) return false;
    // A changed crop moves what "50% across the page" means, so layers on the
    // page are converted to keep them over the same part of the photo.
    final Rect? oldCrop = existing.pageTransforms[pageIndex]?.cropRect;
    final Rect? newCrop = transform.cropRect;
    Rect? from;
    Rect? to;
    if (oldCrop != newCrop && _hasLayersOnPage(existing, pageIndex) && pageIndex < existing.pagePaths.length) {
      final Rect? whole = (oldCrop == null || newCrop == null) ? await _photoRect(existing.pagePaths[pageIndex]) : null;
      from = oldCrop ?? whole;
      to = newCrop ?? whole;
    }
    // Read the document again: it may have changed while the file was read.
    existing = _findById(id);
    if (existing == null) return false;
    ScanDocument base = existing;
    if (from != null && to != null) base = convertLayersForCrop(existing, pageIndex, from, to);
    final newTransforms = Map<int, PageTransform>.from(base.pageTransforms);
    if (transform.isEmpty) {
      newTransforms.remove(pageIndex);
    } else {
      newTransforms[pageIndex] = transform;
    }
    final updated = base.copyWith(pageTransforms: newTransforms, updatedAt: DateTime.now());
    _recordOverlayUndo(existing, updated, 'transform:$id:$pageIndex');
    return _replaceAndSave(updated);
  }

  Future<bool> revertPageTransform(String id, int pageIndex) async {
    return updatePageTransform(id, pageIndex, const PageTransform());
  }

  // Edits are applied in memory straight away and written to the database
  // one at a time, newest version of a document last. Before, the in-memory
  // copy only changed after the write finished, so two quick edits (copy to
  // all pages, dragging a layer) both started from the same old copy and the
  // later write silently dropped the earlier one.
  final Map<String, ScanDocument> _pendingWrites = <String, ScanDocument>{};
  final Map<String, List<Completer<bool>>> _writeWaiters = <String, List<Completer<bool>>>{};
  bool _writerRunning = false;
  final Set<String> _deleting = <String>{};

  Future<bool> _replaceAndSave(ScanDocument updated) {
    if (_deleting.contains(updated.id)) return Future<bool>.value(false);
    documents.value = documents.value
        .map((ScanDocument d) => d.id == updated.id ? updated : d)
        .toList();
    if (activeScan.value?.id == updated.id) {
      activeScan.value = updated;
    }
    final Completer<bool> done = Completer<bool>();
    _pendingWrites[updated.id] = updated;
    _writeWaiters.putIfAbsent(updated.id, () => <Completer<bool>>[]).add(done);
    unawaited(_runWriter());
    return done.future;
  }

  /// Writes that still failed after retrying, newest version per document.
  final Map<String, ScanDocument> _failedWrites = <String, ScanDocument>{};

  /// Number of documents with unsaved changes; the banner shows when above 0.
  final ValueNotifier<int> failedSaves = ValueNotifier<int>(0);

  /// Tries every failed write again. Returns true when all of them saved.
  Future<bool> retryFailedSaves() async {
    final List<ScanDocument> docs = _failedWrites.values.toList();
    _failedWrites.clear();
    failedSaves.value = 0;
    bool all = true;
    for (final ScanDocument d in docs) {
      final ScanDocument latest = _findById(d.id) ?? d;
      if (!await _replaceAndSave(latest)) all = false;
    }
    return all;
  }

  Future<void> _runWriter() async {
    if (_writerRunning) return;
    _writerRunning = true;
    try {
      while (_pendingWrites.isNotEmpty) {
        final String id = _pendingWrites.keys.first;
        final ScanDocument doc = _pendingWrites.remove(id)!;
        final List<Completer<bool>> waiters =
            _writeWaiters.remove(id) ?? <Completer<bool>>[];
        bool ok = false;
        // A document deleted while its write was waiting must not come back.
        if (_findById(id) != null) {
          // A busy or briefly locked database often succeeds a moment later.
          for (int attempt = 0; attempt < 3 && !ok; attempt++) {
            if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 250 * attempt * attempt));
            try {
              ok = await _storage.saveDocument(doc);
            } catch (_) {
              ok = false;
            }
          }
          if (ok) {
            if (_failedWrites.remove(id) != null) failedSaves.value = _failedWrites.length;
          } else {
            // Keep the newest version so the person can retry from the banner.
            if (!_pendingWrites.containsKey(id)) _failedWrites[id] = doc;
            failedSaves.value = _failedWrites.length;
            lastError.value = 'Could not save changes to this document.';
          }
        }
        for (final Completer<bool> w in waiters) {
          w.complete(ok);
        }
      }
    } finally {
      _writerRunning = false;
    }
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
    failedSaves.dispose();
    ocrUnavailable.dispose();
  }
}
