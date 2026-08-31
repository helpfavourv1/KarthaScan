import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../core/models/scan_document.dart';
import '../core/models/page_transform.dart';
import '../core/models/signature_placement.dart';
import '../core/services/export_service.dart' show FilterType;
import '../core/services/filter_service.dart';
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
    this.pageTransforms = const {},
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
  final Map<int, PageTransform> pageTransforms;

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
            pageTransforms: widget.pageTransforms,
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
    this.pageTransforms = const {},
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
  final Map<int, PageTransform> pageTransforms;

  @override
  State<_PageWithInk> createState() => _PageWithInkState();
}

class _PageWithInkState extends State<_PageWithInk> {
  double _pageAspect = 0.75;
  final TransformationController _transformController = TransformationController();
  Uint8List? _filteredBytes;

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
      final transform = widget.pageTransforms[widget.pageIndex];
      if (transform != null && decoded != null && (transform.cropRect != null || transform.resizeWidth != null || transform.filter != FilterType.none)) {
        img.Image processed = decoded;
        if (transform.cropRect != null && transform.cropRect!.width > 0 && transform.cropRect!.height > 0) {
          final r = transform.cropRect!;
          processed = img.copyCrop(processed, x: r.left.round(), y: r.top.round(), width: r.width.round(), height: r.height.round());
        }
        if (transform.resizeWidth != null && transform.resizeHeight != null) {
          processed = img.copyResize(processed, width: transform.resizeWidth!, height: transform.resizeHeight!);
        }
        if (transform.filter != FilterType.none) {
          processed = FilterService.applyToImage(processed, transform.filter);
        }
        final processedBytes = Uint8List.fromList(img.encodeJpg(processed, quality: 85));
        if (mounted) setState(() => _filteredBytes = processedBytes);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final transform = widget.pageTransforms[widget.pageIndex];
        final rotationTurns = transform?.rotationTurns ?? 0;
        final isRotated = (rotationTurns % 2 != 0);
        final cropRect = transform?.cropRect;
        final resizeW = transform?.resizeWidth;
        final resizeH = transform?.resizeHeight;

        double effectiveAspect = _pageAspect;
        if (resizeW != null && resizeH != null && resizeH > 0) {
          effectiveAspect = resizeW / resizeH;
        } else if (cropRect != null && cropRect.width > 0 && cropRect.height > 0) {
          effectiveAspect = cropRect.width / cropRect.height;
        }
        final visualAspect = isRotated ? (1.0 / effectiveAspect) : effectiveAspect;

        double visualW = constraints.maxWidth;
        double visualH = visualW / visualAspect;
        if (visualH > constraints.maxHeight) {
          visualH = constraints.maxHeight;
          visualW = visualH * visualAspect;
        }

        final originalW = isRotated ? visualH : visualW;
        final originalH = isRotated ? visualW : visualH;

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: SizedBox(
                    width: visualW,
                    height: visualH,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: RotatedBox(
                        quarterTurns: rotationTurns,
                        child: SizedBox(
                          width: originalW,
                          height: originalH,
                          child: _filteredBytes != null
                              ? Image.memory(_filteredBytes!, fit: BoxFit.fill)
                              : Image.file(
                                  File(widget.pagePath),
                                  fit: BoxFit.fill,
                                  errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: widget.textSecondary, size: 48),
                                ),
                        ),
                      ),
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
                    child: Center(
                      child: SizedBox(
                        width: visualW,
                        height: visualH,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: RotatedBox(
                            quarterTurns: rotationTurns,
                            child: SizedBox(
                              width: originalW,
                              height: originalH,
                              child: Stack(
                                children: [
                                  if (widget.controller != null)
                                    InkOverlayPage(
                                      controller: widget.controller!,
                                      onSelected: widget.onSignatureSelect,
                                      pageIndex: widget.pageIndex,
                                      imgW: originalW, imgH: originalH, iw: originalW, ih: originalH, dx: 0, dy: 0,
                                      accent: widget.accent,
                                      transformController: _transformController,
                                    ),
                                  if (widget.annotateLayers.isNotEmpty)
                                    AnnotateOverlayPage(
                                      layers: widget.annotateLayers,
                                      pageIndex: widget.pageIndex,
                                      iw: originalW, ih: originalH, dx: 0, dy: 0,
                                      accent: widget.accent,
                                      selectedBytesPath: widget.selectedAnnotateBytesPath,
                                      onSelect: (layer) => widget.onAnnotateSelect?.call(layer),
                                      transformController: _transformController,
                                      onDrag: (layer, dxDelta, dyDelta) {
                                        widget.onAnnotateUpdate?.call(widget.pageIndex, AnnotateLayer(
                                          pageIndex: layer.pageIndex,
                                          bytesPath: layer.bytesPath,
                                          placement: SignaturePlacement(
                                            pctX: (layer.placement.pctX + dxDelta / originalW).clamp(0.0, 1.0),
                                            pctY: (layer.placement.pctY + dyDelta / originalH).clamp(0.0, 1.0),
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
                                      iw: originalW, ih: originalH, dx: 0, dy: 0,
                                      accent: widget.accent,
                                      selectedText: widget.selectedWatermarkText,
                                      onSelect: (layer) { widget.onWatermarkSelected?.call(layer); widget.onWatermarkSelect?.call(); },
                                      transformController: _transformController,
                                      onDrag: (layer, dxDelta, dyDelta) {
                                        widget.onWatermarkLayerUpdate?.call(widget.pageIndex, layer.copyWith(
                                          placement: SignaturePlacement(
                                            pctX: (layer.placement.pctX + dxDelta / originalW).clamp(0.0, 1.0),
                                            pctY: (layer.placement.pctY + dyDelta / originalH).clamp(0.0, 1.0),
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
                                      iw: originalW, ih: originalH, dx: 0, dy: 0,
                                      accent: widget.accent,
                                      selectedId: widget.selectedStampId,
                                      onSelect: (layer) { widget.onStampSelected?.call(layer); widget.onStampSelect?.call(); },
                                      transformController: _transformController,
                                      onDrag: (layer, dxDelta, dyDelta) {
                                        widget.onStampLayerUpdate?.call(widget.pageIndex, layer.copyWith(
                                          placement: SignaturePlacement(
                                            pctX: (layer.placement.pctX + dxDelta / originalW).clamp(0.0, 1.0),
                                            pctY: (layer.placement.pctY + dyDelta / originalH).clamp(0.0, 1.0),
                                            rotationDegrees: layer.placement.rotationDegrees,
                                            scale: layer.placement.scale,
                                          ),
                                        ));
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
