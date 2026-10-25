import 'dart:async' show unawaited;

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
import '../widgets/compress_sheet.dart';
import '../widgets/document_canvas.dart';
import '../widgets/document_tools_mixin.dart';
import '../widgets/conditional_banner.dart';
import '../widgets/edit_tray.dart';
import '../widgets/fill_editor_dock.dart';
import '../widgets/layer_control_panel.dart';
import '../widgets/ink_board.dart';
import '../widgets/signature_editor_bar.dart';
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

  String? _selectedAnnotateId;
  String? _selectedWatermarkText;
  String? _selectedStampId;

  // Fill mode state
  String? _fillText;
  double? _fillGhostPctX;
  double? _fillGhostPctY;
  List<FillSnippet> _fillSnippets = [];

  // The Fill text being typed. It is drawn live on the page and only saved to the
  // document when the person finishes (Done, another tap on the page, or leaving).
  StampLayer? _fillDraft;
  bool _fillDraftIsNew = false;
  // The style of the last Fill text, so the next field starts the same way.
  StampLayer _fillTemplate = const StampLayer(
    id: '', pageIndex: 0, kind: 'fill', placement: SignaturePlacement(pctX: 0.5, pctY: 0.5),
    color: 0xFF111111, fontFamily: 'sans-serif', fontWeight: 400, align: 'left', boxWidth: 0.45, fillSize: 0.022,
  );

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final doc = document;
      if (doc != null) _inkController.seed(doc);
      // Defect 2 fix: when entered via Fill tray (startInFillMode),
      // auto-open the fill input sheet on first frame so the user does not
      // have to discover the canvas-tap gesture. Places at page center;
      // user can drag-reposition via LayerControlPanel afterward.
      if (widget.startInFillMode && doc != null) {
        await _onFillTap(0.5, 0.5, _currentPageIndex);
      }
    });
  }


  Future<void> _loadFillSnippets() async {
    _fillSnippets = await _localStorage.loadFillSnippets();
  }

  /// Tap on empty page space in Fill mode: finish any text being typed, then start a
  /// new text box at the tapped spot.
  Future<void> _onFillTap(double pctX, double pctY, int pageIndex) async {
    await _commitFill();
    if (!mounted) return;
    setState(() {
      _fillDraftIsNew = true;
      _fillDraft = _fillTemplate.copyWith(
        id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
        pageIndex: pageIndex,
        placement: SignaturePlacement(pctX: pctX, pctY: pctY),
        text: '',
      );
      _editMode = TrayEditMode.fill;
      _selectedStampId = null;
      _selectedAnnotateId = null;
      _selectedWatermarkText = null;
    });
  }

  /// Saves the typed text as a layer. Empty text is dropped (an existing box keeps its old text).
  Future<void> _commitFill() async {
    final StampLayer? draft = _fillDraft;
    if (draft == null) return;
    final bool isNew = _fillDraftIsNew;
    if (mounted) setState(() => _fillDraft = null);
    final ScanDocument? doc = document;
    if (doc == null || draft.text.trim().isEmpty) return;
    _fillTemplate = draft.copyWith(text: '');
    if (isNew) {
      await _scanProvider.addStampLayer(doc.id, draft);
    } else {
      await _scanProvider.updateStampLayer(doc.id, draft);
    }
    if (mounted) setState(() => _selectedStampId = draft.id);
  }

  /// Opens an existing Fill text for typing (double tap, or Edit in the controls).
  Future<void> _beginEditFill(StampLayer layer) async {
    await _commitFill();
    if (!mounted) return;
    setState(() {
      _fillDraftIsNew = false;
      // An older Fill (shrunk to a fixed box) becomes a normal wrapping box when edited.
      _fillDraft = layer.isFlowFill ? layer : layer.copyWith(boxWidth: 0.30, fillSize: 0.022);
      _editMode = TrayEditMode.fill;
      _selectedStampId = layer.id;
    });
  }

  Future<void> _saveFillSnippet(String text) async {
    final snippet = FillSnippet(id: 'snip_${DateTime.now().microsecondsSinceEpoch}', label: text.length > 12 ? text.substring(0, 12) : text, text: text);
    _fillSnippets.add(snippet);
    await _localStorage.saveFillSnippets(_fillSnippets);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).fillSaveSnippet), duration: const Duration(seconds: 2)));
  }

  Future<void> _deleteFillSnippet(String id) async {
    _fillSnippets.removeWhere((s) => s.id == id);
    await _localStorage.saveFillSnippets(_fillSnippets);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).fillDeleteSnippet), duration: const Duration(seconds: 2)));
  }

  /// The document's text layers plus the Fill text being typed (drawn live).
  List<StampLayer> _stampsForCanvas(ScanDocument doc) {
    final StampLayer? d = _fillDraft;
    if (d == null) return doc.stampLayers;
    final StampLayer shown = d.text.isEmpty ? d.copyWith(text: AppLocalizations.of(context).fillTypeHint, opacity: 0.4) : d;
    return <StampLayer>[for (final StampLayer l in doc.stampLayers) if (l.id != d.id) l, shown];
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
    if (_fillDraft != null) unawaited(_commitFill());
    if (_editMode == TrayEditMode.none) return;
    setState(() {
      _editMode = TrayEditMode.none;
      _inkController.setEditInk(null);
      _selectedAnnotateId = null;
      _selectedWatermarkText = null;
      _selectedStampId = null;
    });
    _inkController.showSignatureAdIfPending();
  }

  @override
  void onLayerAdded(TrayEditMode mode, String? identifier) {
    setState(() {
      switch (mode) {
        case TrayEditMode.annotate:
          _selectedAnnotateId = identifier;
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


  Future<void> _reEditFill(StampLayer layer) => _beginEditFill(layer);

  void _goToPage(int index) {
    final doc = document;
    if (doc == null) return;
    final clamped = index.clamp(0, doc.pagePaths.length - 1);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(clamped);
    }
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
      bottomNavigationBar: const ConditionalBanner(),
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
                      IconButton(icon: const Icon(Icons.close), color: textPrimary, onPressed: () { _inkController.showSignatureAdIfPending(); context.pop(); }),
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
                        onPressed: () {
                          final doc = document;
                          if (doc != null) context.push('/export', extra: <String>[doc.id]);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.file_download_outlined, size: 20),
                        color: textPrimary,
                        onPressed: exportDocument,
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
                  stampLayers: _stampsForCanvas(doc),
                  selectedAnnotateId: _selectedAnnotateId,
                  selectedWatermarkText: _selectedWatermarkText,
                  selectedStampId: _selectedStampId,
                  onAnnotateSelect: (layer) => setState(() {
                    _selectedAnnotateId = layer.id;
                    _selectedWatermarkText = null;
                    _selectedStampId = null;
                    _editMode = TrayEditMode.annotate;
                  }),
                  onAnnotateUpdate: (pageIndex, newLayer) => scanProvider.updateAnnotateLayer(doc.id, newLayer),
                  onSignatureSelect: () => setState(() => _editMode = TrayEditMode.signature),
                  onWatermarkSelect: () => setState(() => _editMode = TrayEditMode.watermark),
                  onWatermarkSelected: (layer) => setState(() { _selectedWatermarkText = layer.id; _selectedAnnotateId = null; _selectedStampId = null; _editMode = TrayEditMode.watermark; }),
                  onWatermarkLayerUpdate: (pageIndex, layer) => scanProvider.updateWatermarkLayer(doc.id, layer),
                  onStampSelected: (layer) => setState(() { _selectedStampId = layer.id; _selectedAnnotateId = null; _selectedWatermarkText = null; _editMode = layer.kind == 'fill' ? TrayEditMode.fill : (layer.kind == 'text' ? TrayEditMode.text : (layer.kind == 'note' ? TrayEditMode.note : (layer.kind == 'date' ? TrayEditMode.date : (layer.kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal)))); }),
                  onStampLayerUpdate: (pageIndex, layer) {
                    // Dragging the box being typed only moves the draft.
                    if (_fillDraft?.id == layer.id) {
                      setState(() => _fillDraft = _fillDraft!.copyWith(placement: layer.placement));
                    } else {
                      scanProvider.updateStampLayer(doc.id, layer);
                    }
                  },
                  onStampDoubleTap: (layer) { if (layer.kind == 'fill') unawaited(_beginEditFill(layer)); },
                  pageController: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  initialPage: _currentPageIndex,
                  onPageChanged: (index) => setState(() { _currentPageIndex = index; }),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        child: SignatureEditorBar(
                          controller: _inkController,
                          pageIndex: _currentPageIndex,
                          accent: accent,
                          surface: surface,
                          textPrimary: textPrimary,
                          isDark: isDark,
                          onAddInk: () async {
                            final inkId = await _inkController.addInk(context, _localStorage);
                            if (inkId != null && mounted) {
                              _inkController.placeOnPage(_currentPageIndex);
                              setState(() {});
                            }
                          },
                          onPlaceHere: () => _inkController.placeOnPage(_currentPageIndex),
                        ),
                      ),
                    // Context controls (additive, never replaces tray)
                    if (_editMode == TrayEditMode.signature && _inkController.editInkId != null)
                      SignatureOverlayControls(
                        controller: _inkController,
                        pageIndex: _currentPageIndex,
                        pageCount: doc.pagePaths.length,
                        onDone: closeEditor,
                      ),
                    LayerControlPanel(
                      document: doc,
                      pageIndex: _currentPageIndex,
                      editMode: _editMode,
                      scanProvider: _scanProvider,
                      selectedAnnotateId: _selectedAnnotateId,
                      selectedWatermarkText: _selectedWatermarkText,
                      selectedStampId: _selectedStampId,
                      onEditFill: _reEditFill,
                      onDone: closeEditor,
                    ),
                    // The Done button lives inside the control rows when they are showing.
                    if ((_editMode != TrayEditMode.none || _selectedAnnotateId != null || _selectedWatermarkText != null || _selectedStampId != null) &&
                        !LayerControlPanel.willShow(doc, _currentPageIndex, _editMode) &&
                        !(_editMode == TrayEditMode.signature && SignatureOverlayControls.willShow(_inkController, _currentPageIndex)))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ActionChip(
                            avatar: const Icon(Icons.check, size: 14),
                            label: Text(AppLocalizations.of(context).commonDone, style: TextStyle(fontSize: 11)),
                            onPressed: closeEditor,
                          ),
                        ),
                      ),
                    // Fill: a hint until a spot is tapped, then the typing bar above the keyboard.
                    if (_editMode == TrayEditMode.fill && _fillDraft == null && _selectedStampId == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(AppLocalizations.of(context).fillTapHint, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: textSecondary)),
                      ),
                    if (_fillDraft != null)
                      FillEditorDock(
                        draft: _fillDraft!,
                        snippets: _fillSnippets,
                        onChanged: (StampLayer d) => setState(() => _fillDraft = d),
                        onDone: () => unawaited(_commitFill()),
                        onSaveSnippet: (String t) => unawaited(_saveFillSnippet(t)),
                        onDeleteSnippet: (String id) => unawaited(_deleteFillSnippet(id)),
                        accent: accent,
                        surface: surface,
                        textPrimary: textPrimary,
                      ),
                    // Compact train tray (hidden only while the keyboard is up for typing; it could not be used then)
                    if (_fillDraft == null)
                    EditTray(
                      compact: true,
                      onMarkup: annotateCurrentPage,
                      onSign: signFromTray,
                      onWatermark: addWatermarkNow,
                      onOcr: regionOcr,
                      onConvert: exportDocument,
                      onCompress: () async {
                        final CompressChoice? c = await showModalBottomSheet<CompressChoice>(
                          context: context,
                          builder: (BuildContext ctx) => CompressSheet(document: doc),
                        );
                        if (c == null || !context.mounted) return;
                        closeEditor();
                        context.push('/export', extra: <String, dynamic>{'ids': <String>[doc.id], 'format': c.format.name, 'compression': c.tier.name});
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

  
  
  }
