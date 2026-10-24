import 'package:flutter/material.dart';

import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/providers/scan_provider.dart';
import '../core/utils/constants.dart';
import 'ink_board.dart';
import 'watermark_sheet.dart';
import 'text_stamp_sheet.dart';
import 'seal_stamp_sheet.dart';

/// Shared control panel for editing overlay layers (annotate/watermark/stamp).
/// Eliminates duplication between ScanPreviewCard and FullScreenEditScreen.
class LayerControlPanel extends StatelessWidget {
  const LayerControlPanel({
    super.key,
    required this.document,
    required this.pageIndex,
    required this.editMode,
    required this.scanProvider,
    this.selectedAnnotateId,
    this.selectedWatermarkText,
    this.selectedStampId,
      this.onEditFill,
    this.onDone,
  });

  final ScanDocument document;
  final int pageIndex;
  final TrayEditMode editMode;
  final ScanProvider scanProvider;
  final String? selectedAnnotateId;
  final String? selectedWatermarkText;
  final String? selectedStampId;
  final void Function(StampLayer layer)? onEditFill;

  /// Shown as the Done button inside the controls, so no separate Done row is needed.
  final VoidCallback? onDone;

  static String _stampKind(TrayEditMode m) =>
      m == TrayEditMode.fill ? 'fill' : (m == TrayEditMode.note ? 'note' : (m == TrayEditMode.date ? 'date' : (m == TrayEditMode.checkbox ? 'checkbox' : (m == TrayEditMode.seal ? 'seal' : 'text'))));

  static bool _isStampMode(TrayEditMode m) =>
      m == TrayEditMode.text || m == TrayEditMode.note || m == TrayEditMode.date || m == TrayEditMode.checkbox || m == TrayEditMode.seal || m == TrayEditMode.fill;

  /// True when this panel will draw controls (so the screen can skip its own Done button).
  static bool willShow(ScanDocument document, int pageIndex, TrayEditMode mode) {
    if (mode == TrayEditMode.annotate) return document.annotateLayers.any((l) => l.pageIndex == pageIndex);
    if (mode == TrayEditMode.watermark) return document.watermarkLayers.any((l) => l.pageIndex == pageIndex);
    if (_isStampMode(mode)) {
      final String kind = _stampKind(mode);
      return document.stampLayers.any((l) => l.pageIndex == pageIndex && l.kind == kind);
    }
    return false;
  }

