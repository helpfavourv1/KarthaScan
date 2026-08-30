import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/services/local_storage.dart';
import '../core/utils/constants.dart';
import 'signature_canvas.dart';

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
  });

  final InkController controller;
  final int pageIndex;
  final double imgW, imgH, iw, ih, dx, dy;
  final Color accent;

  @override
  Widget build(BuildContext context) {
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
                onTap: () => controller.setEditInk(entry.key),
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
  });

  final List<AnnotateLayer> layers;
  final int pageIndex;
  final double iw, ih, dx, dy;
  final Color accent;
  final String? selectedBytesPath;
  final void Function(AnnotateLayer layer) onSelect;
  final void Function(AnnotateLayer layer, double dxDelta, double dyDelta) onDrag;

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
                onTap: () => widget.onSelect(layer),
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

// === InkEditControls: rotate/scale sliders + copy/clear/remove row ===

class InkEditControls extends StatelessWidget {
  const InkEditControls({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.pageCount,
  });

  final InkController controller;
  final int pageIndex;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final editId = controller.editInkId;
    if (editId == null) return const SizedBox.shrink();
    final pl = controller.inkPlacements[editId]?[pageIndex];
    if (pl == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text('Rotate', style: TextStyle(fontSize: 11)),
            Expanded(
              child: Slider(
                value: pl.rotationDegrees,
                min: -180,
                max: 180,
                onChanged: (v) => controller.updatePlacement(
                  editId,
                  pageIndex,
                  SignaturePlacement(
                    pctX: pl.pctX,
                    pctY: pl.pctY,
                    rotationDegrees: v,
                    scale: pl.scale,
                  ),
                ),
              ),
            ),
            Text('${pl.rotationDegrees.round()}°', style: const TextStyle(fontSize: 11)),
          ],
        ),
        Row(
          children: [
            const Text('Scale', style: TextStyle(fontSize: 11)),
            Expanded(
              child: Slider(
                value: pl.scale,
                min: 0.3,
                max: 3.0,
                onChanged: (v) => controller.updatePlacement(
                  editId,
                  pageIndex,
                  SignaturePlacement(
                    pctX: pl.pctX,
                    pctY: pl.pctY,
                    rotationDegrees: pl.rotationDegrees,
                    scale: v,
                  ),
                ),
              ),
            ),
            Text('${pl.scale.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 11)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => controller.copyToAllPages(editId, pageIndex, pageCount),
              child: const Text('Copy to all', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: () => controller.removePlacement(editId, pageIndex),
              child: const Text('Clear this', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: () => controller.removeInk(editId),
              child: const Text('Remove ink', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: controller.clearAll,
              child: const Text('Clear all', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }
}

// === InkCompactBar: dropdown + N-placed + add button (fits merged row) ===

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
