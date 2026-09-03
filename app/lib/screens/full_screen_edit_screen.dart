import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/local_storage.dart';
import '../core/services/ocr_service.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';
import '../widgets/document_canvas.dart';
import '../widgets/document_tools_mixin.dart';
import '../widgets/edit_tray.dart';
import '../widgets/ink_board.dart';
import '../widgets/seal_stamp_sheet.dart';
import '../widgets/signature_editor_bar.dart';
import '../widgets/text_stamp_sheet.dart';
import '../widgets/watermark_sheet.dart';
import '../widgets/fill_input_bar.dart';
import '../core/models/fill_snippet.dart';
import '../l10n/app_localizations.dart';

class FullScreenEditScreen extends StatefulWidget {
  const FullScreenEditScreen({super.key, required this.documentId, this.startInFillMode = false});
  final String documentId;
  final bool startInFillMode;

  @override
  State<FullScreenEditScreen> createState() => _FullScreenEditScreenState();
}

class _FullScreenEditScreenState extends State<FullScreenEditScreen> with DocumentTools {
  late final ScanProvider _scanProvider;
  late final InkController _inkController;
  late final OcrService _ocrService;
  late final ShareService _shareService;
  late final LocalStorageService _localStorage;
  late final PageController _pageController;

  int _currentPageIndex = 0;
  TrayEditMode _editMode = TrayEditMode.none;

  String? _selectedAnnotateBytesPath;
  String? _selectedWatermarkText;
  String? _selectedStampId;

