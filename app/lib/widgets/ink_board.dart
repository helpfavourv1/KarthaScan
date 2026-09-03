import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/services/local_storage.dart';
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
        builder: (context) => const InkSignatureSheet(),
      );
      if (bytes != null) {
        await localStorage.saveSignaturePng(bytes);
      }
    }
    if (bytes == null) return null;

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

  void placeOnPage(int pageIndex) {
    final inkId = activeInkId;
    if (inkId == null) return;
    inkPlacements.putIfAbsent(inkId, () => {});
    inkPlacements[inkId]![pageIndex] = const SignaturePlacement(pctX: 0.5, pctY: 0.35);
    editInkId = inkId;
    _notify();
  }

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
                  padding: const EdgeInsets.all(12),
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
    required this.selectedBytesPath,
    required this.onSelect,
    required this.onDrag,
    this.onSelected,
    this.transformController,
  });

  final List<AnnotateLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedBytesPath;
  final void Function(AnnotateLayer layer) onSelect;
  final void Function(AnnotateLayer layer, double dxDelta, double dyDelta) onDrag;
  final VoidCallback? onSelected;
  final TransformationController? transformController;

  @override
  State<AnnotateOverlayPage> createState() => _AnnotateOverlayPageState();
}

class _AnnotateOverlayPageState extends State<AnnotateOverlayPage> {
  final Map<String, Uint8List> _cache = {};

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final layer in widget.layers.where((l) => l.pageIndex == widget.pageIndex))
          Builder(builder: (context) {
            if (!_cache.containsKey(layer.bytesPath)) {
              if (File(layer.bytesPath).existsSync()) {
                _cache[layer.bytesPath] = File(layer.bytesPath).readAsBytesSync();
              } else {
                _cache[layer.bytesPath] = Uint8List(0);
              }
            }
            final bytes = _cache[layer.bytesPath]!;
            if (bytes.isEmpty) return const SizedBox.shrink();
            final sigW = widget.iw * 0.28 * layer.placement.scale;
            final sigH = sigW / 2.0;
            final isSelected = layer.bytesPath == widget.selectedBytesPath;
            return Positioned(
              left: widget.dx + layer.placement.pctX * widget.iw - sigW / 2,
              top: widget.dy + layer.placement.pctY * widget.ih - sigH / 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { widget.onSelect(layer); widget.onSelected?.call(); },
                onPanUpdate: (d) {
                  final scale = widget.transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                  widget.onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
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
            final isSelected = layer.text == selectedText;
            final fontSize = layer.fontSize * layer.placement.scale;
            final fontWeight = layer.bold ? FontWeight.w700 : FontWeight.w400;
            final fontStyle = layer.italic ? FontStyle.italic : FontStyle.normal;
            final decoration = layer.underline ? TextDecoration.underline : TextDecoration.none;
            final color = Color(layer.color).withValues(alpha: layer.opacity);
            final shadows = layer.shadowColor != null
                ? [Shadow(offset: Offset(layer.shadowOffsetX, layer.shadowOffsetY), color: Color(layer.shadowColor!), blurRadius: 2)]
                : null;

            return Positioned(
              left: dx + layer.placement.pctX * iw - (iw * 0.3) / 2,
              top: dy + layer.placement.pctY * ih - fontSize / 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { onSelect(layer); onSelected?.call(); },
                onPanUpdate: (d) {
                  final scale = transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                  onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(color: accent, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: Transform.rotate(
                    angle: layer.placement.rotationDegrees * 3.14159 / 180,
                    child: Text(
                      layer.text,
                      style: TextStyle(
                        fontSize: fontSize,
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
  _SealPainter(this.layer);
  final StampLayer layer;
  @override
  void paint(Canvas canvas, Size size) => drawSeal(canvas, size.width, layer);
  @override
  bool shouldRepaint(covariant _SealPainter old) => old.layer != layer;
}

class StampOverlayPage extends StatelessWidget {
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
  final TransformationController? transformController;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final layer in layers.where((l) => l.pageIndex == pageIndex && (l.kind == 'text' || l.kind == 'note' || l.kind == 'date' || l.kind == 'checkbox' || l.kind == 'seal')))
          Builder(builder: (context) {
            final isSelected = layer.id == selectedId;
            if (layer.kind == 'checkbox') {
              final size = iw * 0.15 * layer.placement.scale;
              return Positioned(
                left: dx + layer.placement.pctX * iw - size / 2,
                top: dy + layer.placement.pctY * ih - size / 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { onSelect(layer); onSelected?.call(); },
                  onPanUpdate: (d) {
                    final scale = transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                    onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: isSelected ? BoxDecoration(border: Border.all(color: accent, width: 1.5), borderRadius: BorderRadius.circular(4)) : null,
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
              final size = iw * 0.25 * layer.placement.scale;
              return Positioned(
                left: dx + layer.placement.pctX * iw - size / 2,
                top: dy + layer.placement.pctY * ih - size / 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { onSelect(layer); onSelected?.call(); },
                  onPanUpdate: (d) {
                    final scale = transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                    onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: isSelected ? BoxDecoration(border: Border.all(color: accent, width: 1.5), borderRadius: BorderRadius.circular(4)) : null,
                    child: Transform.rotate(
                      angle: layer.placement.rotationDegrees * 3.14159 / 180,
                      child: SizedBox(width: size, height: size, child: CustomPaint(painter: _SealPainter(layer))),
                    ),
                  ),
                ),
              );
            }
            final fontSize = layer.fontSize * layer.placement.scale;
            final color = Color(layer.color).withValues(alpha: layer.opacity);
            final isFill = layer.kind == 'fill';
            final shadows = layer.halo
                ? [
                    for (final o in const [Offset(2,0), Offset(-2,0), Offset(0,2), Offset(0,-2), Offset(2,2), Offset(-2,-2), Offset(2,-2), Offset(-2,2)])
                      Shadow(offset: o, color: const Color(0xFFFFFFFF), blurRadius: 0),
                  ]
                : null;
            return Positioned(
              left: dx + layer.placement.pctX * iw - (iw * 0.3) / 2,
              top: dy + layer.placement.pctY * ih - fontSize / 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { onSelect(layer); onSelected?.call(); },
                onPanUpdate: (d) {
                    final scale = transformController?.value.getMaxScaleOnAxis() ?? 1.0;
                    onDrag(layer, d.delta.dx / scale, d.delta.dy / scale);
                  },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: layer.kind == 'note' && layer.noteBgColor != null ? Color(layer.noteBgColor!).withValues(alpha: layer.opacity) : null,
                    borderRadius: BorderRadius.circular(layer.kind == 'note' ? 16 : 4),
                    border: isFill 
                        ? Border.all(color: const Color(0xFF007AFF), width: 1.5)
                        : (isSelected ? Border.all(color: accent, width: 1.5) : null),
                  ),
                  child: Transform.rotate(
                    angle: layer.placement.rotationDegrees * 3.14159 / 180,
                    child: Text(
                      layer.text,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.values.firstWhere((w) => w.value == layer.fontWeight, orElse: () => FontWeight.w700),
                        fontFamily: layer.fontFamily,
                        color: color,
                        shadows: shadows,
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
// Row 1 (always): rotate ±10° + scale ±0.1
// Row 2 (type-specific): hidden for signature/annotate/checkbox; T1–T5 extend with opacity/font/color/etc.
// Row 3 (always): Copy all / Clear this / Remove / Clear all

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
  });

  final LayerType layerType;
  final double? opacity;
  final VoidCallback? onOpacityDown;
  final VoidCallback? onOpacityUp;
  final double? fontSize;
  final VoidCallback? onFontSizeDown;
  final VoidCallback? onFontSizeUp;
  final VoidCallback? onTools;
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
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: Icon(icon, size: 24)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepBtn(Icons.rotate_left, onRotateLeft),
                SizedBox(
                  width: 56,
                  child: Text('${rotationDegrees.round()}°',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                ),
                _stepBtn(Icons.rotate_right, onRotateRight),
                const SizedBox(width: 24),
                _stepBtn(Icons.remove, onScaleDown),
                SizedBox(
                  width: 56,
                  child: Text('${scale.toStringAsFixed(1)}x',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                ),
                _stepBtn(Icons.add, onScaleUp),
              ],
            ),
          ),
          if ((layerType == LayerType.watermark || layerType == LayerType.text || layerType == LayerType.note || layerType == LayerType.date || layerType == LayerType.checkbox || layerType == LayerType.seal) && opacity != null)
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stepBtn(Icons.remove, onOpacityDown!),
                  SizedBox(
                    width: 56,
                    child: Text('${(opacity! * 100).round()}%',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ),
                  _stepBtn(Icons.add, onOpacityUp!),
                  if (fontSize != null) ...[
                    const SizedBox(width: 24),
                    _stepBtn(Icons.remove, onFontSizeDown!),
                    SizedBox(
                      width: 56,
                      child: Text('${fontSize!.round()}pt',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center),
                    ),
                    _stepBtn(Icons.add, onFontSizeUp!),
                  ],
                  if (onTools != null) ...[
                    const SizedBox(width: 16),
                    _stepBtn(Icons.brush, onTools!),
                  ],
                ],
              ),
            ),
          SizedBox(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: onCopyAll, child: Text(AppLocalizations.of(context).copyAll, style: TextStyle(fontSize: 11))),
                TextButton(onPressed: onClearThis, child: Text(AppLocalizations.of(context).clearThis, style: TextStyle(fontSize: 11))),
                TextButton(onPressed: onRemove, child: Text(AppLocalizations.of(context).commonRemove, style: TextStyle(fontSize: 11))),
                TextButton(onPressed: onClearAll, child: Text(AppLocalizations.of(context).clearAll, style: TextStyle(fontSize: 11))),
              ],
            ),
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
        height: 48,
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
      height: 48,
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
