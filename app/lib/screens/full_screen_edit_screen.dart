import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/local_storage.dart';
import '../core/utils/constants.dart';
import '../widgets/document_canvas.dart';
import '../widgets/ink_board.dart';
import '../widgets/annotate_sheet.dart';
import '../widgets/watermark_sheet.dart';
import '../widgets/text_stamp_sheet.dart';
import '../widgets/seal_stamp_sheet.dart';

class FullScreenEditScreen extends StatefulWidget {
  const FullScreenEditScreen({super.key, required this.documentId});
  final String documentId;

  @override
  State<FullScreenEditScreen> createState() => _FullScreenEditScreenState();
}

class _FullScreenEditScreenState extends State<FullScreenEditScreen> {
  late final ScanProvider _scanProvider;
  late final InkController _inkController;
  late final PageController _pageController;
  final LocalStorageService _localStorage = LocalStorageService();

  int _currentPageIndex = 0;
  TrayEditMode _editMode = TrayEditMode.none;

  String? _selectedAnnotateBytesPath;
  String? _selectedWatermarkText;
  String? _selectedStampId;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _inkController = InkController(onChange: _persistSignature);
    _pageController = PageController();
    _scanProvider.setActiveScan(widget.documentId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final doc = _document;
      if (doc != null) _inkController.seed(doc);
    });
  }

  Future<void> _persistSignature() async {
    final doc = _document;
    if (doc == null) return;
    await _scanProvider.setSignatureState(doc.id, _inkController.inks.values.toList(), _inkController.layers);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ScanDocument? get _document {
    for (final doc in _scanProvider.documents.value) {
      if (doc.id == widget.documentId) return doc;
    }
    return null;
  }

  void _goToPage(int index) {
    final doc = _document;
    if (doc == null) return;
    final clamped = index.clamp(0, doc.pagePaths.length - 1);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _closeEditor() {
    if (_editMode == TrayEditMode.none) return;
    setState(() {
      _editMode = TrayEditMode.none;
      _inkController.setEditInk(null);
      _selectedAnnotateBytesPath = null;
      _selectedWatermarkText = null;
      _selectedStampId = null;
    });
  }

  Future<void> _addAnnotateToPage(int pageIndex) async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;
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
    await _scanProvider.addAnnotateLayer(
      document.id,
      AnnotateLayer(pageIndex: pageIndex, bytesPath: filePath, placement: const SignaturePlacement(pctX: 0.5, pctY: 0.35)),
    );
    if (mounted) setState(() => _editMode = TrayEditMode.annotate);
  }

  Future<void> _addWatermark() async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;
    final config = await showModalBottomSheet<WatermarkLayer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const WatermarkSheet(),
    );
    if (config == null || !mounted) return;
    final layer = config.copyWith(
      pageIndex: _currentPageIndex,
      placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5),
    );
    await _scanProvider.addWatermarkLayer(document.id, layer);
    if (mounted) setState(() => _editMode = TrayEditMode.watermark);
  }

  Future<void> _editWatermark(WatermarkLayer existing) async {
    final document = _document;
    if (document == null) return;
    final config = await showModalBottomSheet<WatermarkLayer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => WatermarkSheet(initialConfig: existing),
    );
    if (config == null || !mounted) return;
    final updated = config.copyWith(pageIndex: existing.pageIndex, placement: existing.placement);
    await _scanProvider.removeWatermarkLayer(document.id, existing.pageIndex, existing.text);
    await _scanProvider.addWatermarkLayer(document.id, updated);
  }

  Future<void> _addStamp(String kind) async {
    final document = _document;
    if (document == null || document.pagePaths.isEmpty) return;

    StampResult? config;
    if (kind == 'text' || kind == 'note' || kind == 'date' || kind == 'checkbox') {
      config = await showModalBottomSheet<StampResult>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => TextStampSheet(kind: kind),
      );
    } else if (kind == 'seal') {
      config = await showModalBottomSheet<StampResult>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => const SealStampSheet(initial: null),
      );
    }

    if (config == null || !mounted) return;

    final layer = StampLayer(
      id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
      pageIndex: _currentPageIndex,
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
    await _scanProvider.addStampLayer(document.id, layer);
    if (mounted) {
      setState(() => _editMode = kind == 'text' ? TrayEditMode.text : (kind == 'note' ? TrayEditMode.note : (kind == 'date' ? TrayEditMode.date : (kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal))));
    }
  }

  Future<void> _editStamp(StampLayer existing) async {
    final document = _document;
    if (document == null) return;
    final config = await showModalBottomSheet<StampResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => existing.kind == 'seal'
          ? SealStampSheet(initial: existing)
          : TextStampSheet(kind: existing.kind, initial: existing),
    );
    if (config == null || !mounted) return;
    final updated = existing.copyWith(
      text: config.text, fontSize: config.fontSize, color: config.color,
      fontFamily: config.fontFamily, fontWeight: config.fontWeightValue, align: config.alignName,
      halo: config.halo, noteBgColor: config.noteBgColorValue, dateFormat: config.dateFormatValue,
      customDateMillis: config.customDateMillisValue, checked: config.checkedValue,
      checkShape: config.checkShapeValue, boxColor: config.boxColorValue, tickColor: config.tickColorValue,
      sealShape: config.sealShapeValue, sealSubtext: config.sealSubtextValue, sealCenter: config.sealCenterValue,
    );
    await _scanProvider.updateStampLayer(document.id, updated);
  }

  Widget _buildBottomControls() {
    final document = _document;
    if (document == null) return const SizedBox.shrink();

    if (_inkController.editInkId != null) return _buildSignatureControls();
    if (_selectedAnnotateBytesPath != null) return _buildAnnotateControls();
    if (_selectedWatermarkText != null) return _buildWatermarkControls();
    if (_selectedStampId != null) {
      final kind = _editMode == TrayEditMode.note ? 'note' : (_editMode == TrayEditMode.date ? 'date' : (_editMode == TrayEditMode.checkbox ? 'checkbox' : (_editMode == TrayEditMode.seal ? 'seal' : 'text')));
      return _buildStampControls(kind);
    }

    return _buildAddButtons();
  }

  Widget _buildAddButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildAddButton(Icons.draw_outlined, 'Sign', () async {
            final inkId = await _inkController.addInk(context, _localStorage);
            if (inkId != null) {
              _inkController.placeOnPage(_currentPageIndex);
              setState(() => _editMode = TrayEditMode.signature);
            }
          }, accent, textPrimary),
          _buildAddButton(Icons.mode_edit_outline, 'Annotate', () => _addAnnotateToPage(_currentPageIndex), accent, textPrimary),
          _buildAddButton(Icons.text_fields, 'Watermark', () => _addWatermark(), accent, textPrimary),
          _buildAddButton(Icons.title, 'Text', () => _addStamp('text'), accent, textPrimary),
          _buildAddButton(Icons.approval_outlined, 'Seal', () => _addStamp('seal'), accent, textPrimary),
        ],
      ),
    );
  }

  Widget _buildAddButton(IconData icon, String label, VoidCallback onTap, Color accent, Color textPrimary) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSignatureControls() {
    final controller = _inkController;
    final editId = controller.editInkId;
    if (editId == null) return const SizedBox.shrink();
    final pl = controller.inkPlacements[editId]?[_currentPageIndex];
    if (pl == null) return const SizedBox.shrink();
    final pageCount = _document!.pagePaths.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: LayerType.signature,
        rotationDegrees: pl.rotationDegrees,
        scale: pl.scale,
        onRotateLeft: () => controller.updatePlacement(editId, _currentPageIndex, SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: (pl.rotationDegrees - 10).clamp(-180, 180), scale: pl.scale)),
        onRotateRight: () => controller.updatePlacement(editId, _currentPageIndex, SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: (pl.rotationDegrees + 10).clamp(-180, 180), scale: pl.scale)),
        onScaleDown: () => controller.updatePlacement(editId, _currentPageIndex, SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: pl.rotationDegrees, scale: (pl.scale - 0.1).clamp(0.1, 5.0))),
        onScaleUp: () => controller.updatePlacement(editId, _currentPageIndex, SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: pl.rotationDegrees, scale: (pl.scale + 0.1).clamp(0.1, 5.0))),
        onCopyAll: () => controller.copyToAllPages(editId, _currentPageIndex, pageCount),
        onClearThis: () => controller.removePlacement(editId, _currentPageIndex),
        onRemove: () => controller.removeInk(editId),
        onClearAll: () => controller.clearAll(),
      ),
    );
  }

  Widget _buildAnnotateControls() {
    final document = _document;
    if (document == null) return const SizedBox.shrink();
    final pageLayers = document.annotateLayers.where((l) => l.pageIndex == _currentPageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.bytesPath == _selectedAnnotateBytesPath, orElse: () => pageLayers.first);

    void upd(SignaturePlacement pl) {
      _scanProvider.updateAnnotateLayer(document.id, AnnotateLayer(pageIndex: layer.pageIndex, bytesPath: layer.bytesPath, placement: pl));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: LayerType.annotate,
        rotationDegrees: layer.placement.rotationDegrees,
        scale: layer.placement.scale,
        onRotateLeft: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale)),
        onRotateRight: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale)),
        onScaleDown: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0))),
        onScaleUp: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0))),
        onCopyAll: () {
          for (int i = 0; i < document.pagePaths.length; i++) {
            _scanProvider.addAnnotateLayer(document.id, AnnotateLayer(pageIndex: i, bytesPath: layer.bytesPath, placement: layer.placement));
          }
        },
        onClearThis: () => _scanProvider.removeAnnotateLayer(document.id, _currentPageIndex, layer.bytesPath),
        onRemove: () => _scanProvider.removeAnnotateLayer(document.id, _currentPageIndex, layer.bytesPath),
        onClearAll: () => _scanProvider.clearAnnotateLayers(document.id),
      ),
    );
  }

  Widget _buildWatermarkControls() {
    final document = _document;
    if (document == null) return const SizedBox.shrink();
    final pageLayers = document.watermarkLayers.where((l) => l.pageIndex == _currentPageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.text == _selectedWatermarkText, orElse: () => pageLayers.first);

    void upd(WatermarkLayer newLayer) {
      _scanProvider.updateWatermarkLayer(document.id, newLayer);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: LayerType.watermark,
        rotationDegrees: layer.placement.rotationDegrees,
        scale: layer.placement.scale,
        opacity: layer.opacity,
        fontSize: layer.fontSize,
        onRotateLeft: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onOpacityDown: () => upd(layer.copyWith(opacity: (layer.opacity - 0.05).clamp(0.05, 1.0))),
        onOpacityUp: () => upd(layer.copyWith(opacity: (layer.opacity + 0.05).clamp(0.05, 1.0))),
        onFontSizeDown: () => upd(layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144))),
        onFontSizeUp: () => upd(layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144))),
        onTools: () async => await _editWatermark(layer),
        onCopyAll: () {
          for (int i = 0; i < document.pagePaths.length; i++) {
            _scanProvider.addWatermarkLayer(document.id, layer.copyWith(pageIndex: i));
          }
        },
        onClearThis: () => _scanProvider.removeWatermarkLayer(document.id, _currentPageIndex, layer.text),
        onRemove: () => _scanProvider.removeWatermarkLayer(document.id, _currentPageIndex, layer.text),
        onClearAll: () => _scanProvider.clearWatermarkLayers(document.id),
      ),
    );
  }

  Widget _buildStampControls(String kind) {
    final document = _document;
    if (document == null) return const SizedBox.shrink();
    final pageLayers = document.stampLayers.where((l) => l.pageIndex == _currentPageIndex && l.kind == kind).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == _selectedStampId, orElse: () => pageLayers.first);

    void upd(StampLayer newLayer) {
      _scanProvider.updateStampLayer(document.id, newLayer);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: kind == 'text' ? LayerType.text : (kind == 'note' ? LayerType.note : (kind == 'date' ? LayerType.date : (kind == 'checkbox' ? LayerType.checkbox : LayerType.seal))),
        rotationDegrees: layer.placement.rotationDegrees,
        scale: layer.placement.scale,
        opacity: layer.opacity,
        fontSize: kind == 'checkbox' ? null : layer.fontSize,
        onRotateLeft: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => upd(layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onOpacityDown: () => upd(layer.copyWith(opacity: (layer.opacity - 0.05).clamp(0.05, 1.0))),
        onOpacityUp: () => upd(layer.copyWith(opacity: (layer.opacity + 0.05).clamp(0.05, 1.0))),
        onFontSizeDown: () => upd(layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144))),
        onFontSizeUp: () => upd(layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144))),
        onTools: () async => await _editStamp(layer),
        onCopyAll: () {
          for (int i = 0; i < document.pagePaths.length; i++) {
            _scanProvider.addStampLayer(document.id, layer.copyWith(id: 'stamp_${DateTime.now().microsecondsSinceEpoch}_$i', pageIndex: i));
          }
        },
        onClearThis: () => _scanProvider.removeStampLayer(document.id, layer.id),
        onRemove: () => _scanProvider.removeStampLayer(document.id, layer.id),
        onClearAll: () => _scanProvider.clearStampLayers(document.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Scaffold(
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: _scanProvider.documents,
        builder: (context, _) {
          final document = _document;
          if (document == null) {
            return SafeArea(child: Center(child: Text('Document not found', style: TextStyle(color: textPrimary))));
          }

          return Stack(
            children: [
              // Full Screen Canvas
              Positioned.fill(
                child: DocumentCanvas(
                  pagePaths: document.pagePaths,
                  inkController: _inkController,
                  annotateLayers: document.annotateLayers,
                  watermarkLayers: document.watermarkLayers,
                  stampLayers: document.stampLayers,
                  selectedAnnotateBytesPath: _selectedAnnotateBytesPath,
                  selectedWatermarkText: _selectedWatermarkText,
                  selectedStampId: _selectedStampId,
                  onAnnotateSelect: (layer) => setState(() {
                    _selectedAnnotateBytesPath = layer.bytesPath;
                    _editMode = TrayEditMode.annotate;
                  }),
                  onAnnotateUpdate: (pageIndex, newLayer) => _scanProvider.updateAnnotateLayer(document.id, newLayer),
                  onSignatureSelect: () => setState(() => _editMode = TrayEditMode.signature),
                  onWatermarkSelect: () => setState(() => _editMode = TrayEditMode.watermark),
                  onWatermarkSelected: (layer) => setState(() => _selectedWatermarkText = layer.text),
                  onWatermarkLayerUpdate: (pageIndex, layer) => _scanProvider.updateWatermarkLayer(document.id, layer),
                  onStampSelect: () {
                    final kind = _editMode == TrayEditMode.note ? 'note' : (_editMode == TrayEditMode.date ? 'date' : (_editMode == TrayEditMode.checkbox ? 'checkbox' : (_editMode == TrayEditMode.seal ? 'seal' : 'text')));
                    setState(() => _editMode = kind == 'text' ? TrayEditMode.text : (kind == 'note' ? TrayEditMode.note : (kind == 'date' ? TrayEditMode.date : (kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal))));
                  },
                  onStampSelected: (layer) => setState(() => _selectedStampId = layer.id),
                  onStampLayerUpdate: (pageIndex, layer) => _scanProvider.updateStampLayer(document.id, layer),
                  pageController: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  initialPage: _currentPageIndex,
                  onPageChanged: (index) => setState(() => _currentPageIndex = index),
                ),
              ),

              // Floating Top Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: bg.withValues(alpha: 0.9),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.close), color: textPrimary, onPressed: () => context.pop()),
                        Expanded(
                          child: Text(
                            document.title,
                            style: TextStyle(color: textPrimary, fontSize: AppTypography.title2Size, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          color: _currentPageIndex > 0 ? accent : textSecondary,
                          onPressed: _currentPageIndex > 0 ? () => _goToPage(_currentPageIndex - 1) : null,
                        ),
                        Text('${_currentPageIndex + 1} / ${document.pagePaths.length}', style: TextStyle(color: textPrimary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          color: _currentPageIndex < document.pagePaths.length - 1 ? accent : textSecondary,
                          onPressed: _currentPageIndex < document.pagePaths.length - 1 ? () => _goToPage(_currentPageIndex + 1) : null,
                        ),
                        if (_editMode != TrayEditMode.none)
                          ActionChip(
                            avatar: const Icon(Icons.check, size: 14),
                            label: const Text('Done', style: TextStyle(fontSize: 11)),
                            onPressed: _closeEditor,
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Floating Bottom Controls
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: _buildBottomControls(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
