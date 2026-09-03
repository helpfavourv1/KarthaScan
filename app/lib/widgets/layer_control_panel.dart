import 'package:flutter/material.dart';

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/providers/scan_provider.dart';
import '../core/utils/constants.dart';
import 'ink_board.dart';

/// Shared control panel for editing overlay layers (annotate/watermark/stamp).
/// Eliminates duplication between ScanPreviewCard and FullScreenEditScreen.
class LayerControlPanel extends StatelessWidget {
  const LayerControlPanel({
    super.key,
    required this.document,
    required this.pageIndex,
    required this.editMode,
    required this.scanProvider,
    this.selectedAnnotateBytesPath,
    this.selectedWatermarkText,
    this.selectedStampId,
    this.onWatermarkEditTools,
    this.onStampEditTools,
  });

  final ScanDocument document;
  final int pageIndex;
  final TrayEditMode editMode;
  final ScanProvider scanProvider;
  final String? selectedAnnotateBytesPath;
  final String? selectedWatermarkText;
  final String? selectedStampId;
  final VoidCallback? onWatermarkEditTools;
  final VoidCallback? onStampEditTools;

  Widget _buildAnnotateControls(BuildContext context) {
    final pageLayers = document.annotateLayers.where((l) => l.pageIndex == pageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.bytesPath == selectedAnnotateBytesPath, orElse: () => pageLayers.first);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: LayerType.annotate,
        rotationDegrees: layer.placement.rotationDegrees,
        scale: layer.placement.scale,
        onRotateLeft: () => scanProvider.updateAnnotateLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => scanProvider.updateAnnotateLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => scanProvider.updateAnnotateLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => scanProvider.updateAnnotateLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onCopyAll: () {
          for (int i = 0; i < document.pagePaths.length; i++) {
            scanProvider.addAnnotateLayer(document.id, AnnotateLayer(pageIndex: i, bytesPath: layer.bytesPath, placement: layer.placement));
          }
        },
        onClearThis: () => scanProvider.removeAnnotateLayer(document.id, pageIndex, layer.bytesPath),
        onRemove: () => scanProvider.removeAnnotateLayer(document.id, pageIndex, layer.bytesPath),
        onClearAll: () => scanProvider.clearAnnotateLayers(document.id),
      ),
    );
  }

  Widget _buildWatermarkControls(BuildContext context) {
    final pageLayers = document.watermarkLayers.where((l) => l.pageIndex == pageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.text == selectedWatermarkText, orElse: () => pageLayers.first);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: LayerType.watermark,
        rotationDegrees: layer.placement.rotationDegrees,
        scale: layer.placement.scale,
        opacity: layer.opacity,
        fontSize: layer.fontSize,
        onRotateLeft: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onOpacityDown: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(opacity: (layer.opacity - 0.05).clamp(0.05, 1.0))),
        onOpacityUp: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(opacity: (layer.opacity + 0.05).clamp(0.05, 1.0))),
        onFontSizeDown: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144))),
        onFontSizeUp: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144))),
        onTools: onWatermarkEditTools,
        onCopyAll: () {
          for (int i = 0; i < document.pagePaths.length; i++) {
            scanProvider.addWatermarkLayer(document.id, layer.copyWith(pageIndex: i));
          }
        },
        onClearThis: () => scanProvider.removeWatermarkLayer(document.id, pageIndex, layer.text),
        onRemove: () => scanProvider.removeWatermarkLayer(document.id, pageIndex, layer.text),
        onClearAll: () => scanProvider.clearWatermarkLayers(document.id),
      ),
    );
  }

  Widget _buildStampControls(BuildContext context) {
    final kind = editMode == TrayEditMode.note ? 'note' : (editMode == TrayEditMode.date ? 'date' : (editMode == TrayEditMode.checkbox ? 'checkbox' : (editMode == TrayEditMode.seal ? 'seal' : 'text')));
    final pageLayers = document.stampLayers.where((l) => l.pageIndex == pageIndex && l.kind == kind).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == selectedStampId, orElse: () => pageLayers.first);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: kind == 'text' ? LayerType.text : (kind == 'note' ? LayerType.note : (kind == 'date' ? LayerType.date : (kind == 'checkbox' ? LayerType.checkbox : LayerType.seal))),
        rotationDegrees: layer.placement.rotationDegrees,
        scale: layer.placement.scale,
        opacity: layer.opacity,
        fontSize: kind == 'checkbox' ? null : layer.fontSize,
        onRotateLeft: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onOpacityDown: () => scanProvider.updateStampLayer(document.id, layer.copyWith(opacity: (layer.opacity - 0.05).clamp(0.05, 1.0))),
        onOpacityUp: () => scanProvider.updateStampLayer(document.id, layer.copyWith(opacity: (layer.opacity + 0.05).clamp(0.05, 1.0))),
        onFontSizeDown: () => scanProvider.updateStampLayer(document.id, layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144))),
        onFontSizeUp: () => scanProvider.updateStampLayer(document.id, layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144))),
        onTools: onStampEditTools,
        onCopyAll: () {
          for (int i = 0; i < document.pagePaths.length; i++) {
            scanProvider.addStampLayer(document.id, layer.copyWith(id: 'stamp_${DateTime.now().microsecondsSinceEpoch}_$i', pageIndex: i));
          }
        },
        onClearThis: () => scanProvider.removeStampLayer(document.id, layer.id),
        onRemove: () => scanProvider.removeStampLayer(document.id, layer.id),
        onClearAll: () => scanProvider.clearStampLayers(document.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (editMode == TrayEditMode.annotate) return _buildAnnotateControls(context);
    if (editMode == TrayEditMode.watermark) return _buildWatermarkControls(context);
    if (editMode == TrayEditMode.text || editMode == TrayEditMode.note || editMode == TrayEditMode.date || editMode == TrayEditMode.checkbox || editMode == TrayEditMode.seal) {
      return _buildStampControls(context);
    }
    return const SizedBox.shrink();
  }
}
