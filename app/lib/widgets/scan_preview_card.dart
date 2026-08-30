import 'package:flutter/material.dart';

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import 'ink_board.dart';
import 'document_canvas.dart';

class ScanPreviewCard extends StatefulWidget {
  const ScanPreviewCard({
    super.key,
    required this.pagePaths,
    this.inkController,
    this.annotateLayers = const [],
    this.watermarkLayers = const [],
    this.stampLayers = const [],
    this.editMode = TrayEditMode.none,
    this.onSignatureSelect,
    this.onAnnotateSelect,
    this.onWatermarkSelect,
    this.onWatermarkLayerUpdate,
    this.onWatermarkEditTools,
    this.onDoneEditing,
    this.onShare,
    this.onAnnotateLayerUpdate,
    this.onAnnotateThisPage,
    this.onCopyAnnotateToAllPages,
    this.onClearAnnotatePage,
    this.onClearAllAnnotateLayers,
    this.onCopyWatermarkToAllPages,
    this.onClearWatermarkPage,
    this.onClearAllWatermarkLayers,
    this.onStampSelect,
    this.onStampLayerUpdate,
    this.onStampEditTools,
    this.onCopyStampToAllPages,
    this.onClearStampPage,
    this.onClearAllStampLayers,
    this.initialPage = 0,
    this.onPageChanged,
    this.onEditFullscreen,
  });

  final List<String> pagePaths;
  final InkController? inkController;
  final List<AnnotateLayer> annotateLayers;
  final List<WatermarkLayer> watermarkLayers;
  final List<StampLayer> stampLayers;
  final TrayEditMode editMode;
  final VoidCallback? onSignatureSelect;
  final VoidCallback? onAnnotateSelect;
  final VoidCallback? onWatermarkSelect;
  final void Function(int pageIndex, WatermarkLayer layer)? onWatermarkLayerUpdate;
  final VoidCallback? onWatermarkEditTools;
  final VoidCallback? onDoneEditing;
  final VoidCallback? onShare;
  final void Function(int pageIndex, AnnotateLayer layer)? onAnnotateLayerUpdate;
  final void Function(int pageIndex)? onAnnotateThisPage;
  final void Function(AnnotateLayer layer)? onCopyAnnotateToAllPages;
  final void Function(int pageIndex)? onClearAnnotatePage;
  final VoidCallback? onClearAllAnnotateLayers;
  final void Function(WatermarkLayer layer)? onCopyWatermarkToAllPages;
  final void Function(int pageIndex)? onClearWatermarkPage;
  final VoidCallback? onClearAllWatermarkLayers;
  final VoidCallback? onStampSelect;
  final void Function(int pageIndex, StampLayer layer)? onStampLayerUpdate;
  final VoidCallback? onStampEditTools;
  final void Function(StampLayer layer)? onCopyStampToAllPages;
  final void Function(int pageIndex)? onClearStampPage;
  final VoidCallback? onClearAllStampLayers;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onEditFullscreen;

  @override
  State<ScanPreviewCard> createState() => _ScanPreviewCardState();
}

class _ScanPreviewCardState extends State<ScanPreviewCard> {
  late final PageController _pageController;
  late int _currentPage;
  String? _selectedAnnotateBytesPath;
  String? _selectedWatermarkText;
  String? _selectedStampId;

  int get _lastIndex => widget.pagePaths.isEmpty ? 0 : widget.pagePaths.length - 1;

