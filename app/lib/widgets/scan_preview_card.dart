import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/local_storage.dart';
import '../core/models/page_transform.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import 'ink_board.dart';
import 'signature_editor_bar.dart';
import 'layer_control_panel.dart';
import 'document_canvas.dart';

class ScanPreviewCard extends StatefulWidget {
  const ScanPreviewCard({
    super.key,
    required this.document,
    required this.pagePaths,
    this.inkController,
    this.annotateLayers = const [],
    this.watermarkLayers = const [],
    this.stampLayers = const [],
    this.editMode = TrayEditMode.none,
    this.autoSelectAnnotatePath,
    this.autoSelectWatermarkText,
    this.autoSelectStampId,
    this.onSignatureSelect,
    this.onAnnotateSelect,
    this.onWatermarkSelect,
    this.onWatermarkLayerUpdate,
    this.onDoneEditing,
    this.onShare,
    this.onAnnotateLayerUpdate,
    this.onAnnotateThisPage,
    this.onCopyAnnotateToAllPages,
    this.onClearAnnotatePage,
    this.onClearAllAnnotateLayers,
    this.onCopyWatermarkToAllPages,
    this.onClearWatermarkPage,
    this.onClearAllWatermarkLayers,
    this.onStampSelect,
    this.onStampLayerUpdate,
    this.onCopyStampToAllPages,
    this.onClearStampPage,
    this.onClearAllStampLayers,
    this.initialPage = 0,
    this.onPageChanged,
    this.onEditFullscreen,
    this.pageTransforms = const {},
  });

  final ScanDocument document;
  final List<String> pagePaths;
  final InkController? inkController;
  final List<AnnotateLayer> annotateLayers;
  final List<WatermarkLayer> watermarkLayers;
  final List<StampLayer> stampLayers;
  final TrayEditMode editMode;
  final String? autoSelectAnnotatePath;
  final String? autoSelectWatermarkText;
  final String? autoSelectStampId;
  final VoidCallback? onSignatureSelect;
  final VoidCallback? onAnnotateSelect;
  final VoidCallback? onWatermarkSelect;
  final void Function(int pageIndex, WatermarkLayer layer)? onWatermarkLayerUpdate;
  final VoidCallback? onDoneEditing;
  final VoidCallback? onShare;
  final void Function(int pageIndex, AnnotateLayer layer)? onAnnotateLayerUpdate;
  final void Function(int pageIndex)? onAnnotateThisPage;
  final void Function(AnnotateLayer layer)? onCopyAnnotateToAllPages;
  final void Function(int pageIndex)? onClearAnnotatePage;
  final VoidCallback? onClearAllAnnotateLayers;
  final void Function(WatermarkLayer layer)? onCopyWatermarkToAllPages;
  final void Function(int pageIndex)? onClearWatermarkPage;
  final VoidCallback? onClearAllWatermarkLayers;
  final void Function(StampLayer layer)? onStampSelect;
  final void Function(int pageIndex, StampLayer layer)? onStampLayerUpdate;
  final void Function(StampLayer layer)? onCopyStampToAllPages;
  final void Function(int pageIndex)? onClearStampPage;
  final VoidCallback? onClearAllStampLayers;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onEditFullscreen;
  final Map<int, PageTransform> pageTransforms;

  @override
  State<ScanPreviewCard> createState() => _ScanPreviewCardState();
}

class _ScanPreviewCardState extends State<ScanPreviewCard> {
  late final PageController _pageController;
  late int _currentPage;
  String? _selectedAnnotateBytesPath;
  String? _selectedWatermarkText;
  String? _selectedStampId;
  late final ScanProvider _scanProvider;
  final LocalStorageService _localStorage = LocalStorageService();

  int get _lastIndex => widget.pagePaths.isEmpty ? 0 : widget.pagePaths.length - 1;

  @override
  void initState() {
    super.initState();
    final int requested = widget.initialPage;
    _currentPage = requested < 0 ? 0 : (requested > _lastIndex ? _lastIndex : requested);
    _pageController = PageController(initialPage: _currentPage);
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
  }

