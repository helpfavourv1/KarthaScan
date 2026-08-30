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
    this.onShare,
    this.onAnnotateLayerUpdate,
    this.onAnnotateThisPage,
    this.onCopyAnnotateToAllPages,
    this.onClearAnnotatePage,
    this.onClearAllAnnotateLayers,
    this.initialPage = 0,
    this.onPageChanged,
  });

  final List<String> pagePaths;
  final InkController? inkController;
  final List<AnnotateLayer> annotateLayers;
  final VoidCallback? onShare;
  final void Function(int pageIndex, AnnotateLayer layer)? onAnnotateLayerUpdate;
  final void Function(int pageIndex)? onAnnotateThisPage;
  final void Function(AnnotateLayer layer)? onCopyAnnotateToAllPages;
  final void Function(int pageIndex)? onClearAnnotatePage;
  final VoidCallback? onClearAllAnnotateLayers;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  @override
  State<ScanPreviewCard> createState() => _ScanPreviewCardState();
}

class _ScanPreviewCardState extends State<ScanPreviewCard> {
  late final PageController _pageController;
  late int _currentPage;
  late Color _textSecondary;
  String? _selectedAnnotateBytesPath;

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

  Widget _buildAnnotateControls() {
    final pageLayers = widget.annotateLayers.where((l) => l.pageIndex == _currentPage).toList();
    if (pageLayers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ActionChip(
              avatar: const Icon(Icons.draw_outlined, size: 14),
              label: const Text('Annotate this page', style: TextStyle(fontSize: 11)),
              onPressed: () => widget.onAnnotateThisPage?.call(_currentPage),
            ),
          ],
        ),
      );
    }
    final layer = pageLayers.firstWhere((l) => l.bytesPath == _selectedAnnotateBytesPath, orElse: () => pageLayers.first);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      color: _textSecondary.withValues(alpha: 0.05),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Rotate', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: layer.placement.rotationDegrees,
                  min: -180,
                  max: 180,
                  onChanged: (v) {
                    widget.onAnnotateLayerUpdate?.call(_currentPage, AnnotateLayer(
                      pageIndex: layer.pageIndex,
                      bytesPath: layer.bytesPath,
                      placement: SignaturePlacement(
                        pctX: layer.placement.pctX,
                        pctY: layer.placement.pctY,
                        rotationDegrees: v,
                        scale: layer.placement.scale,
                      ),
                    ));
                  },
                ),
              ),
              Text('${layer.placement.rotationDegrees.round()}°', style: const TextStyle(fontSize: 11)),
            ],
          ),
          Row(
            children: [
              const Text('Scale', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: layer.placement.scale,
                  min: 0.3,
                  max: 3.0,
                  onChanged: (v) {
                    widget.onAnnotateLayerUpdate?.call(_currentPage, AnnotateLayer(
                      pageIndex: layer.pageIndex,
                      bytesPath: layer.bytesPath,
                      placement: SignaturePlacement(
                        pctX: layer.placement.pctX,
                        pctY: layer.placement.pctY,
                        rotationDegrees: layer.placement.rotationDegrees,
                        scale: v,
                      ),
                    ));
                  },
                ),
              ),
              Text('${layer.placement.scale.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 11)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => widget.onCopyAnnotateToAllPages?.call(layer),
                child: const Text('Copy to all', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => widget.onClearAnnotatePage?.call(_currentPage),
                child: const Text('Clear this', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => widget.onClearAllAnnotateLayers?.call(),
                child: const Text('Clear all', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    _textSecondary = textSecondary;
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
          Expanded(
            child: PageView.builder(
              controller: _pageController,
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
                );
              },
            ),
          ),
          _buildAnnotateControls(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: surface,
            child: Row(
              children: <Widget>[
                Text('${_currentPage + 1} / ${widget.pagePaths.length}', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize)),
                const Spacer(),
                if (widget.onShare != null) IconButton(onPressed: widget.onShare, icon: Icon(Icons.ios_share, color: accent), tooltip: l10n.shareTooltip),
              ],
            ),
          ),
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

        final hasOverlays = (widget.controller?.hasInks ?? false) || widget.annotateLayers.isNotEmpty;
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
          ],
        );
      },
    );
  }
}
