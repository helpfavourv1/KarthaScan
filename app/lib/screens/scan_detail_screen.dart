import 'dart:io';
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
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/annotation_overlay.dart';
import '../widgets/quick_action_pill.dart';
import '../widgets/scan_preview_card.dart';
import '../widgets/signature_canvas.dart';
import '../widgets/tag_chip.dart';
import '../widgets/overlay_placement_sheet.dart';

class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> with SingleTickerProviderStateMixin {
  late final ScanProvider _scanProvider;
  late final FolderProvider _folderProvider;
  final ShareService _shareService = ShareService();
  final OcrService _ocrService = OcrService();

  late TabController _tabController;
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
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

  Future<void> _addTag(ScanDocument document, AppLocalizations l10n) async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addTagTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.commonAdd)),
        ],
      ),
    );
    controller.dispose();
    final trimmed = tag?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final updated = {...document.tags, trimmed}.toList();
    await _scanProvider.updateTags(document.id, updated);
  }

  Future<void> _removeTag(ScanDocument document, String tag) async {
    final updated = document.tags.where((t) => t != tag).toList();
    await _scanProvider.updateTags(document.id, updated);
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
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final annotationKey = GlobalKey<AnnotationOverlayState>();
    final bytes = await showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AnnotationSheet(annotationKey: annotationKey),
    );

    if (bytes == null || !mounted) return;

    final placement = await showModalBottomSheet<(int, double, double, double, double)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => OverlayPlacementSheet(
        pagePaths: document.pagePaths,
        overlayBytes: bytes,
        title: 'Place Annotation',
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
    );
  }

  Future<void> _addSignature() async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final signatureKey = GlobalKey<SignatureCanvasState>();
    final signatureBytes = await showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SignatureSheet(signatureKey: signatureKey),
    );

    if (signatureBytes == null || !mounted) return;

    final placement = await showModalBottomSheet<(int, double, double, double, double)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => OverlayPlacementSheet(
        pagePaths: document.pagePaths,
        overlayBytes: signatureBytes,
        title: 'Place Signature',
      ),
    );

    if (placement != null && mounted) {
      await _compositeSignatureOnPage(
        placement.$1,
        signatureBytes,
        placement.$2,
        placement.$3,
        placement.$4,
        scale: placement.$5,
      );
    }
  }

  Future<void> _addWatermark() async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    final textController = TextEditingController(text: 'CONFIDENTIAL');
    double opacity = 0.15;
    double fontSize = 48;
    Color color = const Color(0xFF8E8E93);

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

    final watermarkText = textController.text;  // ✅ capture before dispose
    textController.dispose();
    if (confirmed != true || !mounted) return;

    final bytes = await _renderWatermarkPng(watermarkText, opacity, fontSize, color);
    if (bytes == null || !mounted) return;

    final placement = await showModalBottomSheet<(int, double, double, double, double)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => OverlayPlacementSheet(
        pagePaths: document.pagePaths,
        overlayBytes: bytes,
        title: 'Place Watermark',
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
    );
  }

  Future<Uint8List?> _renderWatermarkPng(String text, double opacity, double fontSize, Color color) async {
    if (text.isEmpty) return null;
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
    ))
      ..pushStyle(ui.TextStyle(color: color.withValues(alpha: opacity)))
      ..addText(text);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 600));
    final ui.Image image = await paragraph.toImage(600, (fontSize * 1.4).round());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  Future<void> _regionOcr() async {
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

      final result = await _ocrService.recognizeText(imagePath: tempPath, script: OcrScript.latin);

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
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Region OCR failed: $e')));
    }
  }

  Future<void> _compositeAndSavePage(int pageIndex, Uint8List overlayBytes, {double pctX = 0.5, double pctY = 0.5, double rotationDegrees = 0, double scale = 1.0}) async {
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

  Future<void> _compositeSignatureOnPage(int pageIndex, Uint8List signatureBytes, double pctX, double pctY, double rotation, {double scale = 1.0}) async {
    final document = _document;
    if (document == null) return;

    try {
      final originalBytes = await File(document.pagePaths[pageIndex]).readAsBytes();
      final finalBytes = await compute(_compositeSignatureIsolate, {
        'original': originalBytes,
        'signature': signatureBytes,
        'pctX': pctX,
        'pctY': pctY,
        'rotation': rotation,
        'scale': scale,
      });

      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'signed_pages'));
      await scansDir.create(recursive: true);
      final newPath = p.join(scansDir.path, 'sig_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.jpg');
      await File(newPath).writeAsBytes(finalBytes);

      final newPaths = List<String>.from(document.pagePaths);
      newPaths[pageIndex] = newPath;
      await _scanProvider.updateDocumentPages(document.id, newPaths);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signature saved')));
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
                  PopupMenuButton<String>(
                    icon: Icon(Icons.add_circle_outline, color: textSecondary),
                    tooltip: 'Add Layer',
                    onSelected: (action) {
                      switch (action) {
                        case 'annotate': _annotate(); break;
                        case 'sign': _addSignature(); break;
                        case 'watermark': _addWatermark(); break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'annotate', child: Row(children: [Icon(Icons.highlight_outlined, size: 20), SizedBox(width: 8), Text('Annotate')])),
                      const PopupMenuItem(value: 'sign', child: Row(children: [Icon(Icons.draw_outlined, size: 20), SizedBox(width: 8), Text('Sign')])),
                      const PopupMenuItem(value: 'watermark', child: Row(children: [Icon(Icons.text_fields, size: 20), SizedBox(width: 8), Text('Watermark')])),
                    ],
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
                    Tab(text: 'Text'),
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
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 24,
                          child: Center(
                            child: QuickActionPill(
                              onAnnotate: _annotate,
                              onSign: _addSignature,
                              onRegionOcr: _regionOcr,
                              onConvert: () => context.push('/export', extra: <String>[document.id]),
                              onCompress: () => context.push('/export', extra: <String, dynamic>{'ids': <String>[document.id], 'format': 'jpg'}),
                            ),
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
              // Tag Bar
              Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...document.tags.map((tag) => TagChip(label: tag, onDeleted: () => _removeTag(document, tag))),
                    TagChip(label: l10n.addTagChipLabel, onTap: () => _addTag(document, l10n)),
                  ],
                ),
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

class _AnnotationSheet extends StatelessWidget {
  const _AnnotationSheet({required this.annotationKey});
  final GlobalKey<AnnotationOverlayState> annotationKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Annotate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                  child: AnnotationOverlay(key: annotationKey),
                ),
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
                    onPressed: () async {
                      final bytes = await annotationKey.currentState?.exportPng();
                      if (context.mounted) Navigator.pop(context, bytes);
                    },
                    child: const Text('Save'),
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

class _RegionSelectSheet extends StatefulWidget {
  const _RegionSelectSheet({required this.imagePath});
  final String imagePath;

  @override
  State<_RegionSelectSheet> createState() => _RegionSelectSheetState();
}

class _RegionSelectSheetState extends State<_RegionSelectSheet> {
  Rect? _selectedRect;
  Offset? _startPos;
  img.Image? _originalImage;
  bool _loading = true;
  double _displayW = 0;
  double _displayH = 0;

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

                        return Center(
                          child: SizedBox(
                            width: displayW,
                            height: displayH,
                            child: GestureDetector(
                              onPanStart: (d) => setState(() => _startPos = d.localPosition),
                              onPanUpdate: (d) {
                                if (_startPos == null) return;
                                setState(() {
                                  final left = _startPos!.dx < d.localPosition.dx ? _startPos!.dx : d.localPosition.dx;
                                  final top = _startPos!.dy < d.localPosition.dy ? _startPos!.dy : d.localPosition.dy;
                                  final width = (d.localPosition.dx - _startPos!.dx).abs();
                                  final height = (d.localPosition.dy - _startPos!.dy).abs();
                                  _selectedRect = Rect.fromLTWH(left, top, width, height);
                                });
                              },
                              child: Stack(
                                children: [
                                  Image.file(File(widget.imagePath), fit: BoxFit.fill),
                                  if (_selectedRect != null)
                                    Positioned.fromRect(
                                      rect: _selectedRect!,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.blue, width: 2),
                                          color: Colors.blue.withValues(alpha: 0.2),
                                        ),
                                      ),
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
                    onPressed: _selectedRect == null || _displayW == 0 || _displayH == 0
                        ? null
                        : () {
                            final scaleX = _originalImage!.width / _displayW;
                            final scaleY = _originalImage!.height / _displayH;
                            final originalRect = Rect.fromLTRB(
                              _selectedRect!.left * scaleX,
                              _selectedRect!.top * scaleY,
                              _selectedRect!.right * scaleX,
                              _selectedRect!.bottom * scaleY,
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

class _SignaturePlacementSheet extends StatefulWidget {
  final List<String> pagePaths;
  final Uint8List signatureBytes;
  const _SignaturePlacementSheet({required this.pagePaths, required this.signatureBytes});

  @override
  State<_SignaturePlacementSheet> createState() => _SignaturePlacementSheetState();
}

class _SignaturePlacementSheetState extends State<_SignaturePlacementSheet> {
  int _currentPageIndex = 0;
  Offset _signatureOffset = Offset.zero;
  double _rotationDegrees = 0;
  final GlobalKey _stackKey = GlobalKey();
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final currentPagePath = widget.pagePaths[_currentPageIndex];
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Place Signature', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPageIndex > 0 ? () => setState(() => _currentPageIndex--) : null),
                      Text('Page ${_currentPageIndex + 1} / ${widget.pagePaths.length}'),
                      IconButton(icon: const Icon(Icons.chevron_right), onPressed: _currentPageIndex < widget.pagePaths.length - 1 ? () => setState(() => _currentPageIndex++) : null),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_initialized) {
                    _initialized = true;
                    _signatureOffset = Offset(constraints.maxWidth * 0.6, constraints.maxHeight * 0.7);
                  }
                  return Stack(
                    key: _stackKey,
                    children: [
                      Positioned.fill(child: Image.file(File(currentPagePath), fit: BoxFit.contain)),
                      Positioned(
                        left: _signatureOffset.dx,
                        top: _signatureOffset.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) => setState(() {
                            _signatureOffset += details.delta;
                            _signatureOffset = Offset(
                              _signatureOffset.dx.clamp(0.0, constraints.maxWidth - 100).toDouble(),
                              _signatureOffset.dy.clamp(0.0, constraints.maxHeight - 50).toDouble(),
                            );
                          }),
                          child: Transform.rotate(
                            angle: _rotationDegrees * 3.14159 / 180,
                            child: Opacity(opacity: 0.8, child: Image.memory(widget.signatureBytes, width: 100, height: 50, fit: BoxFit.contain)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Rotate'),
                  Expanded(
                    child: Slider(
                      value: _rotationDegrees,
                      min: -180,
                      max: 180,
                      onChanged: (value) => setState(() => _rotationDegrees = value),
                    ),
                  ),
                  Text('${_rotationDegrees.round()}°'),
                ],
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
                    onPressed: () {
                      final RenderBox? box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
                      final Size size = box?.size ?? const Size(1, 1);
                      final double pctX = (_signatureOffset.dx / size.width).clamp(0.0, 1.0).toDouble();
                      final double pctY = (_signatureOffset.dy / size.height).clamp(0.0, 1.0).toDouble();
                      Navigator.pop(context, (_currentPageIndex, pctX, pctY, _rotationDegrees));
                    },
                    child: const Text('Confirm'),
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
  overlay = img.copyResize(overlay, width: original.width, height: original.height);
  final scale = (args['scale'] as double?) ?? 1.0;
  final pctX = (args['pctX'] as double?) ?? 0.5;
  final pctY = (args['pctY'] as double?) ?? 0.5;
  final rotation = (args['rotation'] as double?) ?? 0.0;

  if (rotation != 0) overlay = img.copyRotate(overlay, angle: rotation);
  if (scale != 1.0) {
    final newW = (overlay.width * scale).round();
    final newH = (overlay.height * scale).round();
    overlay = img.copyResize(overlay, width: newW, height: newH);
  }

  final dstX = (pctX * original.width).round() - (overlay.width ~/ 2);
  final dstY = (pctY * original.height).round() - (overlay.height ~/ 2);

  final composite = img.compositeImage(original, overlay, dstX: dstX, dstY: dstY);
  return Uint8List.fromList(img.encodeJpg(composite, quality: 95));
}

Uint8List _compositeSignatureIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  var signature = img.decodePng(args['signature'] as Uint8List);
  if (original == null || signature == null) {
    return args['original'] as Uint8List;
  }
  final targetWidth = (original.width * 0.28).round();
  final targetHeight = (signature.height * targetWidth / signature.width).round();
  signature = img.copyResize(signature, width: targetWidth, height: targetHeight);

  final rotation = (args['rotation'] as double?) ?? 0.0;
  final scale = (args['scale'] as double?) ?? 1.0;
  if (rotation != 0) signature = img.copyRotate(signature, angle: rotation);
  if (scale != 1.0) {
    final newW = (signature.width * scale).round();
    final newH = (signature.height * scale).round();
    signature = img.copyResize(signature, width: newW, height: newH);
  }

  final pctX = (args['pctX'] as double?) ?? 0.5;
  final pctY = (args['pctY'] as double?) ?? 0.5;
  final dstX = (pctX * original.width).round() - (signature.width ~/ 2);
  final dstY = (pctY * original.height).round() - (signature.height ~/ 2);

  final composite = img.compositeImage(original, signature, dstX: dstX, dstY: dstY);
  return Uint8List.fromList(img.encodeJpg(composite, quality: 95));
}