  @override
  void didUpdateWidget(ScanPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoSelectAnnotatePath != null && widget.autoSelectAnnotatePath != oldWidget.autoSelectAnnotatePath) {
      setState(() => _selectedAnnotateBytesPath = widget.autoSelectAnnotatePath);
    }
    if (widget.autoSelectWatermarkText != null && widget.autoSelectWatermarkText != oldWidget.autoSelectWatermarkText) {
      setState(() => _selectedWatermarkText = widget.autoSelectWatermarkText);
    }
    if (widget.autoSelectStampId != null && widget.autoSelectStampId != oldWidget.autoSelectStampId) {
      setState(() => _selectedStampId = widget.autoSelectStampId);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  Widget _buildSignatureControls() {
    final controller = widget.inkController;
    if (controller == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: InkCompactBar(
            controller: controller,
            accent: isDark ? AppColors.accentDark : AppColors.accentLight,
            surface: isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
            textPrimary: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            isDark: isDark,
            onAddInk: () async {
              final inkId = await controller.addInk(context, _localStorage);
              if (inkId != null && mounted) {
                controller.placeOnPage(_currentPage);
                setState(() {});
              }
            },
          ),
        ),
        SignatureOverlayControls(
          controller: controller,
          pageIndex: _currentPage,
          pageCount: widget.pagePaths.length,
        ),
      ],
    );
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
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
                  icon: Icon(Icons.chevron_left, color: _currentPage > 0 ? accent : textSecondary),
                ),
                Text(AppLocalizations.of(context).pageIndicator(_currentPage + 1, widget.pagePaths.length), style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _currentPage < _lastIndex ? () => _goToPage(_currentPage + 1) : null,
                  icon: Icon(Icons.chevron_right, color: _currentPage < _lastIndex ? accent : textSecondary),
                ),
                if (widget.onEditFullscreen != null)
                  ActionChip(
                    avatar: const Icon(Icons.open_in_full, size: 14),
                    label: Text(AppLocalizations.of(context).fullscreenLabel, style: TextStyle(fontSize: 11)),
                    onPressed: widget.onEditFullscreen,
                  ),
                const Spacer(),
                if (widget.editMode != TrayEditMode.none && widget.onDoneEditing != null)
                  ActionChip(
                    avatar: const Icon(Icons.check, size: 14),
                    label: Text(AppLocalizations.of(context).commonDone, style: TextStyle(fontSize: 11)),
                    onPressed: widget.onDoneEditing,
                  ),
              ],
            ),
          ),
          Expanded(
            child: DocumentCanvas(
                pagePaths: widget.pagePaths,
                inkController: widget.inkController,
                annotateLayers: widget.annotateLayers,
                watermarkLayers: widget.watermarkLayers,
                stampLayers: widget.stampLayers,
                selectedAnnotateBytesPath: _selectedAnnotateBytesPath,
                selectedWatermarkText: _selectedWatermarkText,
                selectedStampId: _selectedStampId,
                onAnnotateSelect: (layer) => setState(() { _selectedAnnotateBytesPath = layer.bytesPath; _selectedWatermarkText = null; _selectedStampId = null; widget.onAnnotateSelect?.call(); }),
                onAnnotateUpdate: widget.onAnnotateLayerUpdate,
                onSignatureSelect: () {
                  setState(() {});
                  widget.onSignatureSelect?.call();
                },
                onWatermarkSelect: widget.onWatermarkSelect,
                onWatermarkSelected: (layer) => setState(() { _selectedWatermarkText = layer.text; _selectedAnnotateBytesPath = null; _selectedStampId = null; }),
                onWatermarkLayerUpdate: widget.onWatermarkLayerUpdate,
                onStampSelected: (layer) { setState(() { _selectedStampId = layer.id; _selectedAnnotateBytesPath = null; _selectedWatermarkText = null; }); widget.onStampSelect?.call(layer); },
                onStampLayerUpdate: widget.onStampLayerUpdate,
                physics: const NeverScrollableScrollPhysics(),
                initialPage: _currentPage,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  widget.onPageChanged?.call(index);
                },
                pageTransforms: widget.pageTransforms,
              ),
          ),
          if (widget.editMode == TrayEditMode.signature && widget.inkController != null)
            _buildSignatureControls(),
          LayerControlPanel(
            document: widget.document,
            pageIndex: _currentPage,
            editMode: widget.editMode,
            scanProvider: _scanProvider,
            selectedAnnotateBytesPath: _selectedAnnotateBytesPath,
            selectedWatermarkText: _selectedWatermarkText,
            selectedStampId: _selectedStampId,
          ),
        ],
      ),
    );
  }
}