  @override
  void initState() {
    super.initState();
    final int requested = widget.initialPage;
    _currentPage = requested < 0 ? 0 : (requested > _lastIndex ? _lastIndex : requested);
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  Widget _buildSignatureControls() {
    final controller = widget.inkController;
    if (controller == null) return const SizedBox.shrink();
    final editId = controller.editInkId;
    if (editId == null) return const SizedBox.shrink();
    final pl = controller.inkPlacements[editId]?[_currentPage];
    if (pl == null) return const SizedBox.shrink();
    final pageCount = widget.pagePaths.length;

    void doCopyAll() => controller.copyToAllPages(editId, _currentPage, pageCount);
    void doClearThis() => controller.removePlacement(editId, _currentPage);
    void doRemove() => controller.removeInk(editId);
    void doClearAll() => controller.clearAll();

    return OverlayEditControls(
      layerType: LayerType.signature,
      rotationDegrees: pl.rotationDegrees,
      scale: pl.scale,
      onRotateLeft: () => controller.updatePlacement(editId, _currentPage,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: (pl.rotationDegrees - 10).clamp(-180, 180), scale: pl.scale)),
      onRotateRight: () => controller.updatePlacement(editId, _currentPage,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: (pl.rotationDegrees + 10).clamp(-180, 180), scale: pl.scale)),
      onScaleDown: () => controller.updatePlacement(editId, _currentPage,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: pl.rotationDegrees, scale: (pl.scale - 0.1).clamp(0.1, 5.0))),
      onScaleUp: () => controller.updatePlacement(editId, _currentPage,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: pl.rotationDegrees, scale: (pl.scale + 0.1).clamp(0.1, 5.0))),
      onCopyAll: doCopyAll,
      onClearThis: doClearThis,
      onRemove: doRemove,
      onClearAll: doClearAll,
    );
  }

  Widget _buildStampControls(String kind) {
    final pageLayers = widget.stampLayers.where((l) => l.pageIndex == _currentPage && l.kind == kind).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == _selectedStampId, orElse: () => pageLayers.first);
    void upd(StampLayer newLayer) {
      widget.onStampLayerUpdate?.call(_currentPage, newLayer);
    }
    return OverlayEditControls(
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
      onTools: widget.onStampEditTools,
      onCopyAll: () => widget.onCopyStampToAllPages?.call(layer),
      onClearThis: () => widget.onClearStampPage?.call(_currentPage),
      onRemove: () => widget.onClearStampPage?.call(_currentPage),
      onClearAll: () => widget.onClearAllStampLayers?.call(),
    );
  }

  Widget _buildWatermarkControls() {
    final pageLayers = widget.watermarkLayers.where((l) => l.pageIndex == _currentPage).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.text == _selectedWatermarkText, orElse: () => pageLayers.first);
    void upd(WatermarkLayer newLayer) {
      widget.onWatermarkLayerUpdate?.call(_currentPage, newLayer);
    }
    return OverlayEditControls(
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
      onTools: widget.onWatermarkEditTools,
      onCopyAll: () => widget.onCopyWatermarkToAllPages?.call(layer),
      onClearThis: () => widget.onClearWatermarkPage?.call(_currentPage),
      onRemove: () => widget.onClearWatermarkPage?.call(_currentPage),
      onClearAll: () => widget.onClearAllWatermarkLayers?.call(),
    );
  }

  Widget _buildAnnotateControls() {
    final pageLayers = widget.annotateLayers.where((l) => l.pageIndex == _currentPage).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.bytesPath == _selectedAnnotateBytesPath, orElse: () => pageLayers.first);
    void upd(SignaturePlacement pl) {
      widget.onAnnotateLayerUpdate?.call(_currentPage, AnnotateLayer(pageIndex: layer.pageIndex, bytesPath: layer.bytesPath, placement: pl));
    }
    return OverlayEditControls(
      layerType: LayerType.annotate,
      rotationDegrees: layer.placement.rotationDegrees,
      scale: layer.placement.scale,
      onRotateLeft: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale)),
      onRotateRight: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale)),
      onScaleDown: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0))),
      onScaleUp: () => upd(SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0))),
      onCopyAll: () => widget.onCopyAnnotateToAllPages?.call(layer),
      onClearThis: () => widget.onClearAnnotatePage?.call(_currentPage),
      onRemove: () => widget.onClearAnnotatePage?.call(_currentPage),
      onClearAll: () => widget.onClearAllAnnotateLayers?.call(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    if (widget.pagePaths.isEmpty) {
      return ColoredBox(
        color: bg,
        child: Center(
          child: Text(l10n.scanPreviewNoPages, style: TextStyle(color: textSecondary, fontSize: AppTypography.bodySize)),
        ),
      );
    }

    return ColoredBox(
      color: bg,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
                  icon: Icon(Icons.chevron_left, color: _currentPage > 0 ? accent : textSecondary),
                ),
                Text('${_currentPage + 1} / ${widget.pagePaths.length}', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _currentPage < _lastIndex ? () => _goToPage(_currentPage + 1) : null,
                  icon: Icon(Icons.chevron_right, color: _currentPage < _lastIndex ? accent : textSecondary),
                ),
                if (widget.onEditFullscreen != null)
                  ActionChip(
                    avatar: const Icon(Icons.open_in_full, size: 14),
                    label: const Text('Fullscreen', style: TextStyle(fontSize: 11)),
                    onPressed: widget.onEditFullscreen,
                  ),
                const Spacer(),
                if (widget.editMode != TrayEditMode.none && widget.onDoneEditing != null)
                  ActionChip(
                    avatar: const Icon(Icons.check, size: 14),
                    label: const Text('Done', style: TextStyle(fontSize: 11)),
                    onPressed: widget.onDoneEditing,
                  ),
              ],
            ),
          ),
          Expanded(
            child: DocumentCanvas(
                pagePaths: widget.pagePaths,
                inkController: widget.inkController,
                annotateLayers: widget.annotateLayers,
                watermarkLayers: widget.watermarkLayers,
                stampLayers: widget.stampLayers,
                selectedAnnotateBytesPath: _selectedAnnotateBytesPath,
                selectedWatermarkText: _selectedWatermarkText,
                selectedStampId: _selectedStampId,
                onAnnotateSelect: (layer) => setState(() => _selectedAnnotateBytesPath = layer.bytesPath),
                onAnnotateUpdate: widget.onAnnotateLayerUpdate,
                onSignatureSelect: () {
                  setState(() {});
                  widget.onSignatureSelect?.call();
                },
                onWatermarkSelect: widget.onWatermarkSelect,
                onWatermarkSelected: (layer) => setState(() => _selectedWatermarkText = layer.text),
                onWatermarkLayerUpdate: widget.onWatermarkLayerUpdate,
                onStampSelect: widget.onStampSelect,
                onStampSelected: (layer) => setState(() => _selectedStampId = layer.id),
                onStampLayerUpdate: widget.onStampLayerUpdate,
                physics: widget.editMode == TrayEditMode.none
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                initialPage: _currentPage,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  widget.onPageChanged?.call(index);
                },
              ),
          ),
          if (widget.editMode == TrayEditMode.signature && widget.inkController != null)
            _buildSignatureControls(),
          if (widget.editMode == TrayEditMode.annotate)
            _buildAnnotateControls(),
          if (widget.editMode == TrayEditMode.watermark)
            _buildWatermarkControls(),
          if (widget.editMode == TrayEditMode.text)
            _buildStampControls('text'),
          if (widget.editMode == TrayEditMode.note)
            _buildStampControls('note'),
          if (widget.editMode == TrayEditMode.date)
            _buildStampControls('date'),
          if (widget.editMode == TrayEditMode.checkbox)
            _buildStampControls('checkbox'),
          if (widget.editMode == TrayEditMode.seal)
            _buildStampControls('seal'),
        ],
      ),
    );
  }
}



