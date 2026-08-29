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
import '../core/services/filter_service.dart';
import '../core/services/share_service.dart';
import '../core/services/local_storage.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/signature_canvas.dart';

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

  bool _isRunning = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    if (widget.initialFormat != null) {
      _selectedFormat = widget.initialFormat!;
    }
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
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                                        _buildLivePreview(),
                                        const SizedBox(height: AppSpacing.lg),
                  // Format Ribbon
                  Text('Format', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _buildFormatCard(ExportFormat.pdf, 'PDF', Icons.picture_as_pdf_outlined, accent),
                      _buildFormatCard(ExportFormat.docx, 'Word', Icons.description_outlined, accent),
                      _buildFormatCard(ExportFormat.txt, 'TXT', Icons.notes_outlined, accent),
                      _buildFormatCard(ExportFormat.jpg, 'JPG', Icons.image_outlined, accent),
                      _buildFormatCard(ExportFormat.png, 'PNG', Icons.image_outlined, accent),
                      _buildFormatCard(ExportFormat.csv, 'CSV', Icons.table_chart_outlined, accent),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Filter Selector
                  Text('Filter', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(AppShape.cardRadius),
                      border: Border.all(color: isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight, width: 1),
                      boxShadow: AppShadows.ambient,
                    ),
                    child: DropdownButton<FilterType>(
                      value: _selectedFilter,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      onChanged: (value) => setState(() => _selectedFilter = value!),
                      items: FilterType.values.map((f) {
                        final label = f == FilterType.none ? 'Original' :
                                     f == FilterType.grayscale ? 'Grayscale' :
                                     f == FilterType.blackAndWhite ? 'B&W' :
                                     f == FilterType.colorEnhance ? 'Color Enhance' : 'Shadow Removal';
                        return DropdownMenuItem(value: f, child: Text(label));
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // DOCX Mode (conditional)
                  if (_selectedFormat == ExportFormat.docx) ...[
                    Text('Word Mode', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppShape.cardRadius)),
                      child: Row(
                        children: [
                          Expanded(child: _buildDocxModeChip(ExportDocxMode.textOnly, 'Text Only', accent)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: _buildDocxModeChip(ExportDocxMode.imageEmbedded, 'With Images', accent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // Page Format
                  Text('Page Size', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppShape.cardRadius)),
                    child: Row(
                      children: [
                        Expanded(child: _buildPageFormatChip(ExportPageFormat.a4, 'A4', accent)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: _buildPageFormatChip(ExportPageFormat.letter, 'Letter (US)', accent)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Compression (conditional)
                  if (showCompression) ...[
                    Text('Quality', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppShape.cardRadius)),
                      child: Row(
                        children: [
                          Expanded(child: _buildCompressionChip(CompressionTier.small, 'Small', accent)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: _buildCompressionChip(CompressionTier.medium, 'Medium', accent)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: _buildCompressionChip(CompressionTier.original, 'Original', accent)),
                        ],
                      ),
                    ),
                    FutureBuilder<int>(
                      future: _calculateEstimate(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data == 0) return const SizedBox.shrink();
                        final mb = (snapshot.data! / (1024 * 1024)).toStringAsFixed(2);
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            'Estimated size: $mb MB',
                            style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_selectedFormat == ExportFormat.jpg) ...[
                      Text('Target Size (optional)', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppShape.cardRadius)),
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Fit to target MB'),
                              value: _targetMB != null,
                              onChanged: (v) => setState(() => _targetMB = v ? 2 : null),
                            ),
                            if (_targetMB != null) ...[
                              Slider(
                                value: _targetMB!.toDouble(),
                                min: 0.5,
                                max: 10,
                                divisions: 19,
                                label: '$_targetMB MB',
                                onChanged: (v) => setState(() => _targetMB = v.round()),
                              ),
                              Text('$_targetMB MB', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],

                  if (_isSingleDoc) ...[
                    // Signature Section
                    Text('Signature', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppShape.cardRadius)),
                      child: _signatureBytes == null
                          ? SizedBox(
                              height: 52,
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _addSignature,
                                icon: const Icon(Icons.draw_outlined, size: 22),
                                label: const Text('Add Signature', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.green),
                                    const SizedBox(width: AppSpacing.sm),
                                    const Expanded(child: Text('Signature added — drag it on the preview')),
                                    TextButton(onPressed: _removeSignature, child: const Text('Remove')),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Signed pages: ${(_signaturePlacements.keys.toList()..sort()).map((i) => i + 1).join(', ')}',
                                  style: TextStyle(color: textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                    ),
                  ],
                ],
              ),
      ),
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

  Widget _buildFormatCard(ExportFormat format, String label, IconData icon, Color accent) {
    final isSelected = _selectedFormat == format;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return GestureDetector(
      onTap: () => setState(() => _selectedFormat = format),
      child: Container(
        width: 62,
        height: 84,
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.15) : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3), width: isSelected ? 2 : 1),
          boxShadow: isSelected ? AppShadows.ambient : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? accent : textPrimary, size: 22),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: isSelected ? accent : textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompressionChip(CompressionTier tier, String label, Color accent) {
    final isSelected = _selectedCompression == tier;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return GestureDetector(
      onTap: () => setState(() => _selectedCompression = tier),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3)),
          boxShadow: isSelected ? AppShadows.ambient : null,
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : textPrimary, fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildDocxModeChip(ExportDocxMode mode, String label, Color accent) {
    final isSelected = _docxMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return GestureDetector(
      onTap: () => setState(() => _docxMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3)),
          boxShadow: isSelected ? AppShadows.ambient : null,
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : textPrimary, fontWeight: FontWeight.w700, fontSize: 11), textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildPageFormatChip(ExportPageFormat format, String label, Color accent) {
    final isSelected = _pageFormat == format;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return GestureDetector(
      onTap: () => setState(() => _pageFormat = format),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3)),
          boxShadow: isSelected ? AppShadows.ambient : null,
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : textPrimary, fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.center),
      ),
    );
  }
  Widget _buildLivePreview() {
    if (_documents.isEmpty) return const SizedBox.shrink();
    if (!_isSingleDoc) {
      return FutureBuilder<Map<String, dynamic>>(
        future: _generatePreview(0),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
          final imgBytes = snapshot.data!['bytes'] as Uint8List;
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
                Positioned.fill(child: Image.memory(imgBytes, fit: BoxFit.contain)),
                const Positioned(
                  top: 4, left: 4,
                  child: Text('Batch export — signature placement disabled', style: TextStyle(color: Colors.white70, fontSize: 11, backgroundColor: Colors.black38)),
                ),
              ],
            ),
          );
        },
      );
    }
    final pageCount = _documents.first.pagePaths.length;
    final pageIndex = _previewPage.clamp(0, pageCount - 1);
    final placement = _signaturePlacements[pageIndex];
    return Column(
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: pageIndex > 0 ? () => setState(() => _previewPage = pageIndex - 1) : null),
            Text('Page ${pageIndex + 1} / $pageCount', style: const TextStyle(fontSize: 13)),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: pageIndex < pageCount - 1 ? () => setState(() => _previewPage = pageIndex + 1) : null),
            const Spacer(),
            if (_signatureBytes != null && placement == null)
              ActionChip(
                avatar: const Icon(Icons.draw_outlined, size: 14),
                label: const Text('Sign this page too', style: TextStyle(fontSize: 11)),
                onPressed: () => setState(() {
                  _signaturePlacements[pageIndex] = const SignaturePlacement(pctX: 0.5, pctY: 0.35);
                }),
              ),
          ],
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _generatePreview(pageIndex),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
            final data = snapshot.data!;
            final imgBytes = data['bytes'] as Uint8List;
            final imgW = (data['w'] as int).toDouble();
            final imgH = (data['h'] as int).toDouble();
            return SizedBox(
              height: 260,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double iw = constraints.maxWidth;
                  double ih = iw * (imgH / imgW);
                  double dx = 0;
                  double dy = 0;
                  if (ih > constraints.maxHeight) {
                    ih = constraints.maxHeight;
                    iw = ih * (imgW / imgH);
                    dx = (constraints.maxWidth - iw) / 2;
                  } else {
                    dy = (constraints.maxHeight - ih) / 2;
                  }
                  final sigW = iw * 0.28 * (placement?.scale ?? 1.0);
                  return Stack(
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
                  );
                },
              ),
            );
          },
        ),
        if (_signatureBytes != null && placement != null) ...[
          Row(
            children: [
              const Text('Rotate', style: TextStyle(fontSize: 12)),
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
              Text('${placement.rotationDegrees.round()}°', style: const TextStyle(fontSize: 12)),
            ],
          ),
          Row(
            children: [
              const Text('Scale', style: TextStyle(fontSize: 12)),
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
              Text('${placement.scale.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  for (int i = 0; i < pageCount; i++) {
                    _signaturePlacements[i] = placement;
                  }
                }),
                child: const Text('Copy to all pages'),
              ),
              TextButton(
                onPressed: () => setState(() => _signaturePlacements.remove(pageIndex)),
                child: const Text('Clear this page'),
              ),
              TextButton(
                onPressed: () => setState(() => _signaturePlacements.clear()),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<Map<String, dynamic>> _generatePreview(int pageIndex) async {
    final paths = _documents.first.pagePaths;
    final idx = pageIndex.clamp(0, paths.length - 1);
    final key = '${idx}_${_selectedFilter.index}';
    final cached = _previewCache[key];
    if (cached != null) return cached;
    final bytes = await File(paths[idx]).readAsBytes();
    final result = await compute(_previewIsolate, {'bytes': bytes, 'filter': _selectedFilter.index});
    _previewCache[key] = result;
    return result;
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