  // Fill mode state
  String? _fillText;
  double? _fillGhostPctX;
  double? _fillGhostPctY;
  int? _fillGhostPageIndex;
  List<FillSnippet> _fillSnippets = [];

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _inkController = InkController(onChange: _persistSignature);
    _ocrService = OcrService();
    _shareService = ShareService();
    _localStorage = LocalStorageService();
    _pageController = PageController();
    _scanProvider.setActiveScan(widget.documentId);
    _scanProvider.undoManager.clear();
    _loadFillSnippets();
    if (widget.startInFillMode) _editMode = TrayEditMode.fill;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final doc = document;
      if (doc != null) _inkController.seed(doc);
    });
  }


  Future<void> _loadFillSnippets() async {
    _fillSnippets = await _localStorage.loadFillSnippets();
  }

  void _onFillTap(double pctX, double pctY, int pageIndex) {
    setState(() {
      _fillGhostPctX = pctX;
      _fillGhostPctY = pctY;
      _fillGhostPageIndex = pageIndex;
      _editMode = TrayEditMode.fill;
    });
  }

  Future<void> _persistSignature() async {
    final doc = document;
    if (doc == null) return;
    await scanProvider.setSignatureState(doc.id, _inkController.inks.values.toList(), _inkController.layers);
  }

  void _resyncInk() {
    final doc = document;
    if (doc != null) _inkController.restoreFrom(doc);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  // --- DocumentTools mixin implementation ---
  @override
  ScanProvider get scanProvider => _scanProvider;
  @override
  InkController get inkController => _inkController;
  @override
  LocalStorageService get localStorage => _localStorage;
  @override
  OcrService get ocrService => _ocrService;
  @override
  ShareService get shareService => _shareService;
  @override
  ScanDocument? get document {
    for (final doc in _scanProvider.documents.value) {
      if (doc.id == widget.documentId) return doc;
    }
    return null;
  }
  @override
  int get currentPageIndex => _currentPageIndex;
  @override
  set editMode(TrayEditMode mode) => setState(() => _editMode = mode);
  @override
  void closeEditor() {
    if (_editMode == TrayEditMode.none) return;
    setState(() {
      _editMode = TrayEditMode.none;
      _inkController.setEditInk(null);
      _selectedAnnotateBytesPath = null;
      _selectedWatermarkText = null;
      _selectedStampId = null;
    });
  }

  @override
  void onLayerAdded(TrayEditMode mode, String? identifier) {
    setState(() {
      switch (mode) {
        case TrayEditMode.annotate:
          _selectedAnnotateBytesPath = identifier;
          break;
        case TrayEditMode.watermark:
          _selectedWatermarkText = identifier;
          break;
        case TrayEditMode.text:
        case TrayEditMode.note:
        case TrayEditMode.date:
        case TrayEditMode.checkbox:
        case TrayEditMode.seal:
          _selectedStampId = identifier;
          break;
        default:
          break;
      }
    });
  }

  void _goToPage(int index) {
    final doc = document;
    if (doc == null) return;
    final clamped = index.clamp(0, doc.pagePaths.length - 1);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;

    return Scaffold(
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: _scanProvider.documents,
        builder: (context, _) {
          final doc = document;
          if (doc == null) {
            return SafeArea(child: Center(child: Text(AppLocalizations.of(context).documentNotFound, style: TextStyle(color: textPrimary))));
          }

          return Column(
            children: [
              // Header with Share/Export
              Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.close), color: textPrimary, onPressed: () => context.pop()),
                      Expanded(
                        child: Text(
                          doc.title,
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
                      Text(AppLocalizations.of(context).pageIndicator(_currentPageIndex + 1, doc.pagePaths.length), style: TextStyle(color: textPrimary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        color: _currentPageIndex < doc.pagePaths.length - 1 ? accent : textSecondary,
                        onPressed: _currentPageIndex < doc.pagePaths.length - 1 ? () => _goToPage(_currentPageIndex + 1) : null,
                      ),
                      ListenableBuilder(
                        listenable: _scanProvider.undoManager.version,
                        builder: (context, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.undo, size: 20),
                              tooltip: AppLocalizations.of(context).undoTooltip,
                              color: _scanProvider.undoManager.canUndo ? textPrimary : textSecondary.withValues(alpha: 0.4),
                              onPressed: _scanProvider.undoManager.canUndo
                                  ? () async {
                                      await _scanProvider.undoManager.undo();
                                      _resyncInk();
                                    }
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.redo, size: 20),
                              tooltip: AppLocalizations.of(context).redoTooltip,
                              color: _scanProvider.undoManager.canRedo ? textPrimary : textSecondary.withValues(alpha: 0.4),
                              onPressed: _scanProvider.undoManager.canRedo
                                  ? () async {
                                      await _scanProvider.undoManager.redo();
                                      _resyncInk();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.ios_share, size: 20),
                        color: textPrimary,
                        onPressed: shareDocument,
                      ),
                      IconButton(
                        icon: const Icon(Icons.file_download_outlined, size: 20),
                        color: textPrimary,
                        onPressed: exportDocument,
                      ),
                      if (_editMode != TrayEditMode.none)
                        ActionChip(
                          avatar: const Icon(Icons.check, size: 14),
                          label: Text(AppLocalizations.of(context).commonDone, style: TextStyle(fontSize: 11)),
                          onPressed: closeEditor,
                        ),
                    ],
                  ),
                ),
              ),
              // Canvas
              Expanded(
                child: DocumentCanvas(
                  pagePaths: doc.pagePaths,
                  inkController: _inkController,
                  annotateLayers: doc.annotateLayers,
                  watermarkLayers: doc.watermarkLayers,
                  stampLayers: doc.stampLayers,
                  selectedAnnotateBytesPath: _selectedAnnotateBytesPath,
                  selectedWatermarkText: _selectedWatermarkText,
                  selectedStampId: _selectedStampId,
                  onAnnotateSelect: (layer) => setState(() {
                    _selectedAnnotateBytesPath = layer.bytesPath;
                    _editMode = TrayEditMode.annotate;
                  }),
                  onAnnotateUpdate: (pageIndex, newLayer) => scanProvider.updateAnnotateLayer(doc.id, newLayer),
                  onSignatureSelect: () => setState(() => _editMode = TrayEditMode.signature),
                  onWatermarkSelect: () => setState(() => _editMode = TrayEditMode.watermark),
                  onWatermarkSelected: (layer) => setState(() => _selectedWatermarkText = layer.text),
                  onWatermarkLayerUpdate: (pageIndex, layer) => scanProvider.updateWatermarkLayer(doc.id, layer),
                  onStampSelect: () {
                    final kind = _editMode == TrayEditMode.note ? 'note' : (_editMode == TrayEditMode.date ? 'date' : (_editMode == TrayEditMode.checkbox ? 'checkbox' : (_editMode == TrayEditMode.seal ? 'seal' : 'text')));
                    setState(() => _editMode = kind == 'text' ? TrayEditMode.text : (kind == 'note' ? TrayEditMode.note : (kind == 'date' ? TrayEditMode.date : (kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal))));
                  },
                  onStampSelected: (layer) => setState(() => _selectedStampId = layer.id),
                  onStampLayerUpdate: (pageIndex, layer) => scanProvider.updateStampLayer(doc.id, layer),
                  pageController: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  initialPage: _currentPageIndex,
                  onPageChanged: (index) => setState(() { _currentPageIndex = index; _scanProvider.undoManager.clear(); }),
                  pageTransforms: doc.pageTransforms,
                  onFillTap: _editMode == TrayEditMode.fill ? _onFillTap : null,
                  fillGhostText: _fillText,
                  fillGhostPctX: _fillGhostPctX,
                  fillGhostPctY: _fillGhostPctY,
                ),
              ),
              // Bottom stack
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Signature bar (only in signature mode)
                    if (_editMode == TrayEditMode.signature)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SignatureEditorBar(
                          controller: _inkController,
                          pageIndex: _currentPageIndex,
                          accent: accent,
                          surface: surface,
                          textPrimary: textPrimary,
                          isDark: isDark,
                          onAddInk: () => _inkController.addInk(context, _localStorage),
                          onPlaceHere: () => _inkController.placeOnPage(_currentPageIndex),
                        ),
                      ),
                    // Context controls (additive, never replaces tray)
                    if (_editMode == TrayEditMode.signature && _inkController.editInkId != null)
                      SignatureOverlayControls(
                        controller: _inkController,
                        pageIndex: _currentPageIndex,
                        pageCount: doc.pagePaths.length,
                      ),
                    if (_editMode == TrayEditMode.annotate && _selectedAnnotateBytesPath != null)
                      _buildAnnotateControls(),
                    if (_editMode == TrayEditMode.watermark && _selectedWatermarkText != null)
                      _buildWatermarkControls(),
                    if (_editMode == TrayEditMode.text || _editMode == TrayEditMode.note || _editMode == TrayEditMode.date || _editMode == TrayEditMode.checkbox || _editMode == TrayEditMode.seal)
                      if (_selectedStampId != null) _buildStampControls(),
                    if (_editMode == TrayEditMode.fill && _fillGhostPctX != null && _fillGhostPctY != null && _fillGhostPageIndex != null)
                      FillInputBar(
                        initialText: _fillText ?? '',
                        snippets: _fillSnippets,
                        onTextChange: (text) => setState(() => _fillText = text),
                        onConfirm: (text, allCaps, color, fontSize) async {
                          if (text.isEmpty) return;
                          final layer = StampLayer(
                            id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
                            pageIndex: _fillGhostPageIndex!,
                            kind: 'fill',
                            placement: SignaturePlacement(pctX: _fillGhostPctX!, pctY: _fillGhostPctY!),
                            text: text,
                            fontSize: fontSize,
                            color: color,
                            fontFamily: 'monospace',
                            fontWeight: 700,
                            align: 'left',
                            allCaps: allCaps,
                          );
                          await _scanProvider.addStampLayer(doc.id, layer);
                          setState(() { _fillGhostPctX = null; _fillGhostPctY = null; _fillGhostPageIndex = null; _editMode = TrayEditMode.none; });
                        },
                        onCancel: () => setState(() { _fillGhostPctX = null; _fillGhostPctY = null; _fillGhostPageIndex = null; _editMode = TrayEditMode.none; }),
                        onSaveSnippet: (text) async {
                          final snippet = FillSnippet(id: 'snip_${DateTime.now().microsecondsSinceEpoch}', label: text.length > 12 ? text.substring(0, 12) : text, text: text);
                          _fillSnippets.add(snippet);
                          await _localStorage.saveFillSnippets(_fillSnippets);
                          setState(() {});
                        },
                        onDeleteSnippet: (id) async {
                          _fillSnippets.removeWhere((s) => s.id == id);
                          await _localStorage.saveFillSnippets(_fillSnippets);
                          setState(() {});
                        },
                      ),
                    // Compact train tray (always visible)
                    EditTray(
                      compact: true,
                      onMarkup: annotateCurrentPage,
                      onSign: signFromTray,
                      onWatermark: addWatermarkNow,
                      onOcr: regionOcr,
                      onConvert: exportDocument,
                      onCompress: () {
                        closeEditor();
                        context.push('/export', extra: <String, dynamic>{'ids': <String>[doc.id], 'format': 'jpg'});
                      },
                      onRotate: rotatePage,
                      onResize: resizePage,
                      onPages: openPagesManager,
                      onFilter: applyFilterToPage,
                      onCrop: cropCurrentPage,
                      onText: () => addStampNow('text'),
                      onNote: () => addStampNow('note'),
                      onDate: () => addStampNow('date'),
                      onCheckbox: () => addStampNow('checkbox'),
                      onSeal: () => addStampNow('seal'),
                      onRevert: doc.pageTransforms[_currentPageIndex]?.isEmpty == false ? revertPage : null,
                      onPrint: printDocument,
                      onEmail: emailDocument,
                      onErase: erasePage,
                      onFill: () => setState(() { _editMode = TrayEditMode.fill; _fillGhostPctX = null; _fillGhostPctY = null; }),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnnotateControls() {
    final doc = document;
    if (doc == null) return const SizedBox.shrink();
    final pageLayers = doc.annotateLayers.where((l) => l.pageIndex == _currentPageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.bytesPath == _selectedAnnotateBytesPath, orElse: () => pageLayers.first);

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
        onRotateLeft: () => scanProvider.updateAnnotateLayer(doc.id, AnnotateLayer(pageIndex: layer.pageIndex, bytesPath: layer.bytesPath, placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => scanProvider.updateAnnotateLayer(doc.id, AnnotateLayer(pageIndex: layer.pageIndex, bytesPath: layer.bytesPath, placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => scanProvider.updateAnnotateLayer(doc.id, AnnotateLayer(pageIndex: layer.pageIndex, bytesPath: layer.bytesPath, placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => scanProvider.updateAnnotateLayer(doc.id, AnnotateLayer(pageIndex: layer.pageIndex, bytesPath: layer.bytesPath, placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onCopyAll: () {
          for (int i = 0; i < doc.pagePaths.length; i++) {
            scanProvider.addAnnotateLayer(doc.id, AnnotateLayer(pageIndex: i, bytesPath: layer.bytesPath, placement: layer.placement));
          }
        },
        onClearThis: () => scanProvider.removeAnnotateLayer(doc.id, _currentPageIndex, layer.bytesPath),
        onRemove: () => scanProvider.removeAnnotateLayer(doc.id, _currentPageIndex, layer.bytesPath),
        onClearAll: () => scanProvider.clearAnnotateLayers(doc.id),
      ),
    );
  }

  Widget _buildWatermarkControls() {
    final doc = document;
    if (doc == null) return const SizedBox.shrink();
    final pageLayers = doc.watermarkLayers.where((l) => l.pageIndex == _currentPageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.text == _selectedWatermarkText, orElse: () => pageLayers.first);

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
        onRotateLeft: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onOpacityDown: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(opacity: (layer.opacity - 0.05).clamp(0.05, 1.0))),
        onOpacityUp: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(opacity: (layer.opacity + 0.05).clamp(0.05, 1.0))),
        onFontSizeDown: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144))),
        onFontSizeUp: () => scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144))),
        onTools: () async {
          final config = await showModalBottomSheet<WatermarkLayer>(
            context: context,
            isScrollControlled: true,
            builder: (context) => WatermarkSheet(initialConfig: layer),
          );
          if (config != null && mounted) {
            final updated = config.copyWith(pageIndex: layer.pageIndex, placement: layer.placement);
            await scanProvider.removeWatermarkLayer(doc.id, layer.pageIndex, layer.text);
            await scanProvider.addWatermarkLayer(doc.id, updated);
          }
        },
        onCopyAll: () {
          for (int i = 0; i < doc.pagePaths.length; i++) {
            scanProvider.addWatermarkLayer(doc.id, layer.copyWith(pageIndex: i));
          }
        },
        onClearThis: () => scanProvider.removeWatermarkLayer(doc.id, _currentPageIndex, layer.text),
        onRemove: () => scanProvider.removeWatermarkLayer(doc.id, _currentPageIndex, layer.text),
        onClearAll: () => scanProvider.clearWatermarkLayers(doc.id),
      ),
    );
  }

  Widget _buildStampControls() {
    final doc = document;
    if (doc == null) return const SizedBox.shrink();
    final kind = _editMode == TrayEditMode.note ? 'note' : (_editMode == TrayEditMode.date ? 'date' : (_editMode == TrayEditMode.checkbox ? 'checkbox' : (_editMode == TrayEditMode.seal ? 'seal' : 'text')));
    final pageLayers = doc.stampLayers.where((l) => l.pageIndex == _currentPageIndex && l.kind == kind).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == _selectedStampId, orElse: () => pageLayers.first);

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
        onRotateLeft: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onOpacityDown: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(opacity: (layer.opacity - 0.05).clamp(0.05, 1.0))),
        onOpacityUp: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(opacity: (layer.opacity + 0.05).clamp(0.05, 1.0))),
        onFontSizeDown: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144))),
        onFontSizeUp: () => scanProvider.updateStampLayer(doc.id, layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144))),
        onTools: () async {
          final config = await showModalBottomSheet<StampResult>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => layer.kind == 'seal'
                ? SealStampSheet(initial: layer)
                : TextStampSheet(kind: layer.kind, initial: layer),
          );
          if (config != null && mounted) {
            final updated = layer.copyWith(
              text: config.text, fontSize: config.fontSize, color: config.color,
              fontFamily: config.fontFamily, fontWeight: config.fontWeightValue, align: config.alignName,
              halo: config.halo, noteBgColor: config.noteBgColorValue, dateFormat: config.dateFormatValue,
              customDateMillis: config.customDateMillisValue, checked: config.checkedValue,
              checkShape: config.checkShapeValue, boxColor: config.boxColorValue, tickColor: config.tickColorValue,
              sealShape: config.sealShapeValue, sealSubtext: config.sealSubtextValue, sealCenter: config.sealCenterValue,
            );
            await scanProvider.updateStampLayer(doc.id, updated);
          }
        },
        onCopyAll: () {
          for (int i = 0; i < doc.pagePaths.length; i++) {
            scanProvider.addStampLayer(doc.id, layer.copyWith(id: 'stamp_${DateTime.now().microsecondsSinceEpoch}_$i', pageIndex: i));
          }
        },
        onClearThis: () => scanProvider.removeStampLayer(doc.id, layer.id),
        onRemove: () => scanProvider.removeStampLayer(doc.id, layer.id),
        onClearAll: () => scanProvider.clearStampLayers(doc.id),
      ),
    );
  }
}
