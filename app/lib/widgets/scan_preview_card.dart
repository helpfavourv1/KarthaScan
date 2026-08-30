import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import 'ink_board.dart';

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

  Widget _buildTextStampControls() {
    final pageLayers = widget.stampLayers.where((l) => l.pageIndex == _currentPage && l.kind == 'text').toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == _selectedStampId, orElse: () => pageLayers.first);
    void upd(StampLayer newLayer) {
      widget.onStampLayerUpdate?.call(_currentPage, newLayer);
    }
    return OverlayEditControls(
      layerType: LayerType.text,
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
            child: PageView.builder(
              controller: _pageController,
              physics: widget.editMode == TrayEditMode.none
                  ? const AlwaysScrollableScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: widget.pagePaths.length,
              onPageChanged: (int index) {
                setState(() => _currentPage = index);
                widget.onPageChanged?.call(index);
              },
              itemBuilder: (BuildContext context, int index) {
                return _PageWithInk(
                  pagePath: widget.pagePaths[index],
                  controller: widget.inkController,
                  pageIndex: index,
                  textSecondary: textSecondary,
                  accent: accent,
                  annotateLayers: widget.annotateLayers,
                  selectedAnnotateBytesPath: _selectedAnnotateBytesPath,
                  onAnnotateSelect: (layer) => setState(() => _selectedAnnotateBytesPath = layer.bytesPath),
                  onAnnotateUpdate: (newLayer) => widget.onAnnotateLayerUpdate?.call(index, newLayer),
                  onSignatureSelect: () {
                    setState(() {});
                    widget.onSignatureSelect?.call();
                  },
                  watermarkLayers: widget.watermarkLayers,
                  selectedWatermarkText: _selectedWatermarkText,
                  onWatermarkSelect: () => widget.onWatermarkSelect?.call(),
                  onWatermarkSelected: (layer) => setState(() => _selectedWatermarkText = layer.text),
                  onWatermarkLayerUpdate: (pageIndex, layer) => widget.onWatermarkLayerUpdate?.call(pageIndex, layer),
                  stampLayers: widget.stampLayers,
                  selectedStampId: _selectedStampId,
                  onStampSelect: () => widget.onStampSelect?.call(),
                  onStampSelected: (layer) => setState(() => _selectedStampId = layer.id),
                  onStampLayerUpdate: (pageIndex, layer) => widget.onStampLayerUpdate?.call(pageIndex, layer),
                );
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
            _buildTextStampControls(),
        ],
      ),
    );
  }
}

class _PageWithInk extends StatefulWidget {
  const _PageWithInk({
    required this.pagePath,
    required this.controller,
    required this.pageIndex,
    required this.textSecondary,
    required this.accent,
    this.annotateLayers = const [],
    this.selectedAnnotateBytesPath,
    this.onAnnotateSelect,
    this.onAnnotateUpdate,
    this.watermarkLayers = const [],
    this.selectedWatermarkText,
    this.onWatermarkSelect,
    this.onWatermarkSelected,
    this.onWatermarkLayerUpdate,
    this.stampLayers = const [],
    this.selectedStampId,
    this.onStampSelect,
    this.onStampSelected,
    this.onStampLayerUpdate,
    this.onSignatureSelect,
  });

  final String pagePath;
  final InkController? controller;
  final int pageIndex;
  final Color textSecondary;
  final Color accent;
  final List<AnnotateLayer> annotateLayers;
  final String? selectedAnnotateBytesPath;
  final void Function(AnnotateLayer layer)? onAnnotateSelect;
  final void Function(AnnotateLayer newLayer)? onAnnotateUpdate;
  final VoidCallback? onSignatureSelect;
  final List<WatermarkLayer> watermarkLayers;
  final String? selectedWatermarkText;
  final VoidCallback? onWatermarkSelect;
  final void Function(WatermarkLayer layer)? onWatermarkSelected;
  final void Function(int pageIndex, WatermarkLayer layer)? onWatermarkLayerUpdate;
  final List<StampLayer> stampLayers;
  final String? selectedStampId;
  final VoidCallback? onStampSelect;
  final void Function(StampLayer layer)? onStampSelected;
  final void Function(int pageIndex, StampLayer layer)? onStampLayerUpdate;

  @override
  State<_PageWithInk> createState() => _PageWithInkState();
}

class _PageWithInkState extends State<_PageWithInk> {
  double _pageAspect = 0.75;

  @override
  void initState() {
    super.initState();
    _loadPageAspect();
  }

