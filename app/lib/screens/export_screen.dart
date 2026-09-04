import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import '../core/services/ad_pacing_service.dart';
import '../core/services/interstitial_ad_service.dart';
import '../widgets/conditional_banner.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_saver/file_saver.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../core/models/export_job.dart';
import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/export_service.dart';
import '../core/services/filter_service.dart';
import '../core/services/local_storage.dart';
import '../core/services/share_service.dart';
import '../core/services/downloads_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/ink_board.dart';
import '../widgets/layer_control_panel.dart';
import '../core/models/signature_placement.dart';
import '../widgets/signature_editor_bar.dart';
import '../widgets/ios_pressable.dart';
import '../core/services/engagement_service.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.documentIds, this.initialFormat});

  final List<String> documentIds;
  final ExportFormat? initialFormat;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ScanProvider _scanProvider;
  final ExportService _exportService = ExportService();
  final LocalStorageService _localStorage = LocalStorageService();
  final ShareService _shareService = ShareService();

  // Export options state
  ExportFormat _selectedFormat = ExportFormat.pdf;
  FilterType _selectedFilter = FilterType.none;
  CompressionTier _selectedCompression = CompressionTier.original;
  ExportDocxMode _docxMode = ExportDocxMode.textOnly;
  ExportPageFormat _pageFormat = ExportPageFormat.a4;
  int? _targetMB;
  
  // Signature state — multi-ink via shared InkController (B19b)
  late final InkController _inkController;
  int _previewPage = 0;
  final Map<String, Map<String, dynamic>> _previewCache = {};

  bool get _isSingleDoc => _documents.length == 1;

  // B16 state-cached preview (no FutureBuilders)
  Uint8List? _previewBytes;
  int _previewW = 1;
  int _previewH = 1;
  bool _filterRowOpen = false;
  bool _targetExpanded = false;

  bool _isRunning = false;
  String? _statusMessage;
  List<String>? _lastExportPaths;
  final TransformationController _exportTransformController = TransformationController();
  TrayEditMode _exportEditMode = TrayEditMode.none;
  String? _selectedAnnotateBytesPath;
  String? _selectedWatermarkText;
  String? _selectedStampId;

  Future<void> _persistSignature() async {
    if (_documents.isEmpty) return;
    final doc = _documents.first;
    await _scanProvider.setSignatureState(doc.id, _inkController.inks.values.toList(), _inkController.layers);
  }

  @override
  void dispose() {
    _exportTransformController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _inkController = InkController(onChange: () { if (mounted) { setState(() {}); _persistSignature(); } });
    if (widget.initialFormat != null) {
      _selectedFormat = widget.initialFormat!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isSingleDoc && _documents.isNotEmpty) {
        _inkController.seed(_documents.first);
      }
      _loadPreview(_previewPage, _selectedFilter);
    });
  }

  List<ScanDocument> get _documents {
    final all = _scanProvider.documents.value;
    final result = <ScanDocument>[];
    for (final id in widget.documentIds) {
      for (final doc in all) {
        if (doc.id == id) {
          result.add(doc);
          break;
        }
      }
    }
    return result;
  }

  Future<void> _loadPreview(int pageIndex, FilterType filter) async {
    if (_documents.isEmpty) return;  // Empty-guard
    if (!_isSingleDoc) pageIndex = 0;
    final paths = _documents.first.pagePaths;
    if (paths.isEmpty) return;  // Empty-guard
    final idx = pageIndex.clamp(0, paths.length - 1);
    final key = '${idx}_${filter.index}';
    final cached = _previewCache[key];
    if (cached != null) {
      setState(() {
        _previewBytes = cached['bytes'] as Uint8List;
        _previewW = cached['w'] as int;
        _previewH = cached['h'] as int;
      });
      return;
    }
    final bytes = await File(paths[idx]).readAsBytes();
    final result = await compute(_previewIsolate, {'bytes': bytes, 'filter': filter.index});
    if (!mounted) return;
    _previewCache[key] = result;
    setState(() {
      _previewBytes = result['bytes'] as Uint8List;
      _previewW = result['w'] as int;
      _previewH = result['h'] as int;
    });
  }

  void _onPreviewPageChanged(int newPage) {
    setState(() {
      _previewPage = newPage;
      _exportEditMode = TrayEditMode.none;
      _selectedAnnotateBytesPath = null;
      _selectedWatermarkText = null;
      _selectedStampId = null;
    });
    _loadPreview(newPage, _selectedFilter);
  }

  void _onFilterChanged(FilterType f) {
    setState(() => _selectedFilter = f);
    _loadPreview(_previewPage, f);
  }

  Future<void> _runExport() async {
    final l10n = AppLocalizations.of(context);
    _lastExportPaths = null;
    setState(() {
      _isRunning = true;
      _statusMessage = l10n.exportingStatus;
    });

    final documents = _documents;
    final allOutputPaths = <String>[];
    String? errorMessage;

    try {
      final outputDir = await getTemporaryDirectory();
      Uint8List? legacyBytes;
      if (_isSingleDoc && !_inkController.hasInks) {
        legacyBytes = await _localStorage.loadSignaturePng();
      }
      for (final document in documents) {
        ScanDocument docForExport = document;
        if (_isSingleDoc && _inkController.hasInks) {
          docForExport = document.copyWith(
            signatureInks: _inkController.inks.values.toList(),
            signatureLayers: _inkController.layers,
          );
        }
        final paths = await _exportService.export(
          document: docForExport,
          format: _selectedFormat,
          outputDirectoryPath: outputDir.path,
          filter: _selectedFilter,
          signatureBytes: legacyBytes,
          signaturePlacements: null,
          compression: _selectedCompression,
          docxMode: _docxMode,
          pageFormat: _pageFormat,
          targetBytes: _targetMB != null ? _targetMB! * 1024 * 1024 : null,
        );
        allOutputPaths.addAll(paths);
        await AdPacingService.instance.recordExport();
        unawaited(InterstitialAdService.instance.showAfterExport());
      }
    } on ExportFailedException {
      errorMessage = l10n.genericErrorMessage;
    } catch (_) {
      errorMessage = l10n.exportGenericError;
    }

    if (!mounted) return;

    setState(() {
      _isRunning = false;
      _statusMessage = errorMessage ?? l10n.exportDoneStatus;
    });
    if (errorMessage == null) _lastExportPaths = allOutputPaths;
  }

  Future<void> _shareExport() async {
    await _runExport();
    if (!mounted) return;
    final paths = _lastExportPaths;
    if (paths == null || paths.isEmpty) return;
    try {
      await _shareService.shareFiles(filePaths: paths);
      EngagementService.instance.recordExport();
    } on ShareFailedException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).genericErrorMessage)));
      }
    }
  }

  Future<void> _saveToDevice() async {
    await _runExport();
    if (!mounted) return;
    final paths = _lastExportPaths;
    if (paths == null || paths.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final dlService = DownloadsService();
    int saved = 0;
    String? lastError;
    for (final path in paths) {
      try {
        final file = File(path);
        final bytes = await file.readAsBytes();
        final ext = p.extension(path).replaceAll('.', '');
        final name = p.basenameWithoutExtension(path);
        final mimeType = _mimeTypeToString(_getMimeType(ext));
        await dlService.saveToDownloads(
          fileName: '$name.$ext',
          bytes: bytes,
          mimeType: mimeType,
        );
        saved++;
      } catch (e) {
        lastError = e.toString();
      }
    }
    if (!mounted) return;
    if (saved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.saveToDownloadsAction)));
      EngagementService.instance.recordExport();
    } else if (lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.exportGenericError}: $lastError')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    final showCompression = _selectedFormat == ExportFormat.jpg || _selectedFormat == ExportFormat.png;

    return Scaffold(
      bottomNavigationBar: const ConditionalBanner(),
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(AppLocalizations.of(context).exportTitle, style: TextStyle(color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: SafeArea(
        child: _isRunning
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    Text(_statusMessage ?? '', style: TextStyle(color: textSecondary)),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                      child: _isSingleDoc ? _buildCanvasSingle() : _buildCanvasMulti(),
                    ),
                  ),
                  // --- Options stack (non-scrolling) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Format ribbon (56dp, one row)
                        SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              _formatCell(ExportFormat.pdf, 'PDF', Icons.picture_as_pdf_outlined, accent, surface, textPrimary, isDark),
                              _formatCell(ExportFormat.docx, 'Word', Icons.description_outlined, accent, surface, textPrimary, isDark),
                              _formatCell(ExportFormat.txt, 'TXT', Icons.notes_outlined, accent, surface, textPrimary, isDark),
                              _formatCell(ExportFormat.jpg, 'JPG', Icons.image_outlined, accent, surface, textPrimary, isDark),
                              _formatCell(ExportFormat.png, 'PNG', Icons.image_outlined, accent, surface, textPrimary, isDark),
                              _formatCell(ExportFormat.csv, 'CSV', Icons.table_chart_outlined, accent, surface, textPrimary, isDark),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // Merged row: Page Size + Signature (48px)
                        SizedBox(
                          height: 44,
                          child: Row(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _fixedSeg(_pageFormat == ExportPageFormat.a4, 'A4', () => setState(() => _pageFormat = ExportPageFormat.a4), accent, surface, textPrimary),
                                  _fixedSeg(_pageFormat == ExportPageFormat.letter, AppLocalizations.of(context).pageFormatLetter, () => setState(() => _pageFormat = ExportPageFormat.letter), accent, surface, textPrimary),
                                ],
                              ),
                              if (_isSingleDoc) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: InkCompactBar(
                                  controller: _inkController,
                                  accent: accent,
                                  surface: surface,
                                  textPrimary: textPrimary,
                                  isDark: isDark,
                                  onAddInk: () async {
                                    final inkId = await _inkController.addInk(context, _localStorage);
                                    if (inkId != null && mounted) {
                                      _inkController.placeOnPage(_previewPage);
                                      setState(() {
                                        _exportEditMode = TrayEditMode.signature;
                                      });
                                    }
                                  },
                                )),
                              ],
                            ],
                          ),
                        ),
                        // Quality + estimate (conditional JPG/PNG)
                        if (showCompression) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _segmentRow([
                            _seg(_selectedCompression == CompressionTier.small, AppLocalizations.of(context).compressSmall, () => setState(() => _selectedCompression = CompressionTier.small), accent, surface, textPrimary),
                            _seg(_selectedCompression == CompressionTier.medium, AppLocalizations.of(context).compressMedium, () => setState(() => _selectedCompression = CompressionTier.medium), accent, surface, textPrimary),
                            _seg(_selectedCompression == CompressionTier.original, AppLocalizations.of(context).filterOriginal, () => setState(() => _selectedCompression = CompressionTier.original), accent, surface, textPrimary),
                          ]),
                          FutureBuilder<int>(
                            future: _calculateEstimate(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data == 0) return const SizedBox.shrink();
                              final mb = (snapshot.data! / (1024 * 1024)).toStringAsFixed(2);
                              final l10n = AppLocalizations.of(context);
                              return Padding(
                                padding: const EdgeInsets.only(top: AppSpacing.xs),
                                child: Text(
                                  l10n.exportEstimatedSize(mb),
                                  style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                          ),
                          // Target MB row-launch (JPG only, collapsible)
                          if (_selectedFormat == ExportFormat.jpg) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _targetMBRowLaunch(accent, surface, textPrimary, isDark),
                            if (_targetMB != null && _targetExpanded) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: _targetMB!.toDouble(),
                                      min: 0.5,
                                      max: 10,
                                      divisions: 19,
                                      label: AppLocalizations.of(context).targetMbLabel(_targetMB!),
                                      onChanged: (v) => setState(() => _targetMB = v.round()),
                                    ),
                                  ),
                                  Text(AppLocalizations.of(context).targetMbLabel(_targetMB!), style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ],
                        ],
                        // Filter pills (conditional on wand toggle)
                        if (_filterRowOpen) ...[
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: FilterType.values.map((f) {
                                final label = f == FilterType.none ? AppLocalizations.of(context).filterOriginal :
                                             f == FilterType.grayscale ? AppLocalizations.of(context).filterGrayscale :
                                             f == FilterType.blackAndWhite ? AppLocalizations.of(context).filterBlackAndWhite :
                                             f == FilterType.colorEnhance ? AppLocalizations.of(context).filterColor : AppLocalizations.of(context).filterShadow;
                                return _filterPill(f, label, accent, textPrimary, isDark);
                              }).toList(),
                            ),
                          ),
                        ],
                        // Word mode (conditional)
                        if (_selectedFormat == ExportFormat.docx) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _segmentRow([
                            _seg(_docxMode == ExportDocxMode.textOnly, AppLocalizations.of(context).docxModeTextOnly, () => setState(() => _docxMode = ExportDocxMode.textOnly), accent, surface, textPrimary),
                            _seg(_docxMode == ExportDocxMode.imageEmbedded, AppLocalizations.of(context).docxModeWithImages, () => setState(() => _docxMode = ExportDocxMode.imageEmbedded), accent, surface, textPrimary),
                          ], height: 32),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                  // --- Pinned Share + Save buttons ---
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border(top: BorderSide(color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight, width: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton.icon(
                            onPressed: _isRunning ? null : _shareExport,
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: Text(AppLocalizations.of(context).commonShare, style: TextStyle(fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600, color: accent)),
                          ),
                          TextButton.icon(
                            onPressed: _isRunning ? null : _saveToDevice,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: Text(AppLocalizations.of(context).saveToDeviceButton, style: TextStyle(fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600, color: accent)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // === B16: single-doc signing canvas (non-scroll, no FutureBuilder) ===
  Widget _buildCanvasSingle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final pageCount = _documents.first.pagePaths.length;
    final pageIndex = _previewPage.clamp(0, pageCount - 1);
    final imgBytes = _previewBytes;
    final imgW = _previewW.toDouble();
    final imgH = _previewH.toDouble();

    return Column(
      children: [
        Row(
          children: [
            IOSPressable(
              onTap: pageIndex > 0 ? () => _onPreviewPageChanged(pageIndex - 1) : null,
              child: Icon(Icons.chevron_left, color: pageIndex > 0 ? accent : textSecondary, size: 24),
            ),
            Text(AppLocalizations.of(context).pageIndicator(pageIndex + 1, pageCount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            IOSPressable(
              onTap: pageIndex < pageCount - 1 ? () => _onPreviewPageChanged(pageIndex + 1) : null,
              child: Icon(Icons.chevron_right, color: pageIndex < pageCount - 1 ? accent : textSecondary, size: 24),
            ),
            if (_isSingleDoc)
              ActionChip(
                avatar: const Icon(Icons.open_in_full, size: 14),
                label: Text(AppLocalizations.of(context).fullscreenLabel, style: TextStyle(fontSize: 11)),
                onPressed: () => context.push('/edit/${_documents.first.id}'),
              ),
            const Spacer(),
            IOSPressable(
              onTap: () => setState(() => _filterRowOpen = !_filterRowOpen),
              child: Icon(Icons.auto_fix_high, color: _filterRowOpen ? accent : textSecondary, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (imgBytes == null) {
                  return Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight, width: 0.5),
                    ),
                    child: const Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                double iw = constraints.maxWidth;
                double ih = iw * (imgH / imgW);
                double dx = 0, dy = 0;
                if (ih > constraints.maxHeight) {
                  ih = constraints.maxHeight;
                  iw = ih * (imgW / imgH);
                  dx = (constraints.maxWidth - iw) / 2;
                } else {
                  dy = (constraints.maxHeight - ih) / 2;
                }
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: InteractiveViewer(
                            transformationController: _exportTransformController,
                            minScale: 1,
                            maxScale: 4,
                            child: Center(
                              child: SizedBox(
                                width: iw,
                                height: ih,
                                child: Image.memory(imgBytes, fit: BoxFit.fill),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _exportTransformController,
                            builder: (context, child) {
                              return Transform(
                                transform: _exportTransformController.value,
                                child: Stack(
                                  children: [
                                    InkOverlayPage(
                                      controller: _inkController,
                                      pageIndex: pageIndex,
                                      imgW: imgW, imgH: imgH, iw: iw, ih: ih, dx: dx, dy: dy,
                                      accent: accent,
                                      transformController: _exportTransformController,
                                      onSelected: () {
                                        setState(() {
                                          _exportEditMode = TrayEditMode.signature;
                                        });
                                      },
                                    ),
                                    if (_documents.first.annotateLayers.isNotEmpty)
                                      AnnotateOverlayPage(
                                        layers: _documents.first.annotateLayers,
                                        pageIndex: pageIndex,
                                        iw: iw, ih: ih, dx: dx, dy: dy,
                                        accent: accent,
                                        selectedBytesPath: _selectedAnnotateBytesPath,
                                        transformController: _exportTransformController,
                                        onSelect: (layer) => setState(() {
                                          _selectedAnnotateBytesPath = layer.bytesPath;
                                          _selectedWatermarkText = null;
                                          _selectedStampId = null;
                                          _exportEditMode = TrayEditMode.annotate;
                                        }),
                                        onDrag: (layer, dxDelta, dyDelta) {
                                          final doc = _documents.first;
                                          _scanProvider.updateAnnotateLayer(doc.id, AnnotateLayer(
                                            pageIndex: layer.pageIndex, bytesPath: layer.bytesPath,
                                            placement: SignaturePlacement(
                                              pctX: (layer.placement.pctX + dxDelta / iw).clamp(0.0, 1.0),
                                              pctY: (layer.placement.pctY + dyDelta / ih).clamp(0.0, 1.0),
                                              rotationDegrees: layer.placement.rotationDegrees, scale: layer.placement.scale,
                                            ),
                                          ));
                                        },
                                      ),
                                    if (_documents.first.watermarkLayers.isNotEmpty)
                                      WatermarkOverlayPage(
                                        layers: _documents.first.watermarkLayers,
                                        pageIndex: pageIndex,
                                        iw: iw, ih: ih, dx: dx, dy: dy,
                                        accent: accent,
                                        selectedText: _selectedWatermarkText,
                                        transformController: _exportTransformController,
                                        onSelect: (layer) => setState(() {
                                          _selectedWatermarkText = layer.text;
                                          _selectedAnnotateBytesPath = null;
                                          _selectedStampId = null;
                                          _exportEditMode = TrayEditMode.watermark;
                                        }),
                                        onDrag: (layer, dxDelta, dyDelta) {
                                          final doc = _documents.first;
                                          _scanProvider.updateWatermarkLayer(doc.id, layer.copyWith(
                                            placement: SignaturePlacement(
                                              pctX: (layer.placement.pctX + dxDelta / iw).clamp(0.0, 1.0),
                                              pctY: (layer.placement.pctY + dyDelta / ih).clamp(0.0, 1.0),
                                              rotationDegrees: layer.placement.rotationDegrees, scale: layer.placement.scale,
                                            ),
                                          ));
                                        },
                                      ),
                                    if (_documents.first.stampLayers.isNotEmpty)
                                      StampOverlayPage(
                                        layers: _documents.first.stampLayers,
                                        pageIndex: pageIndex,
                                        iw: iw, ih: ih, dx: dx, dy: dy,
                                        accent: accent,
                                        selectedId: _selectedStampId,
                                        transformController: _exportTransformController,
                                        onSelect: (layer) => setState(() {
                                          _selectedStampId = layer.id;
                                          _selectedAnnotateBytesPath = null;
                                          _selectedWatermarkText = null;
                                          _exportEditMode = layer.kind == 'text' ? TrayEditMode.text : (layer.kind == 'note' ? TrayEditMode.note : (layer.kind == 'date' ? TrayEditMode.date : (layer.kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal)));
                                        }),
                                        onDrag: (layer, dxDelta, dyDelta) {
                                          final doc = _documents.first;
                                          _scanProvider.updateStampLayer(doc.id, layer.copyWith(
                                            placement: SignaturePlacement(
                                              pctX: (layer.placement.pctX + dxDelta / iw).clamp(0.0, 1.0),
                                              pctY: (layer.placement.pctY + dyDelta / ih).clamp(0.0, 1.0),
                                              rotationDegrees: layer.placement.rotationDegrees, scale: layer.placement.scale,
                                            ),
                                          ));
                                        },
                                      ),



                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_exportEditMode == TrayEditMode.signature)
          Row(
            children: [
              Expanded(
                child: SignatureOverlayControls(
                  controller: _inkController,
                  pageIndex: pageIndex,
                  pageCount: pageCount,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ActionChip(
                avatar: const Icon(Icons.check, size: 14),
                label: Text(AppLocalizations.of(context).commonDone, style: TextStyle(fontSize: 11)),
                onPressed: () => setState(() {
                  _exportEditMode = TrayEditMode.none;
                  _inkController.setEditInk(null);
                }),
              ),
            ],
          ),
        if (_exportEditMode != TrayEditMode.none && _exportEditMode != TrayEditMode.signature)
          LayerControlPanel(
            document: _documents.first,
            pageIndex: pageIndex,
            editMode: _exportEditMode,
            scanProvider: _scanProvider,
            selectedAnnotateBytesPath: _selectedAnnotateBytesPath,
            selectedWatermarkText: _selectedWatermarkText,
            selectedStampId: _selectedStampId,
          ),
        if (_exportEditMode != TrayEditMode.none && _exportEditMode != TrayEditMode.signature)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: ActionChip(
                avatar: const Icon(Icons.check, size: 14),
                label: Text(AppLocalizations.of(context).commonDone, style: TextStyle(fontSize: 11)),
                onPressed: () => setState(() {
                  _exportEditMode = TrayEditMode.none;
                  _selectedAnnotateBytesPath = null;
                  _selectedWatermarkText = null;
                  _selectedStampId = null;
                }),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCanvasMulti() {
    return Container(
      height: 160,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          if (_previewBytes != null)
            Positioned.fill(child: Image.memory(_previewBytes!, fit: BoxFit.contain))
          else
            const Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2))),
          Positioned(
            top: 4, left: 4,
            child: Text(AppLocalizations.of(context).batchExportSignatureDisabled, style: TextStyle(color: Colors.white70, fontSize: 11, backgroundColor: Colors.black38)),
          ),
        ],
      ),
    );
  }

  // Compact signature controls that live in the merged row (multi-ink)
  // Target MB row-launch: switch + label + value + chevron. Tap row (when ON) toggles expansion.
  Widget _targetMBRowLaunch(Color accent, Color surface, Color textPrimary, bool isDark) {
    final enabled = _targetMB != null;
    return IOSPressable(
      onTap: enabled ? () => setState(() => _targetExpanded = !_targetExpanded) : null,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight, width: 0.5),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 24,
              child: Switch(
                value: enabled,
                onChanged: (v) {
                  setState(() {
                    _targetMB = v ? 2 : null;
                    if (v) _targetExpanded = true;
                  });
                },
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(AppLocalizations.of(context).fitToTargetMbLabel, style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (enabled) ...[
              Text(AppLocalizations.of(context).targetMbLabel(_targetMB!), style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: AppSpacing.xs),
              AnimatedRotation(
                turns: _targetExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.expand_more, size: 18, color: textPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<int> _calculateEstimate() async {
    if (_selectedFormat != ExportFormat.jpg && _selectedFormat != ExportFormat.png) return 0;
    if (_documents.isEmpty) return 0;
    
    // Real estimate: encode first page at selected tier quality, extrapolate by page count
    try {
      final firstPath = _documents.first.pagePaths.first;
      final bytes = await File(firstPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return 0;
      
      final quality = _selectedCompression == CompressionTier.original ? 92 :
                      _selectedCompression == CompressionTier.medium ? 60 : 30;
      final encoded = img.encodeJpg(decoded, quality: quality);
      final avgPageSize = encoded.length;
      final totalPages = _documents.fold<int>(0, (sum, doc) => sum + doc.pagePaths.length);
      return avgPageSize * totalPages;
    } catch (_) {
      return 0;
    }
  }

  Widget _segmentRow(List<Widget> children, {double height = 32}) {
    return SizedBox(height: height, child: Row(children: children));
  }

  Widget _seg(bool isSelected, String label, VoidCallback onTap, Color accent, Color surface, Color textPrimary) {
    return Expanded(
      child: IOSPressable(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: isSelected ? accent : surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3), width: isSelected ? 1.5 : 0.5),
          ),
          child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.white : textPrimary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
        ),
      ),
    );
  }

  Widget _fixedSeg(bool isSelected, String label, VoidCallback onTap, Color accent, Color surface, Color textPrimary) {
    return IOSPressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        height: 44,
        decoration: BoxDecoration(
          color: isSelected ? accent : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3), width: isSelected ? 1.5 : 0.5),
        ),
        child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.white : textPrimary, fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
      ),
    );
  }

  Widget _filterPill(FilterType f, String label, Color accent, Color textPrimary, bool isDark) {
    final isSelected = _selectedFilter == f;
    return IOSPressable(
      onTap: () => _onFilterChanged(f),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent : (isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isSelected ? accent : (isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight), width: isSelected ? 1.5 : 0.5),
        ),
        child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.white : textPrimary, fontSize: 11, fontWeight: FontWeight.w600))),
      ),
    );
  }

  Widget _formatCell(ExportFormat format, String label, IconData icon, Color accent, Color surface, Color textPrimary, bool isDark) {
    final isSelected = _selectedFormat == format;
    return Expanded(
      child: IOSPressable(
        onTap: () {
          setState(() {
            _selectedFormat = format;
            if (format != ExportFormat.jpg) { _targetMB = null; _targetExpanded = false; }
          });
          _loadPreview(_previewPage, _selectedFilter);
        },
        child: Container(
          height: 56,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.10) : surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? accent : (isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight), width: isSelected ? 1.5 : 0.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? accent : textPrimary, size: 18),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: isSelected ? accent : textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }



  MimeType _getMimeType(String ext) {
    switch (ext) {
      case 'pdf': return MimeType.pdf;
      case 'docx': return MimeType.other;
      case 'csv': return MimeType.csv;
      case 'txt': return MimeType.text;
      case 'jpg': case 'jpeg': return MimeType.jpeg;
      case 'png': return MimeType.png;
      default: return MimeType.other;
    }
  }

  String _mimeTypeToString(MimeType type) {
    switch (type) {
      case MimeType.pdf: return 'application/pdf';
      case MimeType.jpeg: return 'image/jpeg';
      case MimeType.png: return 'image/png';
      case MimeType.text: return 'text/plain';
      case MimeType.csv: return 'text/csv';
      case MimeType.other: return 'application/octet-stream';
      default: return 'application/octet-stream';
    }
  }
}




Map<String, dynamic> _previewIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final filter = FilterType.values[args['filter'] as int];
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return {'bytes': bytes, 'w': 1, 'h': 1};
  final filtered = FilterService.applyToImage(decoded, filter);
  return {
    'bytes': Uint8List.fromList(img.encodeJpg(filtered, quality: 85)),
    'w': filtered.width,
    'h': filtered.height,
  };
}
