import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/services/local_storage.dart';
import '../core/services/ad_pacing_service.dart';
import '../core/services/interstitial_ad_service.dart';
import '../core/utils/constants.dart';
import '../core/utils/seal_draw.dart';
import 'signature_canvas.dart';
import '../l10n/app_localizations.dart';

/// Which editor currently owns the tray preview screen.
enum TrayEditMode { none, signature, annotate, watermark, text, note, date, checkbox, seal, fill }

/// Which kind of overlay layer the shared editor is editing.
enum LayerType { signature, annotate, watermark, text, note, date, checkbox, seal }

/// Multi-ink signature controller.
/// Lifted verbatim from export_screen.dart and shared by both screens.
/// Persistence is delegated to the owner via [onChange] — the export screen
/// sets it to null (session-only); the tray hooks it to ScanProvider.
class InkController {
  InkController({this.onChange});

  final void Function()? onChange;

  final Map<String, SignatureInk> inks = {};
  final Map<String, Map<int, SignaturePlacement>> inkPlacements = {};
  String? activeInkId;
  String? editInkId;

  /// True once a signature was drawn and its ad has not been shown yet. The ad
  /// appears when the editor closes, not while the person is still placing it.
  bool signatureAdPending = false;

  void showSignatureAdIfPending() {
    if (!signatureAdPending) return;
    signatureAdPending = false;
    unawaited(InterstitialAdService.instance.showAfterSignature());
  }

  void _notify() => onChange?.call();

  void seed(ScanDocument doc) {
    if (doc.signatureInks.isEmpty && doc.signatureLayers.isEmpty) return;
    for (final ink in doc.signatureInks) {
      inks[ink.id] = ink;
    }
    for (final layer in doc.signatureLayers) {
      inkPlacements.putIfAbsent(layer.inkId, () => {})[layer.pageIndex] = layer.placement;
    }
    activeInkId ??= inks.keys.isEmpty ? null : inks.keys.first;
    _notify();
  }

  /// Replaces controller state with the document's persisted signature
  /// state (used by undo/redo restore). Does NOT trigger onChange.
  void restoreFrom(ScanDocument doc) {
    inks.clear();
    inkPlacements.clear();
    for (final ink in doc.signatureInks) {
      inks[ink.id] = ink;
    }
    for (final layer in doc.signatureLayers) {
      inkPlacements.putIfAbsent(layer.inkId, () => {})[layer.pageIndex] = layer.placement;
    }
    if (activeInkId == null || !inks.containsKey(activeInkId)) {
      activeInkId = inks.keys.isEmpty ? null : inks.keys.first;
    }
    if (editInkId != null && !inks.containsKey(editInkId)) editInkId = null;
  }