  Widget _buildAnnotateControls(BuildContext context) {
    final pageLayers = document.annotateLayers.where((l) => l.pageIndex == pageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == selectedAnnotateId, orElse: () => pageLayers.first);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            if (i == pageIndex) continue; // the source page already has it
            scanProvider.addAnnotateLayer(document.id, AnnotateLayer(pageIndex: i, bytesPath: layer.bytesPath, placement: layer.placement));
          }
        },
        onClearThis: () => scanProvider.removeAnnotateLayer(document.id, layer.id),
        onRemove: () => scanProvider.removeAnnotateLayer(document.id, layer.id),
        onClearAll: () => scanProvider.clearAnnotateLayers(document.id),
        onDone: onDone,
      ),
    );
  }

  Widget _buildWatermarkControls(BuildContext context) {
    final pageLayers = document.watermarkLayers.where((l) => l.pageIndex == pageIndex).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == selectedWatermarkText, orElse: () => pageLayers.first);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        // Text is drawn to fit its box, so the size is changed by scaling the
        // box (the same thing the preview and the export both honor).
        onFontSizeDown: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144), placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        // Text is drawn to fit its box, so the size is changed by scaling the
        // box (the same thing the preview and the export both honor).
        onFontSizeUp: () => scanProvider.updateWatermarkLayer(document.id, layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144), placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onTools: () async {
          final config = await showModalBottomSheet<WatermarkLayer>(
            context: context,
            isScrollControlled: true,
            builder: (context) => WatermarkSheet(initialConfig: layer),
          );
          if (config != null) {
            final updated = config.copyWith(pageIndex: layer.pageIndex, placement: layer.placement);
            await scanProvider.replaceWatermarkLayer(document.id, layer, updated);
          }
        },
        onCopyAll: () => scanProvider.addWatermarkLayerToPages(
          document.id,
          layer,
          <int>[for (int i = 0; i < document.pagePaths.length; i++) if (i != pageIndex) i],
        ),
        onClearThis: () => scanProvider.removeWatermarkLayer(document.id, layer.id),
        onRemove: () => scanProvider.removeWatermarkLayer(document.id, layer.id),
        onClearAll: () => scanProvider.clearWatermarkLayers(document.id),
        onDone: onDone,
      ),
    );
  }

  Widget _buildStampControls(BuildContext context) {
    final kind = editMode == TrayEditMode.fill ? 'fill' : (editMode == TrayEditMode.note ? 'note' : (editMode == TrayEditMode.date ? 'date' : (editMode == TrayEditMode.checkbox ? 'checkbox' : (editMode == TrayEditMode.seal ? 'seal' : 'text'))));
    final pageLayers = document.stampLayers.where((l) => l.pageIndex == pageIndex && l.kind == kind).toList();
    if (pageLayers.isEmpty) return const SizedBox.shrink();
    final layer = pageLayers.firstWhere((l) => l.id == selectedStampId, orElse: () => pageLayers.first);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: OverlayEditControls(
        layerType: kind == 'text' || kind == 'fill' ? LayerType.text : (kind == 'note' ? LayerType.note : (kind == 'date' ? LayerType.date : (kind == 'checkbox' ? LayerType.checkbox : LayerType.seal))),
        rotationDegrees: layer.placement.rotationDegrees,
        scale: layer.placement.scale,
        opacity: layer.opacity,
        fontSize: kind == 'checkbox' ? null : (layer.isFlowFill ? layer.fillSize * 600 : layer.fontSize),
        onRotateLeft: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees - 10).clamp(-180, 180), scale: layer.placement.scale))),
        onRotateRight: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: (layer.placement.rotationDegrees + 10).clamp(-180, 180), scale: layer.placement.scale))),
        onScaleDown: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        onScaleUp: () => scanProvider.updateStampLayer(document.id, layer.copyWith(placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onOpacityDown: () => scanProvider.updateStampLayer(document.id, layer.copyWith(opacity: (layer.opacity - 0.05).clamp(0.05, 1.0))),
        onOpacityUp: () => scanProvider.updateStampLayer(document.id, layer.copyWith(opacity: (layer.opacity + 0.05).clamp(0.05, 1.0))),
        // Text is drawn to fit its box, so the size is changed by scaling the
        // box (the same thing the preview and the export both honor).
        onFontSizeDown: () => layer.isFlowFill ? scanProvider.updateStampLayer(document.id, layer.copyWith(fillSize: (layer.fillSize / 1.1).clamp(0.008, 0.12))) : scanProvider.updateStampLayer(document.id, layer.copyWith(fontSize: (layer.fontSize - 4).clamp(12, 144), placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale - 0.1).clamp(0.1, 5.0)))),
        // Text is drawn to fit its box, so the size is changed by scaling the
        // box (the same thing the preview and the export both honor).
        onFontSizeUp: () => layer.isFlowFill ? scanProvider.updateStampLayer(document.id, layer.copyWith(fillSize: (layer.fillSize * 1.1).clamp(0.008, 0.12))) : scanProvider.updateStampLayer(document.id, layer.copyWith(fontSize: (layer.fontSize + 4).clamp(12, 144), placement: SignaturePlacement(pctX: layer.placement.pctX, pctY: layer.placement.pctY, rotationDegrees: layer.placement.rotationDegrees, scale: (layer.placement.scale + 0.1).clamp(0.1, 5.0)))),
        onTools: () async {
          // Fill text is edited right on the page, not in a sheet.
          if (layer.kind == 'fill' && onEditFill != null) {
            onEditFill!(layer);
            return;
          }
          final config = await showModalBottomSheet<StampResult>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => layer.kind == 'seal'
                ? SealStampSheet(initial: layer)
                : TextStampSheet(kind: layer.kind, initial: layer),
          );
          if (config != null) {
            final updated = layer.copyWith(
              text: config.text,
              fontSize: config.fontSize,
              color: config.color,
              fontFamily: config.fontFamily,
              fontWeight: config.fontWeightValue,
              align: config.alignName,
              halo: config.halo,
              noteBgColor: config.noteBgColorValue,
              dateFormat: config.dateFormatValue,
              customDateMillis: config.customDateMillisValue,
              checked: config.checkedValue,
              checkShape: config.checkShapeValue,
              boxColor: config.boxColorValue,
              tickColor: config.tickColorValue,
              sealShape: config.sealShapeValue,
              sealSubtext: config.sealSubtextValue,
              sealCenter: config.sealCenterValue,
              sealImageBytes: config.sealImageBytesValue,
            );
            await scanProvider.updateStampLayer(document.id, updated);
          }
        },
        onCopyAll: () {
          for (int i = 0; i < document.pagePaths.length; i++) {
            if (i == pageIndex) continue;
            scanProvider.addStampLayer(document.id, layer.copyWith(id: 'stamp_${DateTime.now().microsecondsSinceEpoch}_$i', pageIndex: i));
          }
        },
        onClearThis: () => scanProvider.removeStampLayer(document.id, layer.id),
        onRemove: () => scanProvider.removeStampLayer(document.id, layer.id),
        onClearAll: () => scanProvider.clearStampLayers(document.id),
        onDone: onDone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (editMode == TrayEditMode.annotate) return _buildAnnotateControls(context);
    if (editMode == TrayEditMode.watermark) return _buildWatermarkControls(context);
    if (editMode == TrayEditMode.text || editMode == TrayEditMode.note || editMode == TrayEditMode.date || editMode == TrayEditMode.checkbox || editMode == TrayEditMode.seal || editMode == TrayEditMode.fill) {
      return _buildStampControls(context);
    }
    return const SizedBox.shrink();
  }
}
