// lib/widgets/signature_editor_bar.dart
//
// The single shared signature editing cluster (export-grade grammar):
//  - SignatureEditorBar: InkCompactBar (signer dropdown / add) + "Place here"
//  - SignatureOverlayControls: rotate/scale/copy/clear for the edited ink
// Used identically by scan detail, fullscreen editor, and export screens.
import 'package:flutter/material.dart';

import '../core/models/signature_placement.dart';
import 'ink_board.dart';

class SignatureEditorBar extends StatelessWidget {
  const SignatureEditorBar({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.isDark,
    required this.onAddInk,
    required this.onPlaceHere,
  });

  final InkController controller;
  final int pageIndex;
  final Color accent;
  final Color surface;
  final Color textPrimary;
  final bool isDark;
  final VoidCallback onAddInk;
  final VoidCallback onPlaceHere;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkCompactBar(
            controller: controller,
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            isDark: isDark,
            onAddInk: onAddInk,
          ),
        ),
        if (controller.hasInks) ...[
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.draw_outlined, size: 14),
            label: const Text('Place here', style: TextStyle(fontSize: 10)),
            onPressed: onPlaceHere,
          ),
        ],
      ],
    );
  }
}

class SignatureOverlayControls extends StatelessWidget {
  const SignatureOverlayControls({
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

    void doCopyAll() => controller.copyToAllPages(editId, pageIndex, pageCount);
    void doClearThis() => controller.removePlacement(editId, pageIndex);
    void doRemove() => controller.removeInk(editId);
    void doClearAll() => controller.clearAll();

    return OverlayEditControls(
      layerType: LayerType.signature,
      rotationDegrees: pl.rotationDegrees,
      scale: pl.scale,
      onRotateLeft: () => controller.updatePlacement(editId, pageIndex,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: (pl.rotationDegrees - 10).clamp(-180, 180), scale: pl.scale)),
      onRotateRight: () => controller.updatePlacement(editId, pageIndex,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: (pl.rotationDegrees + 10).clamp(-180, 180), scale: pl.scale)),
      onScaleDown: () => controller.updatePlacement(editId, pageIndex,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: pl.rotationDegrees, scale: (pl.scale - 0.1).clamp(0.1, 5.0))),
      onScaleUp: () => controller.updatePlacement(editId, pageIndex,
          SignaturePlacement(pctX: pl.pctX, pctY: pl.pctY, rotationDegrees: pl.rotationDegrees, scale: (pl.scale + 0.1).clamp(0.1, 5.0))),
      onCopyAll: doCopyAll,
      onClearThis: doClearThis,
      onRemove: doRemove,
      onClearAll: doClearAll,
    );
  }
}