  Future<String?> addInk(BuildContext context, LocalStorageService localStorage) async {
    Uint8List? bytes;
    final saved = await localStorage.loadSignaturePng();
    if (saved != null && context.mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).signatureTitle),
          content: Text(AppLocalizations.of(context).signatureChoiceMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'saved'), child: Text(AppLocalizations.of(ctx).useSavedSignature)),
            TextButton(onPressed: () => Navigator.pop(ctx, 'draw'), child: Text(AppLocalizations.of(ctx).drawNewSignature)),
          ],
        ),
      );
      if (choice == 'saved') bytes = saved;
    }
    if (bytes == null && context.mounted) {
      bytes = await showModalBottomSheet<Uint8List?>(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        builder: (context) => const InkSignatureSheet(),
      );
      if (bytes != null) {
        await localStorage.saveSignaturePng(bytes);
      }
    }
    if (bytes == null) return null;

    // Central signature-completion hook: covers export, fullscreen edit, tray, and scan-detail surfaces
    unawaited(AdPacingService.instance.recordSignature());
    signatureAdPending = true;

    final decoded = img.decodePng(bytes);
    final aspect = (decoded != null && decoded.height > 0)
        ? (decoded.width / decoded.height).clamp(0.1, 10.0).toDouble()
        : 2.0;
    final inkId = 'ink_${DateTime.now().microsecondsSinceEpoch}';
    inks[inkId] = SignatureInk(
      id: inkId,
      bytes: bytes,
      label: context.mounted ? AppLocalizations.of(context).signerLabel('${inks.length + 1}') : 'Signer ${inks.length + 1}',
      aspect: aspect,
    );
    activeInkId = inkId;
    editInkId = inkId;
    _notify();
    return inkId;
  }

  /// Puts the active signature on [pageIndex]. If that signature is already on
  /// the page, a second independent copy is placed (same picture, new id) so a
  /// page can be signed in more than one spot and each copy moves on its own.
  void placeOnPage(int pageIndex) {
    final inkId = activeInkId;
    if (inkId == null) return;
    final SignatureInk? source = inks[inkId];
    final bool alreadyThere = inkPlacements[inkId]?.containsKey(pageIndex) ?? false;
    if (alreadyThere && source != null) {
      final String copyId = 'ink_${DateTime.now().microsecondsSinceEpoch}_${_copySeq++}';
      final SignaturePlacement at = inkPlacements[inkId]![pageIndex]!;
      inks[copyId] = source.copyWith(id: copyId, label: '${source.label} +');
      inkPlacements[copyId] = {
        pageIndex: SignaturePlacement(
          pctX: at.pctX,
          pctY: (at.pctY + 0.15).clamp(0.05, 0.95).toDouble(),
          rotationDegrees: at.rotationDegrees,
          scale: at.scale,
        ),
      };
      activeInkId = copyId;
      editInkId = copyId;
      _notify();
      return;
    }
    inkPlacements.putIfAbsent(inkId, () => {});
    inkPlacements[inkId]!.putIfAbsent(pageIndex, () => const SignaturePlacement(pctX: 0.5, pctY: 0.35));
    editInkId = inkId;
    _notify();
  }

  int _copySeq = 0;

  void removeInk(String inkId) {
    inks.remove(inkId);
    inkPlacements.remove(inkId);
    if (editInkId == inkId) editInkId = null;
    if (activeInkId == inkId) activeInkId = inks.keys.isEmpty ? null : inks.keys.first;
    _notify();
  }

  void clearAll() {
    inkPlacements.clear();
    editInkId = null;
    _notify();
  }

  void setActiveInk(String? inkId) {
    activeInkId = inkId;
    _notify();
  }

  void setEditInk(String? inkId) {
    editInkId = inkId;
    _notify();
  }

  void updatePlacement(String inkId, int pageIndex, SignaturePlacement placement) {
    inkPlacements.putIfAbsent(inkId, () => {});
    inkPlacements[inkId]![pageIndex] = placement;
    _notify();
  }

  void removePlacement(String inkId, int pageIndex) {
    inkPlacements[inkId]?.remove(pageIndex);
    _notify();
  }

  void copyToAllPages(String inkId, int sourcePageIndex, int pageCount) {
    final src = inkPlacements[inkId]?[sourcePageIndex];
    if (src == null) return;
    for (int i = 0; i < pageCount; i++) {
      inkPlacements[inkId]![i] = src;
    }
    _notify();
  }

  List<SignatureLayer> get layers {
    final result = <SignatureLayer>[];
    inkPlacements.forEach((inkId, pages) {
      pages.forEach((pg, pl) =>
          result.add(SignatureLayer(pageIndex: pg, placement: pl, inkId: inkId)));
    });
    return result;
  }

  bool get hasInks => inks.isNotEmpty;
  int get totalPlacements => inkPlacements.values.fold<int>(0, (s, m) => s + m.length);
}

// === InkOverlayPage: renders the ink stack for one page, with drag + select ===

class InkOverlayPage extends StatelessWidget {
  const InkOverlayPage({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.imgW,
    required this.imgH,
    required this.iw,
    required this.ih,
    required this.dx,
    required this.dy,
    required this.accent,
    this.onSelected,
    this.transformController,
  });