  Future<void> _loadPageAspect() async {
    try {
      final file = File(widget.pagePath);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.height > 0 && mounted) {
        setState(() => _pageAspect = (decoded.width / decoded.height).clamp(0.1, 10.0).toDouble());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double iw = constraints.maxWidth;
        double ih = iw / _pageAspect;
        double dx = 0, dy = 0;
        if (ih > constraints.maxHeight) {
          ih = constraints.maxHeight;
          iw = ih * _pageAspect;
          dx = (constraints.maxWidth - iw) / 2;
        } else {
          dy = (constraints.maxHeight - ih) / 2;
        }

        final hasOverlays = (widget.controller?.hasInks ?? false) || widget.annotateLayers.isNotEmpty || widget.watermarkLayers.isNotEmpty || widget.stampLayers.isNotEmpty;
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                panEnabled: !hasOverlays,
                scaleEnabled: !hasOverlays,
                child: Center(
                  child: Image.file(
                    File(widget.pagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: widget.textSecondary, size: 48),
                  ),
                ),
              ),
            ),
            if (widget.controller != null)
              InkOverlayPage(
                controller: widget.controller!,
                onSelected: widget.onSignatureSelect,
                pageIndex: widget.pageIndex,
                imgW: iw,
                imgH: ih,
                iw: iw,
                ih: ih,
                dx: dx,
                dy: dy,
                accent: widget.accent,
              ),
            if (widget.annotateLayers.isNotEmpty)
              AnnotateOverlayPage(
                layers: widget.annotateLayers,
                pageIndex: widget.pageIndex,
                iw: iw,
                ih: ih,
                dx: dx,
                dy: dy,
                accent: widget.accent,
                selectedBytesPath: widget.selectedAnnotateBytesPath,
                onSelect: (layer) => widget.onAnnotateSelect?.call(layer),
                onDrag: (layer, dxDelta, dyDelta) {
                  final dragUpdate = widget.onAnnotateUpdate;
                  if (dragUpdate == null) return;
                  dragUpdate(AnnotateLayer(
                    pageIndex: layer.pageIndex,
                    bytesPath: layer.bytesPath,
                    placement: SignaturePlacement(
                      pctX: (layer.placement.pctX + dxDelta / iw).clamp(0.0, 1.0),
                      pctY: (layer.placement.pctY + dyDelta / ih).clamp(0.0, 1.0),
                      rotationDegrees: layer.placement.rotationDegrees,
                      scale: layer.placement.scale,
                    ),
                  ));
                },
              ),
            if (widget.watermarkLayers.isNotEmpty)
              WatermarkOverlayPage(
                layers: widget.watermarkLayers,
                pageIndex: widget.pageIndex,
                iw: iw,
                ih: ih,
                dx: dx,
                dy: dy,
                accent: widget.accent,
                selectedText: widget.selectedWatermarkText,
                onSelect: (layer) { widget.onWatermarkSelected?.call(layer); widget.onWatermarkSelect?.call(); },
                onDrag: (layer, dxDelta, dyDelta) {
                  widget.onWatermarkLayerUpdate?.call(widget.pageIndex, layer.copyWith(
                    placement: SignaturePlacement(
                      pctX: (layer.placement.pctX + dxDelta / iw).clamp(0.0, 1.0),
                      pctY: (layer.placement.pctY + dyDelta / ih).clamp(0.0, 1.0),
                      rotationDegrees: layer.placement.rotationDegrees,
                      scale: layer.placement.scale,
                    ),
                  ));
                },
              ),
            if (widget.stampLayers.isNotEmpty)
              StampOverlayPage(
                layers: widget.stampLayers,
                pageIndex: widget.pageIndex,
                iw: iw,
                ih: ih,
                dx: dx,
                dy: dy,
                accent: widget.accent,
                selectedId: widget.selectedStampId,
                onSelect: (layer) { widget.onStampSelected?.call(layer); widget.onStampSelect?.call(); },
                onDrag: (layer, dxDelta, dyDelta) {
                  widget.onStampLayerUpdate?.call(widget.pageIndex, layer.copyWith(
                    placement: SignaturePlacement(
                      pctX: (layer.placement.pctX + dxDelta / iw).clamp(0.0, 1.0),
                      pctY: (layer.placement.pctY + dyDelta / ih).clamp(0.0, 1.0),
                      rotationDegrees: layer.placement.rotationDegrees,
                      scale: layer.placement.scale,
                    ),
                  ));
                },
              ),
          ],
        );
      },
    );
  }
}
