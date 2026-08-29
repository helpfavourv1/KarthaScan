import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../core/models/export_job.dart';
import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/export_service.dart';
import '../core/models/signature_placement.dart';
import '../core/services/filter_service.dart';
import '../core/services/share_service.dart';
import '../core/services/local_storage.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/signature_canvas.dart';
import '../widgets/ios_pressable.dart';

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
  final ShareService _shareService = ShareService();
  final LocalStorageService _localStorage = LocalStorageService();

  // Export options state
  ExportFormat _selectedFormat = ExportFormat.pdf;
  FilterType _selectedFilter = FilterType.none;
  CompressionTier _selectedCompression = CompressionTier.original;
  ExportDocxMode _docxMode = ExportDocxMode.textOnly;
  ExportPageFormat _pageFormat = ExportPageFormat.a4;
  int? _targetMB;
  
  // Signature state — per-page placement map (sticker model)
  Uint8List? _signatureBytes;
  final Map<int, SignaturePlacement> _signaturePlacements = {};
  int _previewPage = 0;
  double _sigAspect = 2.0;
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

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    if (widget.initialFormat != null) {
      _selectedFormat = widget.initialFormat!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview(_previewPage, _selectedFilter));
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
    setState(() => _previewPage = newPage);
    _loadPreview(newPage, _selectedFilter);
  }

  void _onFilterChanged(FilterType f) {
    setState(() => _selectedFilter = f);
    _loadPreview(_previewPage, f);
  }

  Future<void> _addSignature() async {
    Uint8List? signatureBytes;
    final saved = await _localStorage.loadSignaturePng();
    if (saved != null && mounted) {
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
      if (choice == 'saved') signatureBytes = saved;
    }
    if (signatureBytes == null && mounted) {
      final signatureKey = GlobalKey<SignatureCanvasState>();
      signatureBytes = await showModalBottomSheet<Uint8List?>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _SignatureSheet(signatureKey: signatureKey),
      );
      if (signatureBytes != null) {
        await _localStorage.saveSignaturePng(signatureBytes);
      }
    }

    if (signatureBytes == null || !mounted) return;

    final decoded = img.decodePng(signatureBytes);
    setState(() {
      _signatureBytes = signatureBytes;
      if (decoded != null && decoded.height > 0) {
        _sigAspect = (decoded.width / decoded.height).clamp(0.1, 10.0).toDouble();
      }
      _signaturePlacements.putIfAbsent(
        _previewPage,
        () => const SignaturePlacement(pctX: 0.5, pctY: 0.35),
      );
    });
  }

  void _removeSignature() {
    setState(() {
      _signatureBytes = null;
      _signaturePlacements.clear();
    });
  }

  Future<void> _runExport() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isRunning = true;
      _statusMessage = l10n.exportingStatus;
    });

    final documents = _documents;
    final allOutputPaths = <String>[];
    String? errorMessage;

    try {
      final outputDir = await getTemporaryDirectory();
      // Bridge: if user placed signatures via tray but not export, seed from document layers
      if (_isSingleDoc && _signaturePlacements.isEmpty && documents.first.signatureLayers.isNotEmpty) {
        for (final layer in documents.first.signatureLayers) {
          _signaturePlacements[layer.pageIndex] = layer.placement;
        }
      }
      for (final document in documents) {
        final paths = await _exportService.export(
          document: document,
          format: _selectedFormat,
          outputDirectoryPath: outputDir.path,
          filter: _selectedFilter,
          signatureBytes: _isSingleDoc ? _signatureBytes : null,
          signaturePlacements: (_isSingleDoc && _signatureBytes != null) ? Map<int, SignaturePlacement>.of(_signaturePlacements) : null,
          compression: _selectedCompression,
          docxMode: _docxMode,
          pageFormat: _pageFormat,
          targetBytes: _targetMB != null ? _targetMB! * 1024 * 1024 : null,
        );
        allOutputPaths.addAll(paths);
      }
    } on ExportFailedException {
      errorMessage = l10n.genericErrorMessage;
    } catch (_) {
      errorMessage = l10n.exportGenericError;
    }

    if (!mounted) return;

    if (errorMessage != null) {
      setState(() {
        _isRunning = false;
        _statusMessage = errorMessage;
      });
      return;
    }

    setState(() {
      _isRunning = false;
      _statusMessage = l10n.exportDoneStatus;
    });

    try {
      await _shareService.shareFiles(filePaths: allOutputPaths);
    } on ShareFailedException {
      // Share sheet failing to open isn't fatal here.
    }

    if (mounted) context.pop();
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
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Export', style: TextStyle(color: textPrimary)),
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
                        // Format ribbon (70px, one row)
                        SizedBox(
                          height: 70,
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
                          height: 48,
                          child: Row(
                            children: [
                              Expanded(
                                child: _segmentRow([
                                  _seg(_pageFormat == ExportPageFormat.a4, 'A4', () => setState(() => _pageFormat = ExportPageFormat.a4), accent, surface, textPrimary),
                                  _seg(_pageFormat == ExportPageFormat.letter, 'Letter (US)', () => setState(() => _pageFormat = ExportPageFormat.letter), accent, surface, textPrimary),
                                ], height: 48),
                              ),
                              if (_isSingleDoc) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: _signatureCompact(accent, surface, textPrimary, textSecondary, isDark)),
                              ],
                            ],
                          ),
                        ),
                        // Quality + estimate (conditional JPG/PNG)
                        if (showCompression) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _segmentRow([
                            _seg(_selectedCompression == CompressionTier.small, 'Small', () => setState(() => _selectedCompression = CompressionTier.small), accent, surface, textPrimary),
                            _seg(_selectedCompression == CompressionTier.medium, 'Medium', () => setState(() => _selectedCompression = CompressionTier.medium), accent, surface, textPrimary),
                            _seg(_selectedCompression == CompressionTier.original, 'Original', () => setState(() => _selectedCompression = CompressionTier.original), accent, surface, textPrimary),
                          ]),
                          FutureBuilder<int>(
                            future: _calculateEstimate(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data == 0) return const SizedBox.shrink();
                              final mb = (snapshot.data! / (1024 * 1024)).toStringAsFixed(2);
                              return Padding(
                                padding: const EdgeInsets.only(top: AppSpacing.xs),
                                child: Text(
                                  'Estimated size: $mb MB',
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
                                      label: '\$_targetMB MB',
                                      onChanged: (v) => setState(() => _targetMB = v.round()),
                                    ),
                                  ),
                                  Text('\$_targetMB MB', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
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
                                final label = f == FilterType.none ? 'Original' :
                                             f == FilterType.grayscale ? 'Grayscale' :
                                             f == FilterType.blackAndWhite ? 'B&W' :
                                             f == FilterType.colorEnhance ? 'Color' : 'Shadow';
                                return _filterPill(f, label, accent, textPrimary, isDark);
                              }).toList(),
                            ),
                          ),
                        ],
                        // Word mode (conditional)
                        if (_selectedFormat == ExportFormat.docx) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _segmentRow([
                            _seg(_docxMode == ExportDocxMode.textOnly, 'Text Only', () => setState(() => _docxMode = ExportDocxMode.textOnly), accent, surface, textPrimary),
                            _seg(_docxMode == ExportDocxMode.imageEmbedded, 'With Images', () => setState(() => _docxMode = ExportDocxMode.imageEmbedded), accent, surface, textPrimary),
                          ], height: 32),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                  // --- Pinned Export button ---
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border(top: BorderSide(color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight, width: 0.5)),
                      ),
                      child: SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _runExport,
                          icon: const Icon(Icons.ios_share, size: 20),
                          label: const Text('Export & Share', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shadowColor: accent.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
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
    final placement = _signaturePlacements[pageIndex];
    final imgBytes = _previewBytes;
    final imgW = _previewW.toDouble();
    final imgH = _previewH.toDouble();

    return Column(
      children: [
        // Header row: chevrons + page indicator + wand + sign-this-page
        Row(
          children: [
            IOSPressable(
              onTap: pageIndex > 0 ? () => _onPreviewPageChanged(pageIndex - 1) : null,
              child: Icon(Icons.chevron_left, color: pageIndex > 0 ? accent : textSecondary, size: 24),
            ),
            Text('Page ${pageIndex + 1} / $pageCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            IOSPressable(
              onTap: pageIndex < pageCount - 1 ? () => _onPreviewPageChanged(pageIndex + 1) : null,
              child: Icon(Icons.chevron_right, color: pageIndex < pageCount - 1 ? accent : textSecondary, size: 24),
            ),
            const Spacer(),
            IOSPressable(
              onTap: () => setState(() => _filterRowOpen = !_filterRowOpen),
              child: Icon(
                Icons.auto_fix_high,
                color: _filterRowOpen ? accent : textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (_signatureBytes != null && placement == null)
              ActionChip(
                avatar: const Icon(Icons.draw_outlined, size: 14),
                label: const Text('Sign this page too', style: TextStyle(fontSize: 10)),
                onPressed: () => setState(() {
                  _signaturePlacements[pageIndex] = const SignaturePlacement(pctX: 0.5, pctY: 0.35);
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // Canvas image + signature overlay
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
                final sigW = iw * 0.28 * (placement?.scale ?? 1.0);
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(child: Center(child: Image.memory(imgBytes, fit: BoxFit.contain))),
                      if (_signatureBytes != null && placement != null)
                        Positioned(
                          left: dx + placement.pctX * iw - sigW / 2,
                          top: dy + placement.pctY * ih - (sigW / _sigAspect) / 2,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (d) => setState(() {
                              _signaturePlacements[pageIndex] = SignaturePlacement(
                                pctX: (placement.pctX + d.delta.dx / iw).clamp(0.0, 1.0),
                                pctY: (placement.pctY + d.delta.dy / ih).clamp(0.0, 1.0),
                                rotationDegrees: placement.rotationDegrees,
                                scale: placement.scale,
                              );
                            }),
                            child: Transform.rotate(
                              angle: placement.rotationDegrees * 3.14159 / 180,
                              child: Image.memory(_signatureBytes!, width: sigW, height: sigW / _sigAspect, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        // Rotate/scale sliders + copy/clear controls (only when sig present on current page)
        if (_signatureBytes != null && placement != null) ...[
          Row(
            children: [
              const Text('Rotate', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: placement.rotationDegrees,
                  min: -180,
                  max: 180,
                  onChanged: (v) => setState(() {
                    _signaturePlacements[pageIndex] = SignaturePlacement(pctX: placement.pctX, pctY: placement.pctY, rotationDegrees: v, scale: placement.scale);
                  }),
                ),
              ),
              Text('${placement.rotationDegrees.round()}°', style: const TextStyle(fontSize: 11)),
            ],
          ),
          Row(
            children: [
              const Text('Scale', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: placement.scale,
                  min: 0.3,
                  max: 3.0,
                  onChanged: (v) => setState(() {
                    _signaturePlacements[pageIndex] = SignaturePlacement(pctX: placement.pctX, pctY: placement.pctY, rotationDegrees: placement.rotationDegrees, scale: v);
                  }),
                ),
              ),
              Text('${placement.scale.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 11)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() { for (int i = 0; i < pageCount; i++) { _signaturePlacements[i] = placement; } }),
                child: const Text('Copy to all', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => setState(() => _signaturePlacements.remove(pageIndex)),
                child: const Text('Clear this', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => setState(() => _signaturePlacements.clear()),
                child: const Text('Clear all', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
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
          const Positioned(
            top: 4, left: 4,
            child: Text('Batch export — signature placement disabled', style: TextStyle(color: Colors.white70, fontSize: 11, backgroundColor: Colors.black38)),
          ),
        ],
      ),
    );
  }

  // Compact signature controls that live in the merged row
  Widget _signatureCompact(Color accent, Color surface, Color textPrimary, Color textSecondary, bool isDark) {
    if (_signatureBytes == null) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight, width: 0.5),
        ),
        child: IOSPressable(
          onTap: _addSignature,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.draw_outlined, size: 16, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Text('Add Signature', style: TextStyle(color: textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    final signedCount = _signaturePlacements.length;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 14),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text('$signedCount signed', style: TextStyle(color: textPrimary, fontSize: 11, fontWeight: FontWeight.w600))),
          IOSPressable(
            onTap: _removeSignature,
            child: Text('Remove', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

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
            Text('Fit to target MB', style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (enabled) ...[
              Text('$_targetMB MB', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
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
          height: 70,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.10) : surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? accent : (isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight), width: isSelected ? 1.5 : 0.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? accent : textPrimary, size: 20),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: isSelected ? accent : textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

}

class _SignatureSheet extends StatelessWidget {
  const _SignatureSheet({required this.signatureKey});
  final GlobalKey<SignatureCanvasState> signatureKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppShape.bottomSheetTopRadius), topRight: Radius.circular(AppShape.bottomSheetTopRadius))),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.signSheetTitle, style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(height: 180, child: SignatureCanvas(key: signatureKey)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  TextButton(onPressed: () => signatureKey.currentState?.clear(), child: Text(l10n.commonClear)),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonSkip)),
                  const SizedBox(width: AppSpacing.xs),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                    onPressed: () async {
                      final bytes = await signatureKey.currentState?.exportPng();
                      if (context.mounted) Navigator.pop(context, bytes);
                    },
                    child: Text(l10n.useSignatureButton),
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
