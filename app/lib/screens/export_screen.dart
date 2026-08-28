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
  
  // Signature state
  Uint8List? _signatureBytes;
  int? _signaturePageIndex;
  double? _signatureOffsetX;
  double? _signatureOffsetY;
  double? _signatureRotation;
  ExportSignatureScope _signatureScope = ExportSignatureScope.placed;
  double _signatureScale = 1.0;

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

    final placement = await showModalBottomSheet<(int, double, double, double, double)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SignaturePlacementSheet(
        pagePaths: _documents.first.pagePaths,
        signatureBytes: signatureBytes!,
      ),
    );

    if (placement != null && mounted) {
      setState(() {
        _signatureBytes = signatureBytes;
        _signaturePageIndex = placement.$1;
        _signatureOffsetX = placement.$2;
        _signatureOffsetY = placement.$3;
        _signatureRotation = placement.$4;
        _signatureScale = placement.$5;
      });
    }
  }

  void _removeSignature() {
    setState(() {
      _signatureBytes = null;
      _signaturePageIndex = null;
      _signatureOffsetX = null;
      _signatureOffsetY = null;
      _signatureRotation = null;
      _signatureScale = 1.0;
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
          signatureBytes: _signatureBytes,
          signaturePageIndex: _signaturePageIndex,
          signatureOffsetX: _signatureOffsetX,
          signatureOffsetY: _signatureOffsetY,
          signatureRotation: _signatureRotation,
          signatureScope: _signatureScope,
          signatureScale: _signatureScale,
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
                                  const Expanded(child: Text('Signature added')),
                                  TextButton(onPressed: _removeSignature, child: const Text('Remove')),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text('Apply to:', style: TextStyle(color: textSecondary, fontSize: 12)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                children: ExportSignatureScope.values.map((scope) {
                                  final label = scope == ExportSignatureScope.placed ? 'Placed Page' : scope == ExportSignatureScope.all ? 'All Pages' : scope == ExportSignatureScope.first ? 'First Page' : 'Last Page';
                                  return ChoiceChip(
                                    label: Text(label, style: const TextStyle(fontSize: 11)),
                                    selected: _signatureScope == scope,
                                    onSelected: (_) => setState(() => _signatureScope = scope),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                  ),
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
    return FutureBuilder<Uint8List>(
      future: _generatePreview(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        return Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(snapshot.data!, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  Future<Uint8List> _generatePreview() async {
    final bytes = await File(_documents.first.pagePaths.first).readAsBytes();
    return await compute(_applyFilterIsolate, {'bytes': bytes, 'filter': _selectedFilter.index});
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

class _SignaturePlacementSheet extends StatefulWidget {
  final List<String> pagePaths;
  final Uint8List signatureBytes;
  const _SignaturePlacementSheet({required this.pagePaths, required this.signatureBytes});

  @override
  State<_SignaturePlacementSheet> createState() => _SignaturePlacementSheetState();
}

class _SignaturePlacementSheetState extends State<_SignaturePlacementSheet> {
  int _currentPageIndex = 0;
  Offset _signatureOffset = Offset.zero;
  double _rotationDegrees = 0;
  double _scale = 1.0;
  final GlobalKey _stackKey = GlobalKey();
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final currentPagePath = widget.pagePaths[_currentPageIndex];
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Place signature', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPageIndex > 0 ? () => setState(() => _currentPageIndex--) : null),
                      Text('Page ${_currentPageIndex + 1} / ${widget.pagePaths.length}', style: const TextStyle(fontSize: 14)),
                      IconButton(icon: const Icon(Icons.chevron_right), onPressed: _currentPageIndex < widget.pagePaths.length - 1 ? () => setState(() => _currentPageIndex++) : null),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_initialized) {
                    _initialized = true;
                    _signatureOffset = Offset(constraints.maxWidth * 0.6, constraints.maxHeight * 0.7);
                  }
                  return Stack(
                    key: _stackKey,
                    children: [
                      Positioned.fill(child: Image.file(File(currentPagePath), fit: BoxFit.contain)),
                      Positioned(
                        left: _signatureOffset.dx,
                        top: _signatureOffset.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) => setState(() {
                            _signatureOffset += details.delta;
                            _signatureOffset = Offset(
                              _signatureOffset.dx.clamp(0.0, constraints.maxWidth - 100).toDouble(),
                              _signatureOffset.dy.clamp(0.0, constraints.maxHeight - 50).toDouble(),
                            );
                          }),
                          child: Transform.rotate(
                            angle: _rotationDegrees * 3.14159 / 180,
                            child: Opacity(opacity: 0.8, child: Image.memory(widget.signatureBytes, width: 100 * _scale, height: 50 * _scale, fit: BoxFit.contain)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // Scale slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Scale', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _scale,
                      min: 0.5,
                      max: 3.0,
                      onChanged: (value) => setState(() => _scale = value),
                    ),
                  ),
                  Text('${_scale.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            // Rotation slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Rotation', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _rotationDegrees,
                      min: -180,
                      max: 180,
                      onChanged: (value) => setState(() => _rotationDegrees = value),
                    ),
                  ),
                  Text('${_rotationDegrees.round()}°', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () {
                      final RenderBox? box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
                      final Size size = box?.size ?? const Size(1, 1);
                      final double pctX = (_signatureOffset.dx / size.width).clamp(0.0, 1.0).toDouble();
                      final double pctY = (_signatureOffset.dy / size.height).clamp(0.0, 1.0).toDouble();
                      Navigator.pop(context, (_currentPageIndex, pctX, pctY, _rotationDegrees, _scale));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


Uint8List _applyFilterIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final filter = FilterType.values[args['filter'] as int];
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final filtered = FilterService.applyToImage(decoded, filter);
  return Uint8List.fromList(img.encodeJpg(filtered, quality: 85));
}
