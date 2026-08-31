import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import 'ink_board.dart';

/// A pure, reusable canvas for displaying document pages with non-destructive overlays.
/// Handles aspect ratio, layout math, and pan/zoom gestures.
class DocumentCanvas extends StatefulWidget {
  const DocumentCanvas({
    super.key,
    required this.pagePaths,
    this.inkController,
    this.annotateLayers = const [],
    this.watermarkLayers = const [],
    this.stampLayers = const [],
    this.selectedAnnotateBytesPath,
    this.selectedWatermarkText,
    this.selectedStampId,
    this.onAnnotateSelect,
    this.onAnnotateUpdate,
    this.onSignatureSelect,
    this.onWatermarkSelect,
    this.onWatermarkSelected,
    this.onWatermarkLayerUpdate,
    this.onStampSelect,
    this.onStampSelected,
    this.onStampLayerUpdate,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.pageController,
    this.initialPage = 0,
    this.onPageChanged,
  });

  final List<String> pagePaths;
  final InkController? inkController;
  final List<AnnotateLayer> annotateLayers;
  final List<WatermarkLayer> watermarkLayers;
  final List<StampLayer> stampLayers;
  final String? selectedAnnotateBytesPath;
  final String? selectedWatermarkText;
  final String? selectedStampId;
  final void Function(AnnotateLayer layer)? onAnnotateSelect;
  final void Function(int pageIndex, AnnotateLayer newLayer)? onAnnotateUpdate;
  final VoidCallback? onSignatureSelect;
  final VoidCallback? onWatermarkSelect;
  final void Function(WatermarkLayer layer)? onWatermarkSelected;
  final void Function(int pageIndex, WatermarkLayer layer)? onWatermarkLayerUpdate;
  final VoidCallback? onStampSelect;
  final void Function(StampLayer layer)? onStampSelected;
  final void Function(int pageIndex, StampLayer layer)? onStampLayerUpdate;
  final ScrollPhysics physics;
  final PageController? pageController;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  @override
  State<DocumentCanvas> createState() => _DocumentCanvasState();
}

class _DocumentCanvasState extends State<DocumentCanvas> {
  late final PageController _pageController;
  final bool _ownsController;
  late int _currentPage;

  int get _lastIndex => widget.pagePaths.isEmpty ? 0 : widget.pagePaths.length - 1;

  _DocumentCanvasState() : _ownsController = false;

  @override
  void initState() {
    super.initState();
    final int requested = widget.initialPage;
    _currentPage = requested < 0 ? 0 : (requested > _lastIndex ? _lastIndex : requested);
    if (widget.pageController != null) {
      _pageController = widget.pageController!;
    } else {
      _pageController = PageController(initialPage: _currentPage);
    }
  }

  @override
  void dispose() {
    if (_ownsController || widget.pageController == null) {
      _pageController.dispose();
    }
    super.dispose();
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
      child: PageView.builder(
        controller: _pageController,
        physics: widget.physics,
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
            selectedAnnotateBytesPath: widget.selectedAnnotateBytesPath,
            onAnnotateSelect: widget.onAnnotateSelect,
            onAnnotateUpdate: widget.onAnnotateUpdate,
            onSignatureSelect: widget.onSignatureSelect,
            watermarkLayers: widget.watermarkLayers,
            selectedWatermarkText: widget.selectedWatermarkText,
            onWatermarkSelect: widget.onWatermarkSelect,
            onWatermarkSelected: widget.onWatermarkSelected,
            onWatermarkLayerUpdate: widget.onWatermarkLayerUpdate,
            stampLayers: widget.stampLayers,
            selectedStampId: widget.selectedStampId,
            onStampSelect: widget.onStampSelect,
            onStampSelected: widget.onStampSelected,
            onStampLayerUpdate: widget.onStampLayerUpdate,
          );
        },
      ),
    );
  }
}

// === _PageWithInk: The core page renderer with overlays ===
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
  final void Function(int pageIndex, AnnotateLayer newLayer)? onAnnotateUpdate;
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
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

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

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: SizedBox(
                    width: iw,
                    height: ih,
                    child: Image.file(
                      File(widget.pagePath),
                      fit: BoxFit.fill,
                      errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: widget.textSecondary, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _transformController,
                builder: (context, child) {
                  return Transform(
                    transform: _transformController.value,
                    child: Stack(
                      children: [
                        if (widget.controller != null)
                          InkOverlayPage(
                            controller: widget.controller!,
                            onSelected: widget.onSignatureSelect,
                            pageIndex: widget.pageIndex,
                            imgW: iw, imgH: ih, iw: iw, ih: ih, dx: dx, dy: dy,
                            accent: widget.accent,
                            transformController: _transformController,
                          ),
                        if (widget.annotateLayers.isNotEmpty)
                          AnnotateOverlayPage(
                            layers: widget.annotateLayers,
                            pageIndex: widget.pageIndex,
                            iw: iw, ih: ih, dx: dx, dy: dy,
                            accent: widget.accent,
                            selectedBytesPath: widget.selectedAnnotateBytesPath,
                            onSelect: (layer) => widget.onAnnotateSelect?.call(layer),
                            transformController: _transformController,
                            onDrag: (layer, dxDelta, dyDelta) {
                              widget.onAnnotateUpdate?.call(widget.pageIndex, AnnotateLayer(
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
                            iw: iw, ih: ih, dx: dx, dy: dy,
                            accent: widget.accent,
                            selectedText: widget.selectedWatermarkText,
                            onSelect: (layer) { widget.onWatermarkSelected?.call(layer); widget.onWatermarkSelect?.call(); },
                            transformController: _transformController,
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
                            iw: iw, ih: ih, dx: dx, dy: dy,
                            accent: widget.accent,
                            selectedId: widget.selectedStampId,
                            onSelect: (layer) { widget.onStampSelected?.call(layer); widget.onStampSelect?.call(); },
                            transformController: _transformController,
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
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
