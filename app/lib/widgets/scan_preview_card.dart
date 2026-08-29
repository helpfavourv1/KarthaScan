import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class ScanPreviewCard extends StatefulWidget {
  const ScanPreviewCard({
    super.key,
    required this.pagePaths,
    this.signatureBytes,
    this.signatureLayers = const [],
    this.signatureMode = false,
    this.onShare,
    this.onSignatureLayerUpdate,
    this.onSignThisPage,
    this.onCopyToAllPages,
    this.onClearThisPage,
    this.onClearAllLayers,
    this.initialPage = 0,
    this.onPageChanged,
  });

  final List<String> pagePaths;
  final Uint8List? signatureBytes;
  final List<SignatureLayer> signatureLayers;
  final bool signatureMode;
  final VoidCallback? onShare;
  final void Function(int pageIndex, SignatureLayer layer)? onSignatureLayerUpdate;
  final void Function(int pageIndex)? onSignThisPage;
  final void Function(SignatureLayer layer)? onCopyToAllPages;
  final void Function(int pageIndex)? onClearThisPage;
  final VoidCallback? onClearAllLayers;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  @override
  State<ScanPreviewCard> createState() => _ScanPreviewCardState();
}

class _ScanPreviewCardState extends State<ScanPreviewCard> {
  late final PageController _pageController;
  late int _currentPage;
  double _sigAspect = 2.0;
  late Color _textSecondary;

  int get _lastIndex => widget.pagePaths.isEmpty ? 0 : widget.pagePaths.length - 1;

  @override
  void initState() {
    super.initState();
    final int requested = widget.initialPage;
    _currentPage = requested < 0 ? 0 : (requested > _lastIndex ? _lastIndex : requested);
    _pageController = PageController(initialPage: _currentPage);
    _loadSigAspect();
  }

  void _loadSigAspect() {
    if (widget.signatureBytes == null) return;
    final decoded = img.decodePng(widget.signatureBytes!);
    if (decoded != null && decoded.height > 0) {
      _sigAspect = (decoded.width / decoded.height).clamp(0.1, 10.0).toDouble();
    }
  }

  @override
  void didUpdateWidget(covariant ScanPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.signatureBytes != oldWidget.signatureBytes) {
      _loadSigAspect();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  SignatureLayer? _getLayerForPage(int pageIndex) {
    for (final layer in widget.signatureLayers) {
      if (layer.pageIndex == pageIndex) return layer;
    }
    return null;
  }

  Widget _buildSignatureControls() {
    final layer = _getLayerForPage(_currentPage);
    if (!widget.signatureMode) return const SizedBox.shrink();
    if (widget.signatureBytes == null) return const SizedBox.shrink();
    if (layer == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ActionChip(
              avatar: const Icon(Icons.draw_outlined, size: 14),
              label: const Text('Sign this page too', style: TextStyle(fontSize: 11)),
              onPressed: () => widget.onSignThisPage?.call(_currentPage),
            ),
          ],
        ),
      );
    }
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
                    widget.onSignatureLayerUpdate?.call(_currentPage, SignatureLayer(
                      pageIndex: layer.pageIndex,
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
                    widget.onSignatureLayerUpdate?.call(_currentPage, SignatureLayer(
                      pageIndex: layer.pageIndex,
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
                onPressed: () => widget.onCopyToAllPages?.call(layer),
                child: const Text('Copy to all', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => widget.onClearThisPage?.call(_currentPage),
                child: const Text('Clear this', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => widget.onClearAllLayers?.call(),
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
                final layer = _getLayerForPage(index);
                return _PageWithSignature(
                  pagePath: widget.pagePaths[index],
                  signatureBytes: widget.signatureBytes,
                  layer: layer,
                  sigAspect: _sigAspect,
                  textSecondary: textSecondary,
                  onUpdate: (newLayer) => widget.onSignatureLayerUpdate?.call(index, newLayer),
                  signatureMode: widget.signatureMode,
                );
              },
            ),
          ),
          _buildSignatureControls(),
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

class _PageWithSignature extends StatefulWidget {
  const _PageWithSignature({
    required this.pagePath,
    required this.signatureBytes,
    required this.layer,
    required this.sigAspect,
    required this.textSecondary,
    required this.onUpdate,
    required this.signatureMode,
  });

  final String pagePath;
  final Uint8List? signatureBytes;
  final SignatureLayer? layer;
  final double sigAspect;
  final Color textSecondary;
  final void Function(SignatureLayer) onUpdate;
  final bool signatureMode;

  @override
  State<_PageWithSignature> createState() => _PageWithSignatureState();
}

class _PageWithSignatureState extends State<_PageWithSignature> {
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

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                panEnabled: !widget.signatureMode,
                scaleEnabled: !widget.signatureMode,
                child: Center(
                  child: Image.file(
                    File(widget.pagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: widget.textSecondary, size: 48),
                  ),
                ),
              ),
            ),
            if (widget.signatureBytes != null && widget.layer != null)
              Builder(builder: (context) {
                final layer = widget.layer!;
                final sigW = iw * 0.28 * layer.placement.scale;
                final sigH = sigW / widget.sigAspect;
                return Positioned(
                  left: dx + layer.placement.pctX * iw - sigW / 2,
                  top: dy + layer.placement.pctY * ih - sigH / 2,
                  child: IgnorePointer(
                    ignoring: !widget.signatureMode,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) {
                        final newPctX = (layer.placement.pctX + d.delta.dx / iw).clamp(0.0, 1.0);
                        final newPctY = (layer.placement.pctY + d.delta.dy / ih).clamp(0.0, 1.0);
                        widget.onUpdate(SignatureLayer(
                          pageIndex: layer.pageIndex,
                          placement: SignaturePlacement(
                            pctX: newPctX,
                            pctY: newPctY,
                            rotationDegrees: layer.placement.rotationDegrees,
                            scale: layer.placement.scale,
                          ),
                        ));
                      },
                      child: Transform.rotate(
                        angle: layer.placement.rotationDegrees * 3.14159 / 180,
                        child: Opacity(
                          opacity: 0.9,
                          child: Image.memory(widget.signatureBytes!, width: sigW, height: sigH, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
