import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/services/local_storage.dart';
import '../core/utils/constants.dart';
import 'signature_canvas.dart';

/// Which editor currently owns the tray preview screen.
enum TrayEditMode { none, signature, annotate, watermark, text, note }

/// Which kind of overlay layer the shared editor is editing.
enum LayerType { signature, annotate, watermark, text, note, date, checkbox }

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

  Future<String?> addInk(BuildContext context, LocalStorageService localStorage) async {
    Uint8List? bytes;
    final saved = await localStorage.loadSignaturePng();
    if (saved != null && context.mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Signature'),
          content: const Text('Use your saved signature or draw a new one?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'saved'), child: const Text('Use Saved')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'draw'), child: const Text('Draw New')),
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
      label: 'Signer ${inks.length + 1}',
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
  });

  final InkController controller;
  final VoidCallback? onSelected;
  final int pageIndex;
  final double imgW, imgH, iw, ih, dx, dy;
  final Color accent;

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
                onPanUpdate: (d) => controller.updatePlacement(
                  entry.key,
                  pageIndex,
                  SignaturePlacement(
                    pctX: (pl.pctX + d.delta.dx / iw).clamp(0.0, 1.0),
                    pctY: (pl.pctY + d.delta.dy / ih).clamp(0.0, 1.0),
                    rotationDegrees: pl.rotationDegrees,
                    scale: pl.scale,
                  ),
                ),
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
    required this.selectedBytesPath,
    required this.onSelect,
    required this.onDrag,
    this.onSelected,
  });

  final List<AnnotateLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedBytesPath;
  final void Function(AnnotateLayer layer) onSelect;
  final void Function(AnnotateLayer layer, double dxDelta, double dyDelta) onDrag;
  final VoidCallback? onSelected;

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
                onPanUpdate: (d) => widget.onDrag(layer, d.delta.dx, d.delta.dy),
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
  });

  final List<WatermarkLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedText;
  final void Function(WatermarkLayer layer) onSelect;
  final void Function(WatermarkLayer layer, double dxDelta, double dyDelta) onDrag;
  final VoidCallback? onSelected;

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
                onPanUpdate: (d) => onDrag(layer, d.delta.dx, d.delta.dy),
                child: Container(
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(color: accent, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  padding: const EdgeInsets.all(4),
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
  });

  final List<StampLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedId;
  final void Function(StampLayer layer) onSelect;
  final void Function(StampLayer layer, double dxDelta, double dyDelta) onDrag;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final layer in layers.where((l) => l.pageIndex == pageIndex && (l.kind == 'text' || l.kind == 'note')))
          Builder(builder: (context) {
            final isSelected = layer.id == selectedId;
            final fontSize = layer.fontSize * layer.placement.scale;
            final color = Color(layer.color).withValues(alpha: layer.opacity);
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
                onPanUpdate: (d) => onDrag(layer, d.delta.dx, d.delta.dy),
                child: Container(
                  decoration: BoxDecoration(
                    color: layer.kind == 'note' && layer.noteBgColor != null ? Color(layer.noteBgColor!).withValues(alpha: layer.opacity) : null,
                    borderRadius: BorderRadius.circular(layer.kind == 'note' ? 16 : 4),
                    border: isSelected ? Border.all(color: accent, width: 1.5) : null,
                  ),
                  padding: EdgeInsets.all(layer.kind == 'note' ? layer.fontSize * layer.placement.scale * (40 / 72) : 4),
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
          if ((layerType == LayerType.watermark || layerType == LayerType.text || layerType == LayerType.note) && opacity != null && fontSize != null)
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
                  const SizedBox(width: 24),
                  _stepBtn(Icons.remove, onFontSizeDown!),
                  SizedBox(
                    width: 56,
                    child: Text('${fontSize!.round()}pt',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ),
                  _stepBtn(Icons.add, onFontSizeUp!),
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
                TextButton(onPressed: onCopyAll, child: const Text('Copy all', style: TextStyle(fontSize: 11))),
                TextButton(onPressed: onClearThis, child: const Text('Clear this', style: TextStyle(fontSize: 11))),
                TextButton(onPressed: onRemove, child: const Text('Remove', style: TextStyle(fontSize: 11))),
                TextButton(onPressed: onClearAll, child: const Text('Clear all', style: TextStyle(fontSize: 11))),
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
                Text('Add Signature',
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
          Text('${controller.totalPlacements} placed',
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
              Text('Signature',
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
                      child: const Text('Clear')),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Skip')),
                  const SizedBox(width: AppSpacing.xs),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent, foregroundColor: Colors.white),
                    onPressed: () async {
                      final bytes =
                          await _signatureKey.currentState?.exportPng();
                      if (context.mounted) Navigator.pop(context, bytes);
                    },
                    child: const Text('Use'),
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
