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
import '../core/models/page_transform.dart';
import '../core/models/signature_placement.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/export_service.dart' show ExportService, ExportFailedException, FilterType;
import '../core/services/local_storage.dart';
import '../core/services/ocr_service.dart';
import '../core/services/print_service.dart';
import '../core/services/share_service.dart';
import '../l10n/app_localizations.dart';
import '../core/utils/annotation_items.dart' show AnnotateResult;
import '../core/utils/page_range.dart';
import 'annotate_sheet.dart';
import 'eraser_overlay.dart';
import 'filter_preview_sheet.dart';
import 'ink_board.dart';
import 'pages_manager_sheet.dart';
import 'document_canvas.dart' show ViewCentre, PagePreviewJob, renderPagePreview;
import 'perspective_crop_sheet.dart';
import 'print_email_dialogs.dart';
import '../core/models/export_job.dart' show ExportFormat;
import '../core/utils/perspective.dart';
import 'rotate_resize_sheet.dart';
import 'seal_stamp_sheet.dart';
import 'text_stamp_sheet.dart';
import 'watermark_sheet.dart';

mixin DocumentTools<T extends StatefulWidget> on State<T> {
  AppLocalizations get l10n => AppLocalizations.of(context);

  // --- Host-supplied dependencies ---
  ScanProvider get scanProvider;
  InkController get inkController;

  /// Reloads the signature controller from the saved document. Needed after
  /// anything that moves or renumbers layers (crop, revert, page changes),
  /// otherwise the controller keeps the old positions, draws the signature
  /// in the wrong place and writes the old state back on its next change.
  void resyncInkFromDocument() {
    final d = document;
    if (d == null) return;
    inkController.restoreFrom(d);
    if (mounted) setState(() {});
  }
  LocalStorageService get localStorage;
  OcrService get ocrService;
  ShareService get shareService;
  ScanDocument? get document;

  /// Middle of the visible part of the page being looked at; new items land here.
  final ValueNotifier<ViewCentre?> viewCentre = ValueNotifier<ViewCentre?>(null);
  int get currentPageIndex;
  set editMode(TrayEditMode mode);
  void closeEditor();
  void onLayerAdded(TrayEditMode mode, String? identifier);

  // --- Unified signature entry: export-grade grammar everywhere ---
  Future<void> signFromTray() async {
    closeEditor();
    editMode = TrayEditMode.signature;
    if (!inkController.hasInks) {
      final inkId = await inkController.addInk(context, localStorage);
      if (inkId != null && mounted) {
        inkController.placeOnPage(currentPageIndex);
      }
    } else {
      inkController.placeOnPage(currentPageIndex);
    }
  }

  Future<void> shareDocument() async {
    final doc = document;
    if (doc == null) return;
    try {
      final paths = await ExportService().renderPagesForShare(doc);
      await shareService.shareFiles(filePaths: paths);
    } on ShareFailedException {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.genericErrorMessage)));
    } on ExportFailedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).genericErrorMessage)));
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
    final AnnotateResult? drawn = await showModalBottomSheet<AnnotateResult?>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (context) => AnnotateSheet(
        pagePath: pageIndex < doc.pagePaths.length ? doc.pagePaths[pageIndex] : null,
        pageTransform: doc.pageTransforms[pageIndex],
      ),
    );
    if (drawn == null || !mounted) return;
    final appDir = await getApplicationDocumentsDirectory();
    final annotateDir = Directory(p.join(appDir.path, 'annotate_pages'));
    await annotateDir.create(recursive: true);
    final filePath = p.join(annotateDir.path, 'ann_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.png');
    await File(filePath).writeAsBytes(drawn.bytes);
    final layer = AnnotateLayer(id: scanProvider.newAnnotateId(), pageIndex: pageIndex, bytesPath: filePath, placement: SignaturePlacement(pctX: drawn.pctX, pctY: drawn.pctY, scale: drawn.scale));
    await scanProvider.addAnnotateLayer(doc.id, layer);
    if (mounted) {
      editMode = TrayEditMode.annotate;
      onLayerAdded(TrayEditMode.annotate, layer.id);
    }
  }

  Future<void> copyAnnotateToAllPages(AnnotateLayer layer) async {
    final doc = document;
    if (doc == null) return;
    for (int i = 0; i < doc.pagePaths.length; i++) {
      // The source page already has it; adding it again would double it up.
      if (i == layer.pageIndex) continue;
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
      await scanProvider.removeAnnotateLayer(doc.id, layer.id);
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
    final ValueNotifier<String> pages = ValueNotifier<String>('current');
    final config = await showModalBottomSheet<WatermarkLayer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => WatermarkSheet(pages: pages, pageCount: doc.pagePaths.length),
    );
    if (config == null || !mounted) return;
    final int total = doc.pagePaths.length;
    final List<int> targets = pages.value == 'current'
        ? <int>[currentPageIndex]
        : (parsePageRange(pages.value, total) ?? <int>[currentPageIndex]);
    final List<String> ids = await scanProvider.addWatermarkLayersToPages(doc.id, config, targets);
    if (ids.isEmpty) return;
    final int here = targets.toSet().toList().indexWhere((int p) => p == currentPageIndex);
    final String shown = ids[here >= 0 ? here : 0];
    if (mounted) {
      editMode = TrayEditMode.watermark;
      onLayerAdded(TrayEditMode.watermark, shown);
    }
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
    await scanProvider.replaceWatermarkLayer(doc.id, existing, applyWatermarkEdit(existing, config));
  }

  Future<void> copyWatermarkToAllPages(WatermarkLayer layer) async {
    final doc = document;
    if (doc == null) return;
    await scanProvider.addWatermarkLayerToPages(
      doc.id,
      layer,
      <int>[for (int i = 0; i < doc.pagePaths.length; i++) if (i != layer.pageIndex) i],
    );
  }

  Future<void> clearWatermarkPage(int pageIndex) async {
    final doc = document;
    if (doc == null) return;
    await scanProvider.clearWatermarksOnPage(doc.id, pageIndex);
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
      config = await showModalBottomSheet<StampResult>(context: context, isScrollControlled: true, builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: const SealStampSheet(initial: null)));
    } else {
      config = await showModalBottomSheet<StampResult>(context: context, isScrollControlled: true, builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: TextStampSheet(kind: kind)));
    }
    if (config == null || !mounted) return;

    final layer = StampLayer(
      id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
      pageIndex: currentPageIndex,
      kind: kind,
      placement: () {
        final ViewCentre? vc = viewCentre.value;
        return (vc != null && vc.page == currentPageIndex) ? SignaturePlacement(pctX: vc.x, pctY: vc.y) : const SignaturePlacement(pctX: 0.5, pctY: 0.5);
      }(),
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
      sealImageBytes: config.sealImageBytesValue,
              sealTextColor: config.sealTextColorValue,
              sealTextScale: config.sealTextScaleValue,
              sealFont: config.sealFontValue,
              sealInk: config.sealInkValue,
    );
    await scanProvider.addStampLayer(doc.id, layer);
    if (mounted) {
      final mode = kind == 'text' ? TrayEditMode.text : (kind == 'note' ? TrayEditMode.note : (kind == 'date' ? TrayEditMode.date : (kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal)));
      editMode = mode;
      onLayerAdded(mode, layer.id);
    }
  }

  Future<void> editStamp(StampLayer existing) async {
    final doc = document;
    if (doc == null) return;
    final config = await showModalBottomSheet<StampResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: existing.kind == 'seal'
            ? SealStampSheet(initial: existing)
            : TextStampSheet(kind: existing.kind, initial: existing),
      ),
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
      sealImageBytes: config.sealImageBytesValue,
              sealTextColor: config.sealTextColorValue,
              clearSealTextColor: config.sealTextColorValue == null,
              sealTextScale: config.sealTextScaleValue,
              sealFont: config.sealFontValue,
              sealInk: config.sealInkValue,
    );
    await scanProvider.updateStampLayer(doc.id, updated);
  }

  Future<void> copyStampToAllPages(StampLayer layer) async {
    final doc = document;
    if (doc == null) return;
    for (int i = 0; i < doc.pagePaths.length; i++) {
      if (i == layer.pageIndex) continue;
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

    // Read from the page as it looks now (cropped, tilted, resized), without
    // filter or marks, so the box is drawn on what is seen.
    final PageTransform? pt = doc.pageTransforms[currentPageIndex];
    String sourcePath = doc.pagePaths[currentPageIndex];
    if (pt != null && !pt.isEmpty) {
      final Uint8List raw = await File(sourcePath).readAsBytes();
      final Uint8List? edited = await compute(renderPagePreview, PagePreviewJob(raw, pt.copyWith(filter: FilterType.none, brightness: 0, contrast: 0, rotationTurns: 0)));
      if (edited != null) {
        final Directory td = await getTemporaryDirectory();
        sourcePath = p.join(td.path, 'region_src_${DateTime.now().microsecondsSinceEpoch}.jpg');
        await File(sourcePath).writeAsBytes(edited);
      }
    }
    if (!mounted) return;
    final CropResult? region = await showModalBottomSheet<CropResult?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PerspectiveCropSheet(imagePath: sourcePath, title: l10n.commonExtract, autoDetect: false, showShapes: false),
    );
    if (region == null || !mounted) return;

    try {
      final originalBytes = await File(sourcePath).readAsBytes();
      final originalImage = img.decodeImage(originalBytes);
      if (originalImage == null) return;
      final img.Image? croppedImage = warpQuad(originalImage, region.quad);
      if (croppedImage == null || croppedImage.width <= 0 || croppedImage.height <= 0) return;
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
          title: Text(l10n.extractedTextTitle),
          content: SelectableText(result.fullText.isEmpty ? AppLocalizations.of(context).ocrNoTextFound : result.fullText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose)),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result.fullText));
                Navigator.pop(context);
              },
              child: Text(l10n.commonCopy),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await scanProvider.appendOcrText(doc.id, result.fullText);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.savedToDocumentText)));
                }
              },
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      );
    } on OcrUnavailableException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.regionOcrFailed}: $e')));
    }
  }

  Future<OcrScript?> pickOcrScript() async {
    final labels = <OcrScript, String>{
      OcrScript.latin: AppLocalizations.of(context).ocrScriptLatin,
      OcrScript.chinese: AppLocalizations.of(context).ocrScriptChinese,
      OcrScript.korean: AppLocalizations.of(context).ocrScriptKorean,
      OcrScript.japanese: AppLocalizations.of(context).ocrScriptJapanese,
      OcrScript.devanagari: AppLocalizations.of(context).ocrScriptDevanagari,
      OcrScript.arabic: AppLocalizations.of(context).ocrScriptArabic,
      OcrScript.russian: AppLocalizations.of(context).ocrScriptRussian,
      OcrScript.ukrainian: AppLocalizations.of(context).ocrScriptUkrainian,
      OcrScript.greek: AppLocalizations.of(context).ocrScriptGreek,
      OcrScript.hebrew: AppLocalizations.of(context).ocrScriptHebrew,
      OcrScript.thai: AppLocalizations.of(context).ocrScriptThai,
      OcrScript.bengali: AppLocalizations.of(context).ocrScriptBengali,
    };
    return showModalBottomSheet<OcrScript>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Column(
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
        )),
      ),
    );
  }

  // --- Page ops (shared isolates) ---
  Future<void> applyFilterToPage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;
    final chosen = await showModalBottomSheet<FilterChoice>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FilterPreviewSheet(imagePath: doc.pagePaths[currentPageIndex], transform: doc.pageTransforms[currentPageIndex], pageCount: doc.pagePaths.length),
    );
    if (chosen == null || !mounted) return;
    final List<int> indices = chosen.applyAll ? List<int>.generate(doc.pagePaths.length, (i) => i) : [currentPageIndex];
    final Map<int, PageTransform> changes = <int, PageTransform>{
      for (final int idx in indices)
        idx: (doc.pageTransforms[idx] ?? const PageTransform()).copyWith(
          filter: chosen.filter,
          filterIntensity: chosen.intensity,
          brightness: chosen.brightness,
          contrast: chosen.contrast,
        ),
    };
    // One edit for all chosen pages, so one undo reverses it.
    await scanProvider.updatePageTransforms(doc.id, changes);
    final bool removed = chosen.filter == FilterType.none && chosen.brightness == 0 && chosen.contrast == 0;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(removed ? l10n.filterRemoved : l10n.filterApplied)));
  }

  Future<void> cropCurrentPage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;
    final existing = doc.pageTransforms[currentPageIndex] ?? const PageTransform();
    final CropResult? res = await showModalBottomSheet<CropResult?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PerspectiveCropSheet(imagePath: doc.pagePaths[currentPageIndex], initialQuad: existing.cropQuad, initialAspect: existing.cropAspect),
    );
    if (res == null || !mounted) return;
    // A new crop changes the page's size, so an older resize no longer fits.
    final PageTransform updated;
    if (isUprightRect(res.quad) && res.aspect == null) {
      final Rect box = quadBounds(res.quad);
      updated = existing.copyWith(cropRect: box, clearCropQuad: true, clearResize: true);
    } else {
      updated = existing.copyWith(cropRect: quadBounds(res.quad), cropQuad: res.quad, cropAspect: res.aspect, clearResize: true);
    }
    await scanProvider.updatePageTransform(doc.id, currentPageIndex, updated);
    resyncInkFromDocument();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.pageCropped)));
  }

  Future<void> revertPage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;
    final transform = doc.pageTransforms[currentPageIndex];
    if (transform == null || transform.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.revertToOriginalTitle),
        content: Text(l10n.revertToOriginalMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.commonRevert, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await scanProvider.revertPageTransform(doc.id, currentPageIndex);
    resyncInkFromDocument();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.pageRevertedToOriginal)));
    }
  }

  Future<void> erasePage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final strokes = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (ctx) => EraserSheet(imagePath: doc.pagePaths[currentPageIndex]),
    );
    if (strokes == null || strokes.isEmpty || !mounted) return;

    final existing = doc.pageTransforms[currentPageIndex] ?? const PageTransform();
    final updated = existing.copyWith(eraserStrokes: [...existing.eraserStrokes, ...strokes]);
    await scanProvider.updatePageTransform(doc.id, currentPageIndex, updated);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.eraserApplied)));
  }

  Future<void> rotatePage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final RotateResult? res = await showModalBottomSheet<RotateResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => RotateResizeSheet(
        mode: RotateResizeMode.rotate,
        imagePath: doc.pagePaths[currentPageIndex],
        initialTurns: doc.pageTransforms[currentPageIndex]?.rotationTurns ?? 0,
        initialStraighten: doc.pageTransforms[currentPageIndex]?.straightenDegrees ?? 0,
      ),
    );
    if (res == null || !mounted) return;
    final double oldTilt = doc.pageTransforms[currentPageIndex]?.straightenDegrees ?? 0;
    if (res.turns == 0 && res.straighten == oldTilt) return;

    final List<int> indices = res.applyAll ? List<int>.generate(doc.pagePaths.length, (i) => i) : [currentPageIndex];
    final Map<int, PageTransform> changes = <int, PageTransform>{};
    for (final int idx in indices) {
      final PageTransform existing = doc.pageTransforms[idx] ?? const PageTransform();
      changes[idx] = existing.copyWith(
        rotationTurns: (existing.rotationTurns + res.turns) % 4,
        straightenDegrees: (idx == currentPageIndex || res.applyAll) ? res.straighten : existing.straightenDegrees,
      );
    }
    // One edit for every page, so a single undo reverses it all.
    await scanProvider.updatePageTransforms(doc.id, changes);

    if (mounted) {
      final msg = res.applyAll ? AppLocalizations.of(context).rotationAllPages : AppLocalizations.of(context).rotationPage;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> resizePage() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: RotateResizeSheet(
          mode: RotateResizeMode.resize,
          imagePath: doc.pagePaths[currentPageIndex],
          baseSize: doc.pageTransforms[currentPageIndex]?.croppedSize,
          transform: doc.pageTransforms[currentPageIndex],
        ),
      ),
    );
    if (result == null || !mounted) return;

    final (newW, newH) = result;
    final existing = doc.pageTransforms[currentPageIndex] ?? const PageTransform();
    final updated = existing.copyWith(resizeWidth: newW, resizeHeight: newH);
    await scanProvider.updatePageTransform(doc.id, currentPageIndex, updated);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.pageResized)));
  }

  Future<void> openPagesManager() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final result = await showModalBottomSheet<PagesManagerResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PagesManagerSheet(
        pagePaths: doc.pagePaths,
        allDocuments: scanProvider.documents.value,
        transformsByPath: <String, PageTransform>{
          for (int i = 0; i < doc.pagePaths.length; i++)
            if (doc.pageTransforms[i] != null) doc.pagePaths[i]: doc.pageTransforms[i]!,
        },
        onExtract: (int index, String path) async {
          if (!mounted) return;
          // `index` is the tile's position in the sheet, which may have been
          // reordered; the saved document is addressed by the page's file.
          final int savedIndex = doc.pagePaths.indexOf(path);
          if (savedIndex < 0) return;
          Navigator.of(ctx).pop();
          final extractedDoc = await scanProvider.extractToNewDocument(doc.id, [savedIndex], l10n.extractedPageDefaultTitle);
          if (extractedDoc != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${l10n.extractedAsNewDocument}: ${extractedDoc.title}')),
            );
            context.push('/scan/${extractedDoc.id}');
          }
        },
      ),
    );
    if (result == null || !mounted) return;

    // Quarter turns are given by position in the new order.
    final Map<int, int> addTurns = <int, int>{
      for (int i = 0; i < result.paths.length; i++)
        if ((result.turnsByPath[result.paths[i]] ?? 0) % 4 != 0) i: result.turnsByPath[result.paths[i]]! % 4,
    };
    await scanProvider.updateDocumentPages(doc.id, result.paths, addTurns: addTurns);
    resyncInkFromDocument();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.pagesUpdated)));
  }

  Future<void> printDocument() async {
    final doc = document;
    if (doc == null || doc.pagePaths.isEmpty) return;

    final PrintChoice? choice = await showDialog<PrintChoice>(
      context: context,
      builder: (ctx) => PrintOptionsDialog(pageCount: doc.pagePaths.length, currentIndex: currentPageIndex),
    );
    if (choice == null || !mounted) return;

    try {
      final bytes = await PrintService.buildPdfBytes(
        doc.pagePaths,
        pageIndices: choice.indices,
        filter: choice.filter,
        pageFormat: choice.paper.format,
        margin: choice.margin,
        fit: choice.fit,
        perSheet: choice.perSheet,
        pageBytes: (int i) => ExportService().renderPageForOutput(doc, i, filter: choice.filter),
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: doc.title,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.printFailed}: $e')));
    }
  }

  Future<void> emailDocument() async {
    final doc = document;
    if (doc == null) return;

    final EmailChoice? choice = await showDialog<EmailChoice>(
      context: context,
      builder: (ctx) => const EmailOptionsDialog(),
    );
    if (choice == null || !mounted) return;

    // One PDF with every page, not one attachment per page.
    final List<String> paths;
    bool missedLimit = false;
    try {
      final Directory tmp = await getTemporaryDirectory();
      final Directory out = await Directory(p.join(tmp.path, 'email_${DateTime.now().millisecondsSinceEpoch}')).create(recursive: true);
      final int? target = choice.targetMB == null ? null : choice.targetMB! * 1024 * 1024;
      paths = await ExportService().export(
        document: doc,
        format: ExportFormat.pdf,
        outputDirectoryPath: out.path,
        targetBytes: target,
      );
      if (target != null && paths.isNotEmpty && await File(paths.first).length() > target) missedLimit = true;
    } on ExportFailedException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.genericErrorMessage)));
      return;
    }

    final String message = choice.message;
    try {
      await shareService.shareFiles(
        filePaths: paths,
        subject: doc.title,
        text: message.isEmpty ? null : message,
      );
      if (missedLimit && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.emailLimitMissed(choice.targetMB!))));
      }
      return;
    } catch (_) {
      // Fall through to mailto fallback
    }

    final subject = Uri.encodeComponent(doc.title);
    final body = Uri.encodeComponent(message);
    final uri = Uri.parse('mailto:?subject=$subject&body=$body');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.emailAttachmentNotIncluded)));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noEmailAppFound)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.emailFailed}: $e')));
    }
  }
}
