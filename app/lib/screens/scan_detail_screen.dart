import 'dart:io';
import '../core/models/signature_placement.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/ocr_service.dart';
import '../core/services/share_service.dart';
import '../core/services/local_storage.dart';
import '../core/providers/settings_provider.dart';
import '../widgets/color_picker_dialog.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/edit_tray.dart';
import '../widgets/annotate_sheet.dart';
import '../widgets/scan_preview_card.dart';
import '../widgets/signature_canvas.dart';
import '../widgets/overlay_placement_sheet.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/services/print_service.dart';
import '../widgets/eraser_overlay.dart';
import '../widgets/rotate_resize_sheet.dart';
import '../widgets/pages_manager_sheet.dart';
import '../widgets/filter_preview_sheet.dart';
import '../widgets/text_stamp_sheet.dart';
import '../widgets/edit_session_sheet.dart';
import '../core/models/edit_session.dart';
import '../core/services/filter_service.dart';
import '../core/services/export_service.dart' show FilterType;

class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> with SingleTickerProviderStateMixin {
  late final ScanProvider _scanProvider;
  Uint8List? _signatureBytes;
  late final FolderProvider _folderProvider;
  final ShareService _shareService = ShareService();
  final OcrService _ocrService = OcrService();
  final LocalStorageService _localStorage = LocalStorageService();

  late TabController _tabController;
  int _currentPageIndex = 0;
  bool _signatureMode = false;
  bool _annotateMode = false;
  Uint8List? _annotateBytes;