  final InkController controller;
  final VoidCallback? onSelected;
  final int pageIndex;
  final double imgW, imgH, iw, ih, dx, dy;
  final Color accent;
  final TransformationController? transformController;

  @override
  Widget build(BuildContext context) {
    final onSelectedCallback = onSelected;
    return Stack(
      children: [
        for (final entry in controller.inkPlacements.entries)
          Builder(builder: (context) {
            final ink = controller.inks[entry.key];
            final pl = entry.value[pageIndex];
            if (ink == null || pl == null) return const SizedBox.shrink();
            final sigW = iw * 0.28 * pl.scale;
            final sigH = sigW / ink.aspect;
            final isEdit = entry.key == controller.editInkId;
            return Positioned(
              left: dx + pl.pctX * iw - sigW / 2,
              top: dy + pl.pctY * ih - sigH / 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { controller.setEditInk(entry.key); onSelectedCallback?.call(); },
                onPanStart: (_) {},
                onPanUpdate: (d) {
                  final scale = transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                  controller.updatePlacement(
                  entry.key,
                  pageIndex,
                  SignaturePlacement(
                    pctX: (pl.pctX + (d.delta.dx / scale) / iw).clamp(0.0, 1.0),
                    pctY: (pl.pctY + (d.delta.dy / scale) / ih).clamp(0.0, 1.0),
                    rotationDegrees: pl.rotationDegrees,
                    scale: pl.scale,
                  ),
                  );
                },
                child: Container(
                                    decoration: isEdit
                      ? BoxDecoration(
                          border: Border.all(color: accent, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: Transform.rotate(
                    angle: pl.rotationDegrees * 3.14159 / 180,
                    child: Image.memory(ink.bytes,
                        width: sigW, height: sigH, fit: BoxFit.contain),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

// === AnnotateOverlayPage: renders annotate layers for one page ===

class AnnotateOverlayPage extends StatefulWidget {
  const AnnotateOverlayPage({
    super.key,
    required this.layers,
    required this.pageIndex,
    required this.iw,
    required this.ih,
    required this.dx,
    required this.dy,
    required this.accent,
    required this.selectedId,
    required this.onSelect,
    required this.onDrag,
    this.onSelected,
    this.transformController,
  });

  final List<AnnotateLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedId;
  final void Function(AnnotateLayer layer) onSelect;
  final void Function(AnnotateLayer layer, double dxDelta, double dyDelta) onDrag;
  final VoidCallback? onSelected;
  final TransformationController? transformController;

  @override
  State<AnnotateOverlayPage> createState() => _AnnotateOverlayPageState();
}

class _AnnotateOverlayPageState extends State<AnnotateOverlayPage> {
  final Map<String, Uint8List> _cache = {};
  final Map<String, double> _aspectCache = {};
  final Set<String> _loading = <String>{};

  /// Reads an annotation picture without blocking the screen. The size comes
  /// from the file header, so the picture is not decoded just to measure it.
  Future<void> _load(String path) async {
    if (!_loading.add(path)) return;
    Uint8List bytes = Uint8List(0);
    double? aspect;
    try {
      final file = File(path);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
        final img.DecodeInfo? info = img.findDecoderForData(bytes)?.startDecode(bytes);
        if (info != null && info.height > 0) aspect = info.width / info.height;
      }
    } catch (_) {}
    _loading.remove(path);
    if (!mounted) return;
    setState(() {
      _cache[path] = bytes;
      if (aspect != null) _aspectCache[path] = aspect;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final layer in widget.layers.where((l) => l.pageIndex == widget.pageIndex))
          Builder(builder: (context) {
            final Uint8List? bytes = _cache[layer.bytesPath];
            if (bytes == null) {
              _load(layer.bytesPath);
              return const SizedBox.shrink();
            }
            if (bytes.isEmpty) return const SizedBox.shrink();
            final sigW = widget.iw * 0.28 * layer.placement.scale;
            final aspect = _aspectCache[layer.bytesPath] ?? 2.0;
            final sigH = sigW / aspect;
            final isSelected = layer.id == widget.selectedId;
            return Positioned(
              left: widget.dx + layer.placement.pctX * widget.iw - sigW / 2,
              top: widget.dy + layer.placement.pctY * widget.ih - sigH / 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { widget.onSelect(layer); widget.onSelected?.call(); },
                onPanStart: (_) {},
                onPanUpdate: (d) {
                  final scale = widget.transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                  widget.onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                },
                child: Container(
                                    decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(color: widget.accent, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: Transform.rotate(
                    angle: layer.placement.rotationDegrees * 3.14159 / 180,
                    child: Image.memory(bytes,
                        width: sigW, height: sigH, fit: BoxFit.contain),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}


// === WatermarkOverlayPage: renders watermark text as live overlay ===

class WatermarkOverlayPage extends StatelessWidget {
  const WatermarkOverlayPage({
    super.key,
    required this.layers,
    required this.pageIndex,
    required this.iw,
    required this.ih,
    required this.dx,
    required this.dy,
    required this.accent,
    required this.selectedText,
    required this.onSelect,
    required this.onDrag,
    this.onSelected,
    this.transformController,
  });

  final List<WatermarkLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedText;
  final void Function(WatermarkLayer layer) onSelect;
  final void Function(WatermarkLayer layer, double dxDelta, double dyDelta) onDrag;
  final VoidCallback? onSelected;
  final TransformationController? transformController;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final layer in layers.where((l) => l.pageIndex == pageIndex))
          Builder(builder: (context) {
            final isSelected = layer.id == selectedText;
            final fontWeight = layer.bold ? FontWeight.w700 : FontWeight.w400;
            final fontStyle = layer.italic ? FontStyle.italic : FontStyle.normal;
            final decoration = layer.underline ? TextDecoration.underline : TextDecoration.none;
            final color = Color(layer.color).withValues(alpha: layer.opacity);
            final shadows = layer.shadowColor != null
                ? [Shadow(offset: Offset(layer.shadowOffsetX, layer.shadowOffsetY), color: Color(layer.shadowColor!), blurRadius: 2)]
                : null;
            final boxW = iw * 0.30 * layer.placement.scale;
            final boxH = iw * 0.10 * layer.placement.scale;
            return Positioned(
              left: dx + layer.placement.pctX * iw - boxW / 2,
              top: dy + layer.placement.pctY * ih - boxH / 2,
              width: boxW,
              height: boxH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { onSelect(layer); onSelected?.call(); },
                onPanStart: (_) {},
                onPanUpdate: (d) {
                  final scale = transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                  onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                },
                child: Container(
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(color: accent, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Transform.rotate(
                      angle: layer.placement.rotationDegrees * 3.14159 / 180,
                      child: Text(
                        layer.text,
                        style: TextStyle(
                          fontSize: 100,
                          fontWeight: fontWeight,
                          fontStyle: fontStyle,
                          fontFamily: layer.fontFamily,
                          color: color,
                          decoration: decoration,
                          shadows: shadows,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}


// === StampOverlayPage: renders text stamps as live overlay ===

class _CheckboxPainter extends CustomPainter {
  _CheckboxPainter({required this.shape, required this.boxColor, required this.tickColor, required this.checked, required this.opacity});
  final String shape;
  final Color boxColor;
  final Color tickColor;
  final bool checked;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final box = Paint()
      ..color = boxColor.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.067;
    if (shape == 'circle') {
      canvas.drawCircle(Offset(s / 2, s / 2), s / 2 - s * 0.067, box);
    } else {
      final radius = shape == 'rounded' ? Radius.circular(s * 0.1) : Radius.zero;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.033, s * 0.033, s - s * 0.067, s - s * 0.067), radius), box);
    }
    if (checked) {
      final check = Paint()
        ..color = tickColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()
        ..moveTo(s * 0.25, s * 0.54)
        ..lineTo(s * 0.44, s * 0.73)
        ..lineTo(s * 0.77, s * 0.31);
      canvas.drawPath(path, check);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckboxPainter old) =>
      old.shape != shape || old.boxColor != boxColor || old.tickColor != tickColor ||
      old.checked != checked || old.opacity != opacity;
}

class _SealPainter extends CustomPainter {
  _SealPainter(this.layer, {this.centerImage});
  final StampLayer layer;
  final ui.Image? centerImage;
  @override
  void paint(Canvas canvas, Size size) => drawSeal(canvas, size.width, layer, centerImage: centerImage);
  @override
  bool shouldRepaint(covariant _SealPainter old) => old.layer != layer || old.centerImage != centerImage;
}

class StampOverlayPage extends StatefulWidget {
  const StampOverlayPage({
    super.key,
    required this.layers,
    required this.pageIndex,
    required this.iw,
    required this.ih,
    required this.dx,
    required this.dy,
    required this.accent,
    required this.selectedId,
    required this.onSelect,
    required this.onDrag,
    this.onSelected,
    this.onDoubleTap,
    this.transformController,
  });

  final List<StampLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedId;
  final void Function(StampLayer layer) onSelect;
  final void Function(StampLayer layer, double dxDelta, double dyDelta) onDrag;
  final VoidCallback? onSelected;
  final void Function(StampLayer layer)? onDoubleTap;
  final TransformationController? transformController;

  @override
  State<StampOverlayPage> createState() => _StampOverlayPageState();
}

class _StampOverlayPageState extends State<StampOverlayPage> {
  final Map<String, ui.Image> _sealImageCache = {};

  @override
  void initState() {
    super.initState();
    _decodeSealImages();
  }

  @override
  void didUpdateWidget(StampOverlayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _decodeSealImages();
  }

  // Keyed by the picture itself, not only the layer id, so editing a seal's
  // centre image shows the new picture instead of the old cached one.
  String _sealKey(StampLayer layer) => '${layer.id}:${identityHashCode(layer.sealImageBytes)}';

  Future<void> _decodeSealImages() async {
    final sealLayers = widget.layers.where((l) => l.pageIndex == widget.pageIndex && l.kind == 'seal' && l.sealImageBytes != null);
    for (final layer in sealLayers) {
      final String cacheKey = _sealKey(layer);
      if (!_sealImageCache.containsKey(cacheKey)) {
        try {
          final codec = await ui.instantiateImageCodec(layer.sealImageBytes!);
          final frame = await codec.getNextFrame();
          if (mounted) {
            setState(() {
              _sealImageCache[cacheKey] = frame.image;
            });
          }
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    for (final image in _sealImageCache.values) {
      image.dispose();
    }
    _sealImageCache.clear();
    super.dispose();
  }

  /// Fill text: wraps inside its box and is drawn at its real size (a fraction of
  /// the page width), the same way the export draws it.
  Widget _flowFill(StampLayer layer, bool isSelected) {
    final double fontPx = layer.fillSize * widget.iw * layer.placement.scale;
    final double boxW = layer.boxWidth * widget.iw * layer.placement.scale;
    final double halo = fontPx * 0.03 < 1 ? 1 : fontPx * 0.03;
    final shadows = layer.halo
        ? [
            for (final o in <Offset>[Offset(halo, 0), Offset(-halo, 0), Offset(0, halo), Offset(0, -halo), Offset(halo, halo), Offset(-halo, -halo), Offset(halo, -halo), Offset(-halo, halo)])
              Shadow(offset: o, color: const Color(0xFFFFFFFF), blurRadius: 0),
          ]
        : null;
    final TextAlign align = layer.align == 'right' ? TextAlign.right : (layer.align == 'center' ? TextAlign.center : TextAlign.left);
    return Positioned(
      left: widget.dx + layer.placement.pctX * widget.iw,
      top: widget.dy + layer.placement.pctY * widget.ih,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () { widget.onSelect(layer); widget.onSelected?.call(); },
          onDoubleTap: widget.onDoubleTap == null ? null : () => widget.onDoubleTap!(layer),
          onPanStart: (_) {},
          onPanUpdate: (d) {
            final scale = widget.transformController?.value.getMaxScaleOnAxis() ?? 1.0;
            widget.onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
          },
          child: Transform.rotate(
            angle: layer.placement.rotationDegrees * 3.14159 / 180,
            child: Container(
              width: boxW,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: isSelected ? widget.accent : widget.accent.withValues(alpha: 0.35), width: isSelected ? 1.5 : 0.8),
              ),
              child: Text(
                layer.text.isEmpty ? ' ' : layer.text,
                textAlign: align,
                style: TextStyle(
                  fontSize: fontPx,
                  fontWeight: FontWeight.values.firstWhere((w) => w.value == layer.fontWeight, orElse: () => FontWeight.w400),
                  fontFamily: layer.fontFamily,
                  color: Color(layer.color).withValues(alpha: layer.opacity),
                  shadows: shadows,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final layer in widget.layers.where((l) => l.pageIndex == widget.pageIndex && (l.kind == 'text' || l.kind == 'note' || l.kind == 'date' || l.kind == 'checkbox' || l.kind == 'seal' || l.kind == 'fill')))
          Builder(builder: (context) {
            final isSelected = layer.id == widget.selectedId;
            if (layer.kind == 'checkbox') {
              final size = widget.iw * 0.15 * layer.placement.scale;
              return Positioned(
                left: widget.dx + layer.placement.pctX * widget.iw - size / 2,
                top: widget.dy + layer.placement.pctY * widget.ih - size / 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { widget.onSelect(layer); widget.onSelected?.call(); },
                  onPanStart: (_) {},
                  onPanUpdate: (d) {
                    final scale = widget.transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                    widget.onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                  },
                  child: Container(
                                        decoration: isSelected ? BoxDecoration(border: Border.all(color: widget.accent, width: 1.5), borderRadius: BorderRadius.circular(4)) : null,
                    child: Transform.rotate(
                      angle: layer.placement.rotationDegrees * 3.14159 / 180,
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: CustomPaint(
                          painter: _CheckboxPainter(
                            shape: layer.checkShape ?? 'rounded',
                            boxColor: Color(layer.boxColor ?? 0xFF111111),
                            tickColor: Color(layer.tickColor ?? 0xFF007AFF),
                            checked: layer.checked ?? true,
                            opacity: layer.opacity,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            if (layer.kind == 'seal') {
              final size = widget.iw * 0.25 * layer.placement.scale;
              final centerImage = _sealImageCache[_sealKey(layer)];
              return Positioned(
                left: widget.dx + layer.placement.pctX * widget.iw - size / 2,
                top: widget.dy + layer.placement.pctY * widget.ih - size / 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { widget.onSelect(layer); widget.onSelected?.call(); },
                  onPanStart: (_) {},
                  onPanUpdate: (d) {
                    final scale = widget.transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                    widget.onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                  },
                  child: Container(
                                        decoration: isSelected ? BoxDecoration(border: Border.all(color: widget.accent, width: 1.5), borderRadius: BorderRadius.circular(4)) : null,
                    child: Transform.rotate(
                      angle: layer.placement.rotationDegrees * 3.14159 / 180,
                      child: SizedBox(width: size, height: size, child: CustomPaint(painter: _SealPainter(layer, centerImage: centerImage))),
                    ),
                  ),
                ),
              );
            }
            if (layer.isFlowFill) return _flowFill(layer, isSelected);
            final boxW = widget.iw * 0.30 * layer.placement.scale;
            final boxH = widget.iw * 0.10 * layer.placement.scale;
            final color = Color(layer.color).withValues(alpha: layer.opacity);
            final isFill = layer.kind == 'fill';
            final shadows = layer.halo
                ? [
                    for (final o in const [Offset(2,0), Offset(-2,0), Offset(0,2), Offset(0,-2), Offset(2,2), Offset(-2,-2), Offset(2,-2), Offset(-2,2)])
                      Shadow(offset: o, color: const Color(0xFFFFFFFF), blurRadius: 0),
                  ]
                : null;
            return Positioned(
              left: widget.dx + layer.placement.pctX * widget.iw - boxW / 2,
              top: widget.dy + layer.placement.pctY * widget.ih - boxH / 2,
              width: boxW,
              height: boxH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { widget.onSelect(layer); widget.onSelected?.call(); },
                onPanStart: (_) {},
                onPanUpdate: (d) {
                  final scale = widget.transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                  widget.onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: layer.kind == 'note' && layer.noteBgColor != null ? Color(layer.noteBgColor!).withValues(alpha: layer.opacity) : null,
                    borderRadius: BorderRadius.circular(layer.kind == 'note' ? 16 : 4),
                    border: isFill
                        ? Border.all(color: const Color(0xFF007AFF), width: 1.5)
                        : (isSelected ? Border.all(color: widget.accent, width: 1.5) : null),
                  ),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Transform.rotate(
                      angle: layer.placement.rotationDegrees * 3.14159 / 180,
                      child: Text(
                        layer.text,
                        textAlign: layer.align == 'right' ? TextAlign.right : (layer.align == 'center' ? TextAlign.center : TextAlign.left),
                        style: TextStyle(
                          fontSize: 100,
                          fontWeight: FontWeight.values.firstWhere((w) => w.value == layer.fontWeight, orElse: () => FontWeight.w700),
                          fontFamily: layer.fontFamily,
                          color: color,
                          shadows: shadows,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

// === OverlayEditControls: shared rotate/scale/actions editor for every overlay layer ===
// Two compact rows, every control always visible (nothing scrolls or hides):
//   Row 1: steppers for rotate, scale and (when the layer has them) opacity and size.
//          On a very narrow screen the steppers wrap onto a second line instead of hiding.
//   Row 2: Edit (when available) / Copy to all / Remove / Clear all / Done.

class OverlayEditControls extends StatelessWidget {
  const OverlayEditControls({
    super.key,
    required this.layerType,
    required this.rotationDegrees,
    required this.scale,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onScaleDown,
    required this.onScaleUp,
    required this.onCopyAll,
    required this.onClearThis,
    required this.onRemove,
    required this.onClearAll,
    this.opacity,
    this.onOpacityDown,
    this.onOpacityUp,
    this.fontSize,
    this.onFontSizeDown,
    this.onFontSizeUp,
    this.onTools,
    this.onDone,
    this.showClearThis = false,
  });

  final LayerType layerType;
  /// Signatures only: "Clear this" removes the signature from this page, while
  /// Remove deletes it everywhere. For the other layers both do the same, so only Remove shows.
  final bool showClearThis;
  final double? opacity;
  final VoidCallback? onOpacityDown;
  final VoidCallback? onOpacityUp;
  final double? fontSize;
  final VoidCallback? onFontSizeDown;
  final VoidCallback? onFontSizeUp;
  final VoidCallback? onTools;
  final VoidCallback? onDone;
  final double rotationDegrees;
  final double scale;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onScaleDown;
  final VoidCallback onScaleUp;
  final VoidCallback onCopyAll;
  final VoidCallback onClearThis;
  final VoidCallback onRemove;
  final VoidCallback onClearAll;

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 26, height: 40, child: Center(child: Icon(icon, size: 20))),
      ),
    );
  }

  Widget _group(IconData minusIcon, VoidCallback onMinus, String value, IconData plusIcon, VoidCallback onPlus) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(minusIcon, onMinus),
        SizedBox(
          width: 34,
          child: Text(value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false),
        ),
        _stepBtn(plusIcon, onPlus),
      ],
    );
  }

  Widget _action(BuildContext context, IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = dark ? AppColors.accentDark : AppColors.accentLight;
    final bool hasOpacity = (layerType == LayerType.watermark || layerType == LayerType.text || layerType == LayerType.note || layerType == LayerType.date || layerType == LayerType.checkbox || layerType == LayerType.seal) &&
        opacity != null && onOpacityDown != null && onOpacityUp != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: 0,
            children: [
              _group(Icons.rotate_left, onRotateLeft, '${rotationDegrees.round()}°', Icons.rotate_right, onRotateRight),
              _group(Icons.remove, onScaleDown, '${scale.toStringAsFixed(1)}x', Icons.add, onScaleUp),
              if (hasOpacity) _group(Icons.remove, onOpacityDown!, '${(opacity! * 100).round()}%', Icons.add, onOpacityUp!),
              if (hasOpacity && fontSize != null && onFontSizeDown != null && onFontSizeUp != null)
                _group(Icons.remove, onFontSizeDown!, '${fontSize!.round()}pt', Icons.add, onFontSizeUp!),
            ],
          ),
          Row(
            children: [
              if (onTools != null) _action(context, Icons.brush, l10n.editLabel, onTools!),
              _action(context, Icons.copy_all, l10n.copyAll, onCopyAll),
              if (showClearThis) _action(context, Icons.layers_clear, l10n.clearThis, onClearThis),
              _action(context, Icons.delete_outline, l10n.commonRemove, onRemove),
              _action(context, Icons.layers_clear_outlined, l10n.clearAll, onClearAll),
              if (onDone != null) _action(context, Icons.check_circle, l10n.commonDone, onDone!, color: accent),
            ],
          ),
        ],
      ),
    );
  }
}

class InkCompactBar extends StatelessWidget {
  const InkCompactBar({
    super.key,
    required this.controller,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.isDark,
    required this.onAddInk,
  });

  final InkController controller;
  final Color accent, surface, textPrimary;
  final bool isDark;
  final VoidCallback onAddInk;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasInks) {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight,
            width: 0.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onAddInk,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.draw_outlined, size: 16, color: accent),
                const SizedBox(width: AppSpacing.xs),
                Text(AppLocalizations.of(context).addSignature,
                    style: TextStyle(
                        color: textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: controller.activeInkId,
              onChanged: controller.setActiveInk,
              items: controller.inks.values
                  .map((ink) => DropdownMenuItem(
                      value: ink.id,
                      child: Text(ink.label,
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              underline: const SizedBox.shrink(),
              isDense: true,
            ),
          ),
          Text(AppLocalizations.of(context).placementsCountLabel(controller.totalPlacements),
              style: TextStyle(
                  color: textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(width: AppSpacing.xs),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onAddInk,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.add, size: 16, color: accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// === InkSignatureSheet: signature canvas bottom sheet ===

class InkSignatureSheet extends StatefulWidget {
  const InkSignatureSheet({super.key});

  @override
  State<InkSignatureSheet> createState() => InkSignatureSheetState();
}

class InkSignatureSheetState extends State<InkSignatureSheet> {
  final GlobalKey<SignatureCanvasState> _signatureKey =
      GlobalKey<SignatureCanvasState>();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
              topRight: Radius.circular(AppShape.bottomSheetTopRadius),
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppLocalizations.of(context).signatureTitle,
                  style: TextStyle(
                      color: textPrimary,
                      fontSize: AppTypography.title1Size,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(height: 180, child: SignatureCanvas(key: _signatureKey)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  TextButton(
                      onPressed: () => _signatureKey.currentState?.clear(),
                      child: Text(AppLocalizations.of(context).commonClear)),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context).commonSkip)),
                  const SizedBox(width: AppSpacing.xs),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent, foregroundColor: Colors.white),
                    onPressed: () async {
                      final bytes =
                          await _signatureKey.currentState?.exportPng();
                      if (context.mounted) Navigator.pop(context, bytes);
                    },
                    child: Text(AppLocalizations.of(context).commonUse),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
