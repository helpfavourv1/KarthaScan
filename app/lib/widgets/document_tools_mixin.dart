// lib/widgets/document_tools_mixin.dart
//
// Single shared implementation of every document tool action.
// ScanDetailScreen and FullScreenEditScreen both mix this in, so a
// feature change (e.g. non-destructive eraser) lands once and applies
// everywhere with identical identity.
import 'dart:io' show File, Directory;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/export_service.dart' show FilterType;
import '../core/services/local_storage.dart';
import '../core/services/ocr_service.dart';
import '../core/services/page_isolates.dart';
import '../core/services/print_service.dart';
import '../core/services/share_service.dart';
import '../l10n/app_localizations.dart';
import 'annotate_sheet.dart';
import 'eraser_overlay.dart';
import 'filter_preview_sheet.dart';
import 'ink_board.dart';
import 'pages_manager_sheet.dart';
import 'region_select_sheet.dart';
import 'rotate_resize_sheet.dart';
import 'seal_stamp_sheet.dart';
import 'text_stamp_sheet.dart';
import 'watermark_sheet.dart';

mixin DocumentTools<T extends StatefulWidget> on State<T> {
  // --- Host-supplied dependencies ---
  ScanProvider get scanProvider;
  InkController get inkController;
  LocalStorageService get localStorage;
  OcrService get ocrService;
  ShareService get shareService;
  ScanDocument? get document;
  int get currentPageIndex;
  set editMode(TrayEditMode mode);
  void closeEditor();

  // --- Unified signature entry: export-grade grammar everywhere ---
  Future<void> signFromTray() async {
    closeEditor();
    editMode = TrayEditMode.signature;
    if (!inkController.hasInks) {
      final inkId = await inkController.addInk(context, localStorage);
      if (inkId != null && mounted) {
        inkController.placeOnPage(currentPageIndex);
      }
    }
  }

  Future<void> shareDocument() async {
    final doc = document;
    if (doc == null) return;
    try {
      await shareService.shareFiles(filePaths: doc.pagePaths);
    } on ShareFailedException {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.genericErrorMessage)));
    }
  }

  Future<void> exportDocument() async {
    final doc = document;
    if (doc == null || !mounted) return;
    context.push('/export', extra: <String>[doc.id]);
  }

  // --- Annotate ---
  Future<void> annotateCurrentPage() async => addAnnotateToPage(currentPageIndex);

  Future<void> addAnnotateToPage(int pageIndex) async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;
    final bytes = await showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const AnnotateSheet(),
    );
    if (bytes == null || !mounted) return;
    final appDir = await getApplicationDocumentsDirectory();
    final annotateDir = Directory(p.join(appDir.path, 'annotate_pages'));
    await annotateDir.create(recursive: true);
    final filePath = p.join(annotateDir.path, 'ann_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.png');
    await File(filePath).writeAsBytes(bytes);
    await scanProvider.addAnnotateLayer(
      doc.id,
      AnnotateLayer(pageIndex: pageIndex, bytesPath: filePath, placement: const SignaturePlacement(pctX: 0.5, pctY: 0.35)),
    );
    if (mounted) editMode = TrayEditMode.annotate;
  }

  Future<void> copyAnnotateToAllPages(AnnotateLayer layer) async {
    final doc = document;
    if (doc == null) return;
    for (int i = 0; i < doc.pagePaths.length; i++) {
      await scanProvider.addAnnotateLayer(
        doc.id,
        AnnotateLayer(pageIndex: i, bytesPath: layer.bytesPath, placement: layer.placement),
      );
    }
  }

  Future<void> clearAnnotatePage(int pageIndex) async {
    final doc = document;
    if (doc == null) return;
    final matching = doc.annotateLayers.where((l) => l.pageIndex == pageIndex).toList();
    for (final layer in matching) {
      await scanProvider.removeAnnotateLayer(doc.id, pageIndex, layer.bytesPath);
    }
  }

  Future<void> clearAllAnnotateLayers() async {
    final doc = document;
    if (doc == null) return;
    await scanProvider.clearAnnotateLayers(doc.id);
  }

  // --- Watermark ---
  Future<void> addWatermarkNow() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;
    final config = await showModalBottomSheet<WatermarkLayer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const WatermarkSheet(),
    );
    if (config == null || !mounted) return;
    final layer = config.copyWith(
      pageIndex: currentPageIndex,
      placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5),
    );
    await scanProvider.addWatermarkLayer(doc.id, layer);
    if (mounted) editMode = TrayEditMode.watermark;
  }

  Future<void> editWatermark(WatermarkLayer existing) async {
    final doc = document;
    if (doc == null) return;
    final config = await showModalBottomSheet<WatermarkLayer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => WatermarkSheet(initialConfig: existing),
    );
    if (config == null || !mounted) return;
    final updated = config.copyWith(
      pageIndex: existing.pageIndex,
      placement: existing.placement,
    );
    await scanProvider.removeWatermarkLayer(doc.id, existing.pageIndex, existing.text);
    await scanProvider.addWatermarkLayer(doc.id, updated);
  }

  Future<void> copyWatermarkToAllPages(WatermarkLayer layer) async {
    final doc = document;
    if (doc == null) return;
    for (int i = 0; i < doc.pagePaths.length; i++) {
      await scanProvider.addWatermarkLayer(doc.id, layer.copyWith(pageIndex: i));
    }
  }

  Future<void> clearWatermarkPage(int pageIndex) async {
    final doc = document;
    if (doc == null) return;
    final matching = doc.watermarkLayers.where((l) => l.pageIndex == pageIndex).toList();
    for (final layer in matching) {
      await scanProvider.removeWatermarkLayer(doc.id, pageIndex, layer.text);
    }
  }

  Future<void> clearAllWatermarkLayers() async {
    final doc = document;
    if (doc == null) return;
    await scanProvider.clearWatermarkLayers(doc.id);
  }

  // --- Stamps (text / note / date / checkbox / seal) ---
  Future<void> addStampNow(String kind) async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    StampResult? config;
    if (kind == 'seal') {
      config = await showModalBottomSheet<StampResult>(context: context, isScrollControlled: true, builder: (ctx) => const SealStampSheet(initial: null));
    } else {
      config = await showModalBottomSheet<StampResult>(context: context, isScrollControlled: true, builder: (ctx) => TextStampSheet(kind: kind));
    }
    if (config == null || !mounted) return;

    final layer = StampLayer(
      id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
      pageIndex: currentPageIndex,
      kind: kind,
      placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5),
      opacity: 1.0,
      text: config.text,
      fontSize: config.fontSize,
      color: config.color,
      fontFamily: config.fontFamily,
      fontWeight: config.fontWeightValue,
      align: config.alignName,
      halo: config.halo,
      noteBgColor: config.noteBgColorValue,
      dateFormat: config.dateFormatValue,
      customDateMillis: config.customDateMillisValue,
      checked: config.checkedValue,
      checkShape: config.checkShapeValue,
      boxColor: config.boxColorValue,
      tickColor: config.tickColorValue,
      sealShape: config.sealShapeValue,
      sealSubtext: config.sealSubtextValue,
      sealCenter: config.sealCenterValue,
    );
    await scanProvider.addStampLayer(doc.id, layer);
    if (mounted) {
      editMode = kind == 'text' ? TrayEditMode.text : (kind == 'note' ? TrayEditMode.note : (kind == 'date' ? TrayEditMode.date : (kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal)));
    }
  }

  Future<void> editStamp(StampLayer existing) async {
    final doc = document;
    if (doc == null) return;
    final config = await showModalBottomSheet<StampResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => existing.kind == 'seal'
          ? SealStampSheet(initial: existing)
          : TextStampSheet(kind: existing.kind, initial: existing),
    );
    if (config == null || !mounted) return;
    final updated = existing.copyWith(
      text: config.text,
      fontSize: config.fontSize,
      color: config.color,
      fontFamily: config.fontFamily,
      fontWeight: config.fontWeightValue,
      align: config.alignName,
      halo: config.halo,
      noteBgColor: config.noteBgColorValue,
      dateFormat: config.dateFormatValue,
      customDateMillis: config.customDateMillisValue,
      checked: config.checkedValue,
      checkShape: config.checkShapeValue,
      boxColor: config.boxColorValue,
      tickColor: config.tickColorValue,
      sealShape: config.sealShapeValue,
      sealSubtext: config.sealSubtextValue,
      sealCenter: config.sealCenterValue,
    );
    await scanProvider.updateStampLayer(doc.id, updated);
  }

  Future<void> copyStampToAllPages(StampLayer layer) async {
    final doc = document;
    if (doc == null) return;
    for (int i = 0; i < doc.pagePaths.length; i++) {
      await scanProvider.addStampLayer(doc.id, layer.copyWith(id: 'stamp_${DateTime.now().microsecondsSinceEpoch}_$i', pageIndex: i));
    }
  }

  Future<void> clearStampPage(int pageIndex) async {
    final doc = document;
    if (doc == null) return;
    final matching = doc.stampLayers.where((l) => l.pageIndex == pageIndex).toList();
    for (final layer in matching) {
      await scanProvider.removeStampLayer(doc.id, layer.id);
    }
  }

  Future<void> clearAllStampLayers() async {
    final doc = document;
    if (doc == null) return;
    await scanProvider.clearStampLayers(doc.id);
  }

  // --- Region OCR ---
  Future<void> regionOcr() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final rect = await showModalBottomSheet<Rect?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RegionSelectSheet(imagePath: doc.pagePaths[currentPageIndex]),
    );
    if (rect == null || !mounted) return;

    try {
      final originalBytes = await File(doc.pagePaths[currentPageIndex]).readAsBytes();
      final originalImage = img.decodeImage(originalBytes);
      if (originalImage == null) return;

      final x = rect.left.toInt().clamp(0, originalImage.width);
      final y = rect.top.toInt().clamp(0, originalImage.height);
      final w = rect.width.toInt().clamp(0, originalImage.width - x);
      final h = rect.height.toInt().clamp(0, originalImage.height - y);
      if (w <= 0 || h <= 0) return;

      final croppedImage = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
      final croppedBytes = Uint8List.fromList(img.encodeJpg(croppedImage));

      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'region_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(tempPath).writeAsBytes(croppedBytes);

      final script = await pickOcrScript();
      if (script == null || !mounted) return;

      final result = await ocrService.recognizeText(imagePath: tempPath, script: script);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Extracted Text'),
          content: SelectableText(result.fullText.isEmpty ? 'No text found' : result.fullText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result.fullText));
                Navigator.pop(context);
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await scanProvider.appendOcrText(doc.id, result.fullText);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to document text')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } on OcrUnavailableException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Region OCR failed: $e')));
    }
  }

  Future<OcrScript?> pickOcrScript() async {
    final labels = <OcrScript, String>{
      OcrScript.latin: 'Latin (English, European)',
      OcrScript.chinese: 'Chinese',
      OcrScript.korean: 'Korean',
      OcrScript.japanese: 'Japanese',
    };
    return showModalBottomSheet<OcrScript>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: OcrScript.values.map((s) {
            final failure = OcrService.lastFailureFor(s);
            final bool isHard = failure?.$2 ?? false;
            return ListTile(
              title: Text(labels[s] ?? s.name, style: TextStyle(color: isHard ? Colors.grey : null)),
              enabled: !isHard,
              subtitle: failure != null && !isHard ? Text(failure.$1, style: const TextStyle(fontSize: 10, color: Colors.orange)) : null,
              onTap: () {
                OcrService.clearFailureFor(s);
                Navigator.pop(ctx, s);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- Page ops (shared isolates) ---
  Future<void> applyFilterToPage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;
    final chosen = await showModalBottomSheet<FilterType>(context: context, isScrollControlled: true, builder: (ctx) => FilterPreviewSheet(imagePath: doc.pagePaths[currentPageIndex]));
    if (chosen == null || chosen == FilterType.none || !mounted) return;
    try {
      final originalBytes = await File(doc.pagePaths[currentPageIndex]).readAsBytes();
      final filtered = await compute(filterBakeIsolate, {'original': originalBytes, 'filter': chosen.index});
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'filtered_pages'));
      await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'flt_${DateTime.now().microsecondsSinceEpoch}_$currentPageIndex.jpg');
      await File(newPath).writeAsBytes(filtered);
      final newPaths = List<String>.from(doc.pagePaths);
      newPaths[currentPageIndex] = newPath;
      await scanProvider.updateDocumentPages(doc.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Filter applied')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> cropCurrentPage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;
    final rect = await showModalBottomSheet<Rect?>(context: context, isScrollControlled: true, builder: (context) => RegionSelectSheet(imagePath: doc.pagePaths[currentPageIndex]));
    if (rect == null || !mounted) return;
    try {
      final originalBytes = await File(doc.pagePaths[currentPageIndex]).readAsBytes();
      final cropped = await compute(cropIsolate, {'original': originalBytes, 'rect': rect});
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'cropped_pages'));
      await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'crp_${DateTime.now().microsecondsSinceEpoch}_$currentPageIndex.jpg');
      await File(newPath).writeAsBytes(cropped);
      final newPaths = List<String>.from(doc.pagePaths);
      newPaths[currentPageIndex] = newPath;
      await scanProvider.updateDocumentPages(doc.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page cropped')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> erasePage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final strokes = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => EraserSheet(imagePath: doc.pagePaths[currentPageIndex]),
    );
    if (strokes == null || strokes.isEmpty || !mounted) return;

    try {
      final originalBytes = await File(doc.pagePaths[currentPageIndex]).readAsBytes();
      final erased = await compute(eraseIsolate, {'original': originalBytes, 'strokes': strokes});

      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'erased_pages'));
      await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'ers_${DateTime.now().microsecondsSinceEpoch}_$currentPageIndex.jpg');
      await File(newPath).writeAsBytes(erased);

      final newPaths = List<String>.from(doc.pagePaths);
      newPaths[currentPageIndex] = newPath;
      await scanProvider.updateDocumentPages(doc.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eraser applied')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> rotatePage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    bool applyAll = false;
    final turns = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => RotateResizeSheet(
        mode: RotateResizeMode.rotate,
        imagePath: doc.pagePaths[currentPageIndex],
        onApplyAll: (bool value) => applyAll = value,
      ),
    );
    if (turns == null || turns == 0 || !mounted) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'rotated_pages'));
      await scansDir.create(recursive: true);

      final List<String> newPaths = List<String>.from(doc.pagePaths);
      final List<int> indicesToRotate = applyAll
          ? List<int>.generate(doc.pagePaths.length, (i) => i)
          : [currentPageIndex];

      for (final idx in indicesToRotate) {
        final originalBytes = await File(doc.pagePaths[idx]).readAsBytes();
        final rotatedBytes = await compute(rotateIsolate, {'original': originalBytes, 'turns': turns});
        final newPath = p.join(scansDir.path, 'rot_${DateTime.now().microsecondsSinceEpoch}_$idx.jpg');
        await File(newPath).writeAsBytes(rotatedBytes);
        newPaths[idx] = newPath;
      }

      await scanProvider.updateDocumentPages(doc.id, newPaths);
      if (mounted) {
        final msg = applyAll ? 'All pages rotated' : 'Page rotated';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> resizePage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => RotateResizeSheet(
        mode: RotateResizeMode.resize,
        imagePath: doc.pagePaths[currentPageIndex],
      ),
    );
    if (result == null || !mounted) return;

    final (newW, newH) = result;
    try {
      final originalBytes = await File(doc.pagePaths[currentPageIndex]).readAsBytes();
      final resizedBytes = await compute(resizeIsolate, {'original': originalBytes, 'width': newW, 'height': newH});

      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'resized_pages'));
      await scansDir.create(recursive: true);
      final newPath = p.join(scansDir.path, 'res_${DateTime.now().microsecondsSinceEpoch}_$currentPageIndex.jpg');
      await File(newPath).writeAsBytes(resizedBytes);

      final newPaths = List<String>.from(doc.pagePaths);
      newPaths[currentPageIndex] = newPath;
      await scanProvider.updateDocumentPages(doc.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page resized')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> openPagesManager() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final newPaths = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PagesManagerSheet(
        pagePaths: doc.pagePaths,
        allDocuments: scanProvider.documents.value,
        onExtract: (int index, String path) async {
          if (!mounted) return;
          Navigator.of(ctx).pop();
          final extractedDoc = await scanProvider.extractToNewDocument(doc.id, [index], 'Extracted Page');
          if (extractedDoc != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Extracted as new document: ${extractedDoc.title}')),
            );
            context.push('/scan/${extractedDoc.id}');
          }
        },
      ),
    );
    if (newPaths == null || !mounted) return;

    await scanProvider.updateDocumentPages(doc.id, newPaths);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pages updated')));
  }

  Future<void> printDocument() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    String mode = 'all';
    FilterType filter = FilterType.none;
    bool letter = false;
    final fromCtrl = TextEditingController(text: '1');
    final toCtrl = TextEditingController(text: '${doc.pagePaths.length}');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Print Options'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: ['all', 'current', 'range'].map((m) => ChoiceChip(
                    label: Text(m == 'all' ? 'All pages' : m == 'current' ? 'Current' : 'Range'),
                    selected: mode == m,
                    onSelected: (_) => setDialogState(() => mode = m),
                  )).toList(),
                ),
                if (mode == 'range')
                  Row(
                    children: [
                      SizedBox(width: 60, child: TextField(controller: fromCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'From'))),
                      const SizedBox(width: 8),
                      SizedBox(width: 60, child: TextField(controller: toCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'To'))),
                    ],
                  ),
                const SizedBox(height: 8),
                DropdownButton<FilterType>(
                  value: filter,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setDialogState(() => filter = v!),
                  items: FilterType.values.map((f) => DropdownMenuItem(value: f, child: Text(f == FilterType.none ? 'No filter' : f.name))).toList(),
                ),
                SwitchListTile(
                  title: const Text('Letter size (US)'),
                  value: letter,
                  onChanged: (v) => setDialogState(() => letter = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Print')),
          ],
        ),
      ),
    );
    final fromText = fromCtrl.text;
    final toText = toCtrl.text;
    fromCtrl.dispose();
    toCtrl.dispose();
    if (confirmed != true || !mounted) return;

    List<int>? indices;
    if (mode == 'current') {
      indices = [currentPageIndex];
    } else if (mode == 'range') {
      final from = (int.tryParse(fromText) ?? 1).clamp(1, doc.pagePaths.length);
      final to = (int.tryParse(toText) ?? doc.pagePaths.length).clamp(from, doc.pagePaths.length);
      indices = List<int>.generate(to - from + 1, (i) => from - 1 + i);
    }

    try {
      final bytes = await PrintService.buildPdfBytes(
        doc.pagePaths,
        pageIndices: indices,
        filter: filter,
        pageFormat: letter ? PdfPageFormat.letter : PdfPageFormat.a4,
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: doc.title,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> emailDocument() async {
    final doc = document;
    if (doc == null) return;

    try {
      await shareService.shareFiles(
        filePaths: doc.pagePaths,
        subject: doc.title,
        text: doc.ocrText.length > 500 ? '${doc.ocrText.substring(0, 500)}...' : doc.ocrText,
      );
      return;
    } catch (_) {
      // Fall through to mailto fallback
    }

    final subject = Uri.encodeComponent(doc.title);
    final bodyText = doc.ocrText.length > 500 ? '${doc.ocrText.substring(0, 500)}...' : doc.ocrText;
    final body = Uri.encodeComponent(bodyText);
    final uri = Uri.parse('mailto:?subject=$subject&body=$body');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email app found')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Email failed: $e')));
    }
  }
}