  @override
  void initState() {
    super.initState();
    _loadSignatureBytes();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _folderProvider = Provider.of<FolderProvider>(context, listen: false);
    _scanProvider.setActiveScan(widget.documentId);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  ScanDocument? get _document {
    for (final doc in _scanProvider.documents.value) {
      if (doc.id == widget.documentId) return doc;
    }
    return null;
  }

  // --- Existing Actions ---

  Future<void> _editTitle(ScanDocument document, AppLocalizations l10n) async {
    final controller = TextEditingController(text: document.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameDocumentTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.commonSave)),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _scanProvider.renameDocument(document.id, newTitle);
    }
  }



  Future<void> _moveToFolder(ScanDocument document, AppLocalizations l10n) async {
    final folders = _folderProvider.folders.value;
    final chosenFolderId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _FolderPickerSheet(folders: folders),
    );
    if (chosenFolderId == null) return;
    await _folderProvider.addDocumentToFolder(chosenFolderId, document.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.movedToFolderMessage)));
  }

  Future<void> _delete(ScanDocument document, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteScanTitle),
        content: Text(l10n.deleteScanMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _scanProvider.deleteDocument(document.id);
    await _folderProvider.removeDocumentFromAllFolders(document.id);
    if (!mounted) return;
    context.pop();
  }

  Future<void> _share(ScanDocument document) async {
    try {
      await _shareService.shareFiles(filePaths: document.pagePaths);
    } on ShareFailedException {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.genericErrorMessage)));
    }
  }

  Future<void> _export(ScanDocument document) async {
    if (!mounted) return;
    context.push('/export', extra: <String>[document.id]);
  }

  void _copyOcrToClipboard(String text, AppLocalizations l10n) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _shareOcrText(String text) async {
    try {
      await _shareService.shareText(text: text);
    } catch (_) {}
  }

  // --- R6 New Features ---

  Future<void> _annotate() async {
    await _addAnnotateToPage(_currentPageIndex);
  }


  Future<void> _loadSignatureBytes() async {
    final bytes = await _localStorage.loadSignaturePng();
    if (mounted && bytes != null) {
      setState(() => _signatureBytes = bytes);
    }
  }

  Future<void> _addSignature() async {
    await _addSignatureToPage(_currentPageIndex);
  }

  Future<void> _addSignatureToPage(int pageIndex) async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    Uint8List? signatureBytes;
    final saved = await _localStorage.loadSignaturePng();
    if (saved != null && mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Signature'),
          content: const Text('Use your saved signature or draw a new one?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'saved'), child: const Text('Use Saved')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'draw'), child: const Text('Draw New')),
          ],
        ),
      );
      if (choice == 'saved') signatureBytes = saved;
    }
    if (signatureBytes == null && mounted) {
      final signatureKey = GlobalKey<SignatureCanvasState>();
      signatureBytes = await showModalBottomSheet<Uint8List?>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _SignatureSheet(signatureKey: signatureKey),
      );
      if (signatureBytes != null) {
        await _localStorage.saveSignaturePng(signatureBytes);
      }
    }

    if (signatureBytes == null || !mounted) return;

    // Ensure overlay renders immediately
    setState(() {
      _signatureBytes = signatureBytes;
      _signatureMode = true;
    });

    await _scanProvider.addSignatureLayer(
      document.id,
      pageIndex,
      const SignaturePlacement(pctX: 0.5, pctY: 0.35),
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature added — drag to reposition')),
      );
    }
  }

  Future<void> _copySignatureToAllPages(SignatureLayer layer) async {
    final document = _document;
    if (document == null) return;
    for (int i = 0; i < document.pagePaths.length; i++) {
      await _scanProvider.updateSignatureLayer(document.id, SignatureLayer(pageIndex: i, placement: layer.placement, inkId: layer.inkId));
    }
  }

  Future<void> _clearSignaturePage(int pageIndex) async {
    final document = _document;
    if (document == null) return;
    await _scanProvider.removeSignatureLayer(document.id, pageIndex);
  }

  Future<void> _clearAllSignatureLayers() async {
    final document = _document;
    if (document == null) return;
    await _scanProvider.clearSignatureLayers(document.id);
  }

  Future<void> _annotateThisPage(int pageIndex) async {
    await _addAnnotateToPage(pageIndex);
  }

  Future<void> _addAnnotateToPage(int pageIndex) async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    // Use the already-drawn bytes if available, else open the sheet
    Uint8List? bytes = _annotateBytes;
    if (bytes == null) {
      bytes = await showModalBottomSheet<Uint8List?>(
        context: context,
        isScrollControlled: true,
        builder: (context) => const AnnotateSheet(),
      );
      if (bytes == null || !mounted) return;
    }

    // Save the PNG to a file
    final appDir = await getApplicationDocumentsDirectory();
    final annotateDir = Directory(p.join(appDir.path, 'annotate_pages'));
    await annotateDir.create(recursive: true);
    final filePath = p.join(annotateDir.path, 'ann_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.png');
    await File(filePath).writeAsBytes(bytes);

    setState(() {
      _annotateBytes = bytes;
      _annotateMode = true;
      _signatureMode = false;
    });

    await _scanProvider.addAnnotateLayer(
      document.id,
      AnnotateLayer(pageIndex: pageIndex, bytesPath: filePath, placement: const SignaturePlacement(pctX: 0.5, pctY: 0.35)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Annotate added — drag to reposition')),
      );
    }
  }

  Future<void> _copyAnnotateToAllPages(AnnotateLayer layer) async {
    final document = _document;
    if (document == null) return;
    for (int i = 0; i < document.pagePaths.length; i++) {
      await _scanProvider.addAnnotateLayer(
        document.id,
        AnnotateLayer(pageIndex: i, bytesPath: layer.bytesPath, placement: layer.placement),
      );
    }
  }

  Future<void> _clearAnnotatePage(int pageIndex) async {
    final document = _document;
    if (document == null) return;
    final matching = document.annotateLayers.where((l) => l.pageIndex == pageIndex).toList();
    if (matching.isNotEmpty) {
      await _scanProvider.removeAnnotateLayer(document.id, pageIndex, matching.first.bytesPath);
    }
  }

  Future<void> _clearAllAnnotateLayers() async {
    final document = _document;
    if (document == null) return;
    await _scanProvider.clearAnnotateLayers(document.id);
  }


  Future<void> _addWatermark() async {
    _signatureMode = false;
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final memo = settingsProvider.settings.value.lastWatermark;

    final textController = TextEditingController(text: (memo?['text'] as String?) ?? 'CONFIDENTIAL');
    double opacity = (memo?['opacity'] as num?)?.toDouble() ?? 0.15;
    double fontSize = (memo?['size'] as num?)?.toDouble() ?? 48;
    Color color = memo?['color'] != null ? Color(memo!['color'] as int) : const Color(0xFF8E8E93);
    String fontFamily = (memo?['fontFamily'] as String?) ?? 'sans-serif';
    bool bold = (memo?['bold'] as bool?) ?? true;
    TextAlign align = TextAlign.values.firstWhere((a) => a.name == ((memo?['align'] as String?) ?? 'center'), orElse: () => TextAlign.center);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Watermark'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textController,
                  decoration: const InputDecoration(labelText: 'Text'),
                ),
                const SizedBox(height: 16),
                Text('Opacity: ${opacity.toStringAsFixed(2)}'),
                Slider(
                  value: opacity,
                  min: 0.05,
                  max: 0.5,
                  onChanged: (v) => setDialogState(() => opacity = v),
                ),
                Text('Size: ${fontSize.round()}'),
                Slider(
                  value: fontSize,
                  min: 12,
                  max: 96,
                  onChanged: (v) => setDialogState(() => fontSize = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Color', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    for (final sw in [const Color(0xFF8E8E93), Colors.black, Colors.red, Colors.blue])
                      GestureDetector(
                        onTap: () => setDialogState(() => color = sw),
                        child: Container(
                          width: 24, height: 24, margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(color: sw, shape: BoxShape.circle, border: Border.all(color: color == sw ? Colors.blue : Colors.grey, width: color == sw ? 2 : 1)),
                        ),
                      ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDialog<Color>(context: ctx, builder: (c2) => ColorPickerDialog(initial: color));
                        if (picked != null) setDialogState(() => color = picked);
                      },
                      child: const Text('Custom'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: ['sans-serif', 'serif', 'monospace'].map((f) => ChoiceChip(
                    label: Text(f, style: const TextStyle(fontSize: 11)),
                    selected: fontFamily == f,
                    onSelected: (_) => setDialogState(() => fontFamily = f),
                  )).toList(),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(label: const Text('Bold'), selected: bold, onSelected: (_) => setDialogState(() => bold = !bold)),
                    ChoiceChip(label: const Text('L'), selected: align == TextAlign.left, onSelected: (_) => setDialogState(() => align = TextAlign.left)),
                    ChoiceChip(label: const Text('C'), selected: align == TextAlign.center, onSelected: (_) => setDialogState(() => align = TextAlign.center)),
                    ChoiceChip(label: const Text('R'), selected: align == TextAlign.right, onSelected: (_) => setDialogState(() => align = TextAlign.right)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    final watermarkText = textController.text;
    textController.dispose();
    if (confirmed != true || !mounted) return;

    await settingsProvider.setLastWatermark(<String, dynamic>{
      'text': watermarkText,
      'opacity': opacity,
      'size': fontSize,
      'color': color.toARGB32(),
      'fontFamily': fontFamily,
      'bold': bold,
      'align': align.name,
    });

    final bytes = await _renderWatermarkPng(
      watermarkText,
      opacity,
      fontSize,
      color,
      fontFamily: fontFamily,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      align: align,
    );
    if (bytes == null || !mounted) return;

    final placement = await showModalBottomSheet<(int, double, double, double, double, double)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => OverlayPlacementSheet(
        pagePaths: document.pagePaths,
        overlayBytes: bytes,
        title: 'Place Watermark',
        initialWidthFraction: 0.6,
      ),
    );
    if (placement == null || !mounted) return;
    await _compositeAndSavePage(
      placement.$1,
      bytes,
      pctX: placement.$2,
      pctY: placement.$3,
      rotationDegrees: placement.$4,
      scale: placement.$5,
      widthFraction: placement.$6,
    );
    
    await _compositeAndSavePage(
      placement.$1,
      bytes,
      pctX: placement.$2,
      pctY: placement.$3,
      rotationDegrees: placement.$4,
      scale: placement.$5,
    );
  }

  Future<Uint8List?> _renderWatermarkPng(
    String text,
    double opacity,
    double fontSize,
    Color color, {
    String fontFamily = 'sans-serif',
    FontWeight fontWeight = FontWeight.w700,
    TextAlign align = TextAlign.center,
  }) async {
    if (text.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFamily: fontFamily,
    ))
      ..pushStyle(ui.TextStyle(color: color.withValues(alpha: opacity)))
      ..addText(text);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 600));
    canvas.drawParagraph(paragraph, Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(600, (fontSize * 1.4).round());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  Future<void> _regionOcr() async {
    _signatureMode = false;
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final rect = await showModalBottomSheet<Rect?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RegionSelectSheet(imagePath: document.pagePaths[_currentPageIndex]),
    );

    if (rect == null || !mounted) return;

    try {
      final originalBytes = await File(document.pagePaths[_currentPageIndex]).readAsBytes();
      final originalImage = img.decodeImage(originalBytes);
      if (originalImage == null) return;

      // rect is already in original image coordinates (thanks to the fix)
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

      final script = await _pickOcrScript();
      if (script == null || !mounted) return;

      final result = await _ocrService.recognizeText(imagePath: tempPath, script: script);

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
                await _scanProvider.appendOcrText(document.id, result.fullText);
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



  Future<OcrScript?> _pickOcrScript() async {
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
              title: Text(
                labels[s] ?? s.name,
                style: TextStyle(color: isHard ? Colors.grey : null),
              ),
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

  Future<void> _applyFilterToPage() async {
    _signatureMode = false;
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;
    final chosen = await showModalBottomSheet<FilterType>(context: context, isScrollControlled: true, builder: (ctx) => FilterPreviewSheet(imagePath: document.pagePaths[_currentPageIndex]));
    if (chosen == null || chosen == FilterType.none || !mounted) return;
    try {
      final originalBytes = await File(document.pagePaths[_currentPageIndex]).readAsBytes();
      final filtered = await compute(_filterBakeIsolate, {'original': originalBytes, 'filter': chosen.index});
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'filtered_pages')); await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'flt_${DateTime.now().microsecondsSinceEpoch}_$_currentPageIndex.jpg');
      await File(newPath).writeAsBytes(filtered);
      final newPaths = List<String>.from(document.pagePaths); newPaths[_currentPageIndex] = newPath;
      await _scanProvider.updateDocumentPages(document.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Filter applied')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }

  Future<void> _cropCurrentPage() async {
    _signatureMode = false;
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;
    final rect = await showModalBottomSheet<Rect?>(context: context, isScrollControlled: true, builder: (context) => _RegionSelectSheet(imagePath: document.pagePaths[_currentPageIndex]));
    if (rect == null || !mounted) return;
    try {
      final originalBytes = await File(document.pagePaths[_currentPageIndex]).readAsBytes();
      final cropped = await compute(_cropIsolate, {'original': originalBytes, 'rect': rect});
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'cropped_pages')); await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'crp_${DateTime.now().microsecondsSinceEpoch}_$_currentPageIndex.jpg');
      await File(newPath).writeAsBytes(cropped);
      final newPaths = List<String>.from(document.pagePaths); newPaths[_currentPageIndex] = newPath;
      await _scanProvider.updateDocumentPages(document.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page cropped')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }

  Future<void> _addStamp(String kind) async {
    _signatureMode = false;
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;
    final stamp = await showModalBottomSheet<StampResult>(context: context, isScrollControlled: true, builder: (ctx) => TextStampSheet(kind: kind));
    if (stamp == null || !mounted) return;
    final layers = await showModalBottomSheet<List<EditLayer>>(context: context, isScrollControlled: true, builder: (ctx) => EditSessionSheet(imagePath: document.pagePaths[_currentPageIndex], initialBytes: stamp.bytes, initialLabel: stamp.label, initialWidthFraction: stamp.widthFraction, initialAspect: stamp.aspect));
    if (layers == null || layers.isEmpty || !mounted) return;
    try {
      final originalBytes = await File(document.pagePaths[_currentPageIndex]).readAsBytes();
      final baked = await compute(bakeSessionIsolate, {'original': originalBytes, 'layers': layers.map((l) => {'bytes': l.pngBytes, 'pctX': l.pctX, 'pctY': l.pctY, 'rotation': l.rotationDegrees, 'scale': l.scale, 'opacity': l.opacity, 'widthFraction': l.widthFraction}).toList()});
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'stamped_pages')); await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'stamp_${DateTime.now().microsecondsSinceEpoch}_$_currentPageIndex.jpg');
      await File(newPath).writeAsBytes(baked);
      final newPaths = List<String>.from(document.pagePaths); newPaths[_currentPageIndex] = newPath;
      await _scanProvider.updateDocumentPages(document.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Layers saved')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }



  Future<void> _erasePage() async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final strokes = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => EraserSheet(imagePath: document.pagePaths[_currentPageIndex]),
    );
    if (strokes == null || strokes.isEmpty || !mounted) return;

    try {
      final originalBytes = await File(document.pagePaths[_currentPageIndex]).readAsBytes();
      final erased = await compute(_eraseIsolate, {'original': originalBytes, 'strokes': strokes});

      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'erased_pages'));
      await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'ers_${DateTime.now().microsecondsSinceEpoch}_$_currentPageIndex.jpg');
      await File(newPath).writeAsBytes(erased);

      final newPaths = List<String>.from(document.pagePaths);
      newPaths[_currentPageIndex] = newPath;
      await _scanProvider.updateDocumentPages(document.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eraser applied')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _printDocument() async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    String mode = 'all';
    FilterType filter = FilterType.none;
    bool letter = false;
    final fromCtrl = TextEditingController(text: '1');
    final toCtrl = TextEditingController(text: '${document.pagePaths.length}');

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
      indices = [_currentPageIndex];
    } else if (mode == 'range') {
      final from = (int.tryParse(fromText) ?? 1).clamp(1, document.pagePaths.length);
      final to = (int.tryParse(toText) ?? document.pagePaths.length).clamp(from, document.pagePaths.length);
      indices = List<int>.generate(to - from + 1, (i) => from - 1 + i);
    }

    try {
      final bytes = await PrintService.buildPdfBytes(
        document.pagePaths,
        pageIndices: indices,
        filter: filter,
        pageFormat: letter ? PdfPageFormat.letter : PdfPageFormat.a4,
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: document.title,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _emailDocument() async {
    final document = _document;
    if (document == null) return;

    // Primary: share-to-email with pages attached (user picks email app from share sheet)
    try {
      await _shareService.shareFiles(
        filePaths: document.pagePaths,
        subject: document.title,
        text: document.ocrText.length > 500 ? '${document.ocrText.substring(0, 500)}...' : document.ocrText,
      );
      return; // Success via share sheet
    } catch (_) {
      // Fall through to mailto fallback
    }

    // Fallback: mailto: (no attachments, just opens composer)
    final subject = Uri.encodeComponent(document.title);
    final bodyText = document.ocrText.length > 500 ? '${document.ocrText.substring(0, 500)}...' : document.ocrText;
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

  Future<void> _rotatePage() async {
    _signatureMode = false;
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    bool applyAll = false;
    final turns = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => RotateResizeSheet(
        mode: RotateResizeMode.rotate,
        imagePath: document.pagePaths[_currentPageIndex],
        onApplyAll: (bool value) => applyAll = value,
      ),
    );
    if (turns == null || turns == 0 || !mounted) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'rotated_pages'));
      await scansDir.create(recursive: true);

      final List<String> newPaths = List<String>.from(document.pagePaths);
      final List<int> indicesToRotate = applyAll
          ? List<int>.generate(document.pagePaths.length, (i) => i)
          : [_currentPageIndex];

      for (final idx in indicesToRotate) {
        final originalBytes = await File(document.pagePaths[idx]).readAsBytes();
        final rotatedBytes = await compute(_rotateIsolate, {
          'original': originalBytes,
          'turns': turns,
        });
        final newPath = p.join(scansDir.path, 'rot_${DateTime.now().microsecondsSinceEpoch}_$idx.jpg');
        await File(newPath).writeAsBytes(rotatedBytes);
        newPaths[idx] = newPath;
      }

      await _scanProvider.updateDocumentPages(document.id, newPaths);

      if (mounted) {
        final msg = applyAll ? 'All pages rotated' : 'Page rotated';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _resizePage() async {
    _signatureMode = false;
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => RotateResizeSheet(
        mode: RotateResizeMode.resize,
        imagePath: document.pagePaths[_currentPageIndex],
      ),
    );
    if (result == null || !mounted) return;

    final (newW, newH) = result;
    try {
      final originalBytes = await File(document.pagePaths[_currentPageIndex]).readAsBytes();
      final resizedBytes = await compute(_resizeIsolate, {
        'original': originalBytes,
        'width': newW,
        'height': newH,
      });

      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'resized_pages'));
      await scansDir.create(recursive: true);
      final newPath = p.join(scansDir.path, 'res_${DateTime.now().microsecondsSinceEpoch}_$_currentPageIndex.jpg');
      await File(newPath).writeAsBytes(resizedBytes);

      final newPaths = List<String>.from(document.pagePaths);
      newPaths[_currentPageIndex] = newPath;
      await _scanProvider.updateDocumentPages(document.id, newPaths);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page resized')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _openPagesManager() async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final newPaths = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PagesManagerSheet(
        pagePaths: document.pagePaths,
        allDocuments: _scanProvider.documents.value,
        onExtract: (int index, String path) async {
          if (!mounted) return;
          Navigator.of(ctx).pop();
          final extractedDoc = await _scanProvider.extractToNewDocument(document.id, [index], 'Extracted Page');
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

    await _scanProvider.updateDocumentPages(document.id, newPaths);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pages updated')));
    }
  }

  Future<void> _compositeAndSavePage(int pageIndex, Uint8List overlayBytes, {double pctX = 0.5, double pctY = 0.5, double rotationDegrees = 0, double scale = 1.0, double widthFraction = 0.5}) async {
    final document = _document;
    if (document == null) return;

    setState(() { /* show progress if needed */ });
    try {
      final originalBytes = await File(document.pagePaths[pageIndex]).readAsBytes();
      final finalBytes = await compute(_compositeOverlayIsolate, {
        'original': originalBytes,
        'overlay': overlayBytes,
        'pctX': pctX,
        'pctY': pctY,
        'rotation': rotationDegrees,
        'scale': scale,
        'widthFraction': widthFraction,
      });

      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'annotated_pages'));
      await scansDir.create(recursive: true);
      final newPath = p.join(scansDir.path, 'ann_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.jpg');
      await File(newPath).writeAsBytes(finalBytes);

      final newPaths = List<String>.from(document.pagePaths);
      newPaths[pageIndex] = newPath;
      await _scanProvider.updateDocumentPages(document.id, newPaths);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annotation saved')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }



  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;

    return Scaffold(
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: _scanProvider.documents,
        builder: (context, _) {
          final document = _document;
          if (document == null) {
            return SafeArea(
              child: Column(
                children: [
                  AppBar(backgroundColor: bg, elevation: 0),
                  Expanded(child: Center(child: Text(l10n.scanUnavailable))),
                ],
              ),
            );
          }

          return Column(
            children: [
              AppBar(
                backgroundColor: bg,
                elevation: 0,
                title: GestureDetector(
                  onTap: () => _editTitle(document, l10n),
                  child: Text(
                    document.title,
                    style: TextStyle(color: textPrimary, fontSize: AppTypography.title2Size),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(document.isFavorite ? Icons.star : Icons.star_border, color: accent),
                    tooltip: 'Favorite',
                    onPressed: () => _scanProvider.toggleFavorite(document.id),
                  ),
                  IconButton(
                    icon: Icon(Icons.drive_file_move_outlined, color: textSecondary),
                    tooltip: l10n.moveToFolderTooltip,
                    onPressed: () => _moveToFolder(document, l10n),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: textSecondary),
                    tooltip: l10n.deleteTooltip,
                    onPressed: () => _delete(document, l10n),
                  ),
                ],
              ),
              // Tabs
              Container(
                color: bg,
                child: TabBar(
                  controller: _tabController,
                  labelColor: accent,
                  unselectedLabelColor: textSecondary,
                  indicatorColor: accent,
                  tabs: const [
                    Tab(text: 'Image'),
                    Tab(text: 'OCR Text'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Image Tab
                    Stack(
                      children: [
                        Positioned.fill(
                          child: ScanPreviewCard(
                            pagePaths: document.pagePaths,
                            onPageChanged: (index) => setState(() => _currentPageIndex = index),
                          
              signatureBytes: _signatureBytes,
              signatureLayers: _document?.signatureLayers ?? const [],
              signatureMode: _signatureMode,
              onSignatureLayerUpdate: (pageIndex, layer) {
                final doc = _document;
                if (doc != null) {
                  _scanProvider.updateSignatureLayer(doc.id, layer);
                }
              },
              onSignThisPage: (pageIndex) => _addSignatureToPage(pageIndex),
              onCopyToAllPages: (layer) => _copySignatureToAllPages(layer),
              onClearThisPage: (pageIndex) => _clearSignaturePage(pageIndex),
              onClearAllLayers: () => _clearAllSignatureLayers(),
              annotateLayers: _document?.annotateLayers ?? const [],
              annotateMode: _annotateMode,
              onAnnotateLayerUpdate: (pageIndex, layer) {
                final doc = _document;
                if (doc != null) {
                  _scanProvider.updateAnnotateLayer(doc.id, layer);
                }
              },
              onAnnotateThisPage: (pageIndex) => _annotateThisPage(pageIndex),
              onCopyAnnotateToAllPages: (layer) => _copyAnnotateToAllPages(layer),
              onClearAnnotatePage: (pageIndex) => _clearAnnotatePage(pageIndex),
              onClearAllAnnotateLayers: () => _clearAllAnnotateLayers(),
            ),
                        ),
                                              ],
                    ),
                    // Text Tab
                    Column(
                      children: [
                        // Action Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: border, width: 0.5)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              TextButton.icon(
                                onPressed: () => _copyOcrToClipboard(document.ocrText, l10n),
                                icon: const Icon(Icons.copy, size: 18),
                                label: const Text('Copy'),
                              ),
                              TextButton.icon(
                                onPressed: () => _shareOcrText(document.ocrText),
                                icon: const Icon(Icons.ios_share, size: 18),
                                label: const Text('Share'),
                              ),
                              TextButton.icon(
                                onPressed: () => _export(document),
                                icon: const Icon(Icons.file_download_outlined, size: 18),
                                label: const Text('Export'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(
                              document.ocrText.isEmpty ? l10n.noTextRecognized : document.ocrText,
                              style: TextStyle(color: textSecondary, fontSize: 15, height: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              EditTray(
                                                  onMarkup: _annotate,
                                                  onSign: _addSignature,
                                                  onWatermark: _addWatermark,
                                                  onOcr: _regionOcr,
                                                  onConvert: () => context.push('/export', extra: <String>[document.id]),
                                                  onCompress: () => context.push('/export', extra: <String, dynamic>{'ids': <String>[document.id], 'format': 'jpg'}),
                                                  onRotate: _rotatePage,
                                                  onResize: _resizePage,
                                                  onPages: _openPagesManager,
                                                  onFilter: _applyFilterToPage,
                                                  onCrop: _cropCurrentPage,
                                                  onText: () => _addStamp('text'),
                                                  onNote: () => _addStamp('note'),
                                                  onDate: () => _addStamp('date'),
                                                  onCheckbox: () => _addStamp('checkbox'),
                                                  onPrint: _printDocument,
                                                  onEmail: _emailDocument,
                                                  onErase: _erasePage,
                                                ),
                                                // Bottom Actions
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: bg, border: Border(top: BorderSide(color: border, width: 0.5))),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _share(document),
                          icon: const Icon(Icons.ios_share),
                          label: Text(l10n.shareTooltip),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _export(document),
                          icon: const Icon(Icons.file_download_outlined),
                          label: Text(l10n.exportTooltip),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: surface,
                            foregroundColor: textPrimary,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --- Helper Sheets ---



class _RegionSelectSheet extends StatefulWidget {
  const _RegionSelectSheet({required this.imagePath});
  final String imagePath;

  @override
  State<_RegionSelectSheet> createState() => _RegionSelectSheetState();
}

class _RegionSelectSheetState extends State<_RegionSelectSheet> {
  Rect? _displayRect;
  img.Image? _originalImage;
  bool _loading = true;
  double _displayW = 0;
  double _displayH = 0;

  String _activeHandle = 'none';
  Offset? _dragStart;

  static const double _hitSlop = 24.0;
  static const double _snapThreshold = 12.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      _originalImage = img.decodeImage(bytes);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_displayRect == null) return;
    final pos = details.localPosition;
    final r = _displayRect!;

    final distTL = (pos - Offset(r.left, r.top)).distance;
    final distTR = (pos - Offset(r.right, r.top)).distance;
    final distBL = (pos - Offset(r.left, r.bottom)).distance;
    final distBR = (pos - Offset(r.right, r.bottom)).distance;

    double minDist = distTL;
    String handle = 'tl';
    if (distTR < minDist) { minDist = distTR; handle = 'tr'; }
    if (distBL < minDist) { minDist = distBL; handle = 'bl'; }
    if (distBR < minDist) { minDist = distBR; handle = 'br'; }

    if (minDist < _hitSlop) {
      _activeHandle = handle;
    } else if (r.contains(pos)) {
      _activeHandle = 'body';
      _dragStart = pos;
    } else {
      _activeHandle = 'none';
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_displayRect == null || _activeHandle == 'none') return;
    final pos = details.localPosition;
    final r = _displayRect!;

    double newLeft = r.left;
    double newTop = r.top;
    double newRight = r.right;
    double newBottom = r.bottom;

    if (_activeHandle == 'tl') { newLeft = pos.dx; newTop = pos.dy; }
    else if (_activeHandle == 'tr') { newRight = pos.dx; newTop = pos.dy; }
    else if (_activeHandle == 'bl') { newLeft = pos.dx; newBottom = pos.dy; }
    else if (_activeHandle == 'br') { newRight = pos.dx; newBottom = pos.dy; }
    else if (_activeHandle == 'body' && _dragStart != null) {
      final delta = pos - _dragStart!;
      newLeft += delta.dx; newTop += delta.dy;
      newRight += delta.dx; newBottom += delta.dy;
      _dragStart = pos;
    }

    newLeft = newLeft.clamp(0.0, _displayW);
    newTop = newTop.clamp(0.0, _displayH);
    newRight = newRight.clamp(0.0, _displayW);
    newBottom = newBottom.clamp(0.0, _displayH);

    if (newRight - newLeft < 20) {
              if (_activeHandle == 'tl' || _activeHandle == 'bl') {
          newLeft = newRight - 20;
        } else {
          newRight = newLeft + 20;
        }
    }
    if (newBottom - newTop < 20) {
              if (_activeHandle == 'tl' || _activeHandle == 'tr') {
          newTop = newBottom - 20;
        } else {
          newBottom = newTop + 20;
        }
    }

    if (newLeft < _snapThreshold) {
      newLeft = 0;
    }
    if (newTop < _snapThreshold) {
      newTop = 0;
    }
    if (newRight > _displayW - _snapThreshold) {
      newRight = _displayW;
    }
    if (newBottom > _displayH - _snapThreshold) {
      newBottom = _displayH;
    }

    setState(() {
      _displayRect = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _activeHandle = 'none';
    _dragStart = null;
  }

  void _initRect() {
    if (_displayRect == null && _displayW > 0 && _displayH > 0) {
      _displayRect = Rect.fromCenter(
        center: Offset(_displayW / 2, _displayH / 2),
        width: _displayW * 0.5,
        height: _displayH * 0.5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Region', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: _loading || _originalImage == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final imgW = _originalImage!.width;
                        final imgH = _originalImage!.height;
                        final aspect = imgW / imgH;

                        double displayW = constraints.maxWidth;
                        double displayH = displayW / aspect;

                        if (displayH > constraints.maxHeight) {
                          displayH = constraints.maxHeight;
                          displayW = displayH * aspect;
                        }

                        _displayW = displayW;
                        _displayH = displayH;
                        _initRect();

                        return Center(
                          child: SizedBox(
                            width: displayW,
                            height: displayH,
                            child: GestureDetector(
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: Stack(
                                children: [
                                  Image.file(File(widget.imagePath), fit: BoxFit.fill),
                                  CustomPaint(
                                    size: Size(displayW, displayH),
                                    painter: _RegionOverlayPainter(rect: _displayRect),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _displayRect == null || _displayW == 0 || _displayH == 0
                        ? null
                        : () {
                            final scaleX = _originalImage!.width / _displayW;
                            final scaleY = _originalImage!.height / _displayH;
                            final originalRect = Rect.fromLTRB(
                              _displayRect!.left * scaleX,
                              _displayRect!.top * scaleY,
                              _displayRect!.right * scaleX,
                              _displayRect!.bottom * scaleY,
                            );
                            Navigator.pop(context, originalRect);
                          },
                    child: const Text('Extract'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionOverlayPainter extends CustomPainter {
  final Rect? rect;
  _RegionOverlayPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    if (rect == null) return;
    final r = rect!;
    
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(r, borderPaint);

    final handlePaint = Paint()..color = Colors.white;
    final handleBorder = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
      
    const radius = 10.0;
    final corners = [
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.left, r.bottom),
      Offset(r.right, r.bottom),
    ];
    
    for (final corner in corners) {
      canvas.drawCircle(corner, radius, handlePaint);
      canvas.drawCircle(corner, radius, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _RegionOverlayPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}

class _SignatureSheet extends StatelessWidget {
  const _SignatureSheet({required this.signatureKey});
  final GlobalKey<SignatureCanvasState> signatureKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sign', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(height: 200, child: SignatureCanvas(key: signatureKey)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => signatureKey.currentState?.clear(), child: const Text('Clear')),
                const SizedBox(width: 12),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    final bytes = await signatureKey.currentState?.exportPng();
                    if (context.mounted) Navigator.pop(context, bytes);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({required this.folders});
  final List<Folder> folders;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.moveToFolderTooltip, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No folders yet'),
              )
            else
              ...folders.map((folder) => ListTile(title: Text(folder.name), onTap: () => Navigator.of(context).pop(folder.id))),
          ],
        ),
      ),
    );
  }
}


// Top-level functions for compute() isolate
Uint8List _compositeOverlayIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  var overlay = img.decodePng(args['overlay'] as Uint8List);
  if (original == null || overlay == null) {
    return args['original'] as Uint8List;
  }
  final scale = (args['scale'] as double?) ?? 1.0;
  final pctX = (args['pctX'] as double?) ?? 0.5;
  final pctY = (args['pctY'] as double?) ?? 0.5;
  final rotation = (args['rotation'] as double?) ?? 0.0;
  final widthFraction = (args['widthFraction'] as double?) ?? 0.5;
  double tw = original.width * widthFraction * scale;
  if (tw < 8) tw = 8;
  final targetW = tw.round();
  final targetH = (targetW * overlay.height / overlay.width).round();
  overlay = img.copyResize(overlay, width: targetW, height: targetH);
  if (rotation != 0) overlay = img.copyRotate(overlay, angle: rotation);

  final dstX = (pctX * original.width).round() - (overlay.width ~/ 2);
  final dstY = (pctY * original.height).round() - (overlay.height ~/ 2);

  final composite = img.compositeImage(original, overlay, dstX: dstX, dstY: dstY);
  return Uint8List.fromList(img.encodeJpg(composite, quality: 95));
}




Uint8List _rotateIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final turns = args['turns'] as int;
  final rotated = img.copyRotate(original, angle: turns * 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
}

Uint8List _resizeIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final width = args['width'] as int;
  final height = args['height'] as int;
  final resized = img.copyResize(original, width: width, height: height);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 95));
}


Uint8List _filterBakeIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final filtered = FilterService.applyToImage(original, FilterType.values[args['filter'] as int]);
  return Uint8List.fromList(img.encodeJpg(filtered, quality: 95));
}

Uint8List _cropIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final rect = args['rect'] as Rect;
  final x = rect.left.toInt().clamp(0, original.width);
  final y = rect.top.toInt().clamp(0, original.height);
  final w = rect.width.toInt().clamp(0, original.width - x);
  final h = rect.height.toInt().clamp(0, original.height - y);
  if (w <= 0 || h <= 0) return args['original'] as Uint8List;
  final cropped = img.copyCrop(original, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}


Uint8List _eraseIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final strokes = args['strokes'] as List<dynamic>;
  for (final s in strokes) {
    final m = s as Map<dynamic, dynamic>;
    final pts = (m['points'] as List<dynamic>)
        .map((e) => (e as List<dynamic>).map((v) => (v as num).toDouble()).toList())
        .toList();
    final colorInt = m['color'] as int;
    final color = img.ColorRgba8((colorInt >> 16) & 0xFF, (colorInt >> 8) & 0xFF, colorInt & 0xFF, (colorInt >> 24) & 0xFF);
    final wf = (m['width'] as num).toDouble();
    final thickness = (wf * original.width).clamp(1.0, original.width / 2).round();
    for (int i = 0; i < pts.length - 1; i++) {
      final x1 = (pts[i][0] * original.width).round();
      final y1 = (pts[i][1] * original.height).round();
      final x2 = (pts[i + 1][0] * original.width).round();
      final y2 = (pts[i + 1][1] * original.height).round();
      img.drawLine(original, x1: x1, y1: y1, x2: x2, y2: y2, color: color, thickness: thickness, antialias: true);
    }
  }
  return Uint8List.fromList(img.encodeJpg(original, quality: 95));
}
