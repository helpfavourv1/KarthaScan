import 'dart:async' show unawaited;
import 'dart:io' show Directory, File;

import 'package:file_picker/file_picker.dart';
import 'package:pdf_render_plus/pdf_render.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/services/debug_log_service.dart';
import '../core/services/doc_scanner_service.dart';
import '../core/services/export_service.dart';
import '../core/services/ocr_service.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';

enum _Stage { pickImage, saving }
enum _CaptureMode { docs, ocr, idCard, passport }

class ManualCropScreen extends StatefulWidget {
  const ManualCropScreen({super.key});

  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  late final ScanProvider _scanProvider;
  late final SettingsProvider _settingsProvider;
  final OcrService _ocrService = OcrService();
  final ExportService _exportService = ExportService();
  final ShareService _shareService = ShareService();
  final DebugLogService _log = DebugLogService();

  _Stage _stage = _Stage.pickImage;
  bool _isPicking = false;
  _CaptureMode _currentMode = _CaptureMode.docs;

  // ID Card State
  String? _idFrontPath;
  String? _idBackPath;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _log.log('CROP', 'ManualCropScreen initialized');
  }

  void _playCaptureFeedback() {
    if (_settingsProvider.settings.value.beepOnCapture) {
      SystemSound.play(SystemSoundType.alert);
    }
    if (_settingsProvider.settings.value.vibrateOnCapture) {
      HapticFeedback.vibrate();
    }
  }

  List<CropAspectRatioPreset> _getAspectRatios() {
    switch (_currentMode) {
      case _CaptureMode.docs:
        return [CropAspectRatioPreset.original, CropAspectRatioPreset.square, CropAspectRatioPreset.ratio4x3, CropAspectRatioPreset.ratio3x2, CropAspectRatioPreset.ratio16x9];
      case _CaptureMode.ocr:
        return [CropAspectRatioPreset.original, CropAspectRatioPreset.square, CropAspectRatioPreset.ratio4x3];
      case _CaptureMode.idCard:
        return [CropAspectRatioPreset.ratio3x2, CropAspectRatioPreset.original]; // Standard ID landscape
      case _CaptureMode.passport:
        return [CropAspectRatioPreset.ratio4x3, CropAspectRatioPreset.original]; // Passport portrait/landscape
    }
  }

  String _getModeLabel() {
    switch (_currentMode) {
      case _CaptureMode.docs: return 'Document Mode';
      case _CaptureMode.ocr: return 'OCR Mode';
      case _CaptureMode.idCard: return 'ID Card Mode';
      case _CaptureMode.passport: return 'Passport Mode';
    }
  }

  Future<void> _takePhoto() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
      if (!mounted) return;
      if (photo == null) {
        setState(() => _isPicking = false);
        return;
      }
      _playCaptureFeedback();
      setState(() => _isPicking = false);

      if (_currentMode == _CaptureMode.idCard) {
        final isFront = _idFrontPath == null;
        await _cropAndSave(photo.path, isIdFront: isFront, isIdBack: !isFront);
      } else {
        await _cropAndSave(photo.path);
      }
    } catch (e) {
      _log.log('CROP', 'Camera error: $e');
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e')));
    }
  }

  Future<void> _pickImage() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      final path = result?.files.single.path;
      if (!mounted) return;
      if (path == null) {
        setState(() => _isPicking = false);
        return;
      }
      _playCaptureFeedback();
      setState(() => _isPicking = false);

      // PDF import branch
      if (path.toLowerCase().endsWith('.pdf')) {
        await _importPdf(path);
        return;
      }

      if (_currentMode == _CaptureMode.idCard) {
        final isFront = _idFrontPath == null;
        await _cropAndSave(path, isIdFront: isFront, isIdBack: !isFront);
      } else {
        await _cropAndSave(path);
      }
    } catch (e) {
      _log.log('CROP', 'Import error: $e');
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import error: $e')));
    }
  }

  Future<void> _importPdf(String pdfPath) async {
    setState(() => _stage = _Stage.saving);
    try {
      final doc = await PdfDocument.openFile(pdfPath);
      final pageCount = doc.pageCount;
      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'pdf_import_pages'));
      await scansDir.create(recursive: true);

      final savedPaths = <String>[];
      for (int i = 1; i <= pageCount; i++) {
        final page = await doc.getPage(i);
        final renderedImage = await page.render(width: (page.width * 2).round(), height: (page.height * 2).round());
        final rawPixels = renderedImage.pixels;
        final pngImage = img.Image.fromBytes(
          width: renderedImage.width,
          height: renderedImage.height,
          bytes: rawPixels.buffer,
          numChannels: 4,
        );
        final pngBytes = img.encodePng(pngImage);
        final outPath = p.join(scansDir.path, 'pdf_${DateTime.now().microsecondsSinceEpoch}_$i.png');
        await File(outPath).writeAsBytes(pngBytes);
        savedPaths.add(outPath);
      }

      String ocrText = '';
      try {
        final result = await _ocrService.recognizeText(imagePath: savedPaths.first, script: OcrScript.latin);
        ocrText = result.fullText;
      } catch (_) {}

      final now = DateTime.now();
      final document = ScanDocument(
        id: '${now.microsecondsSinceEpoch}',
        title: 'PDF Import ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        pageCount: savedPaths.length,
        pagePaths: savedPaths,
        createdAt: now,
        updatedAt: now,
        ocrText: ocrText,
        thumbnailPath: savedPaths.first,
      );

      final success = await _scanProvider.importDocument(document);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF imported as document')));
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        context.pushReplacement('/scan/${document.id}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF import error: $e')));
    } finally {
      if (mounted) setState(() => _stage = _Stage.pickImage);
    }
  }


  Future<void> _pickAndConvertDocument() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt', 'csv'],
      );
      final path = result?.files.single.path;
      if (!mounted) return;
      if (path == null) {
        setState(() => _isPicking = false);
        return;
      }
      final ext = path.toLowerCase().split('.').last;
      String type = 'unknown';
      if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
        type = 'image';
      } else if (ext == 'pdf') {
        type = 'pdf';
      } else if (ext == 'txt') {
        type = 'txt';
      } else if (ext == 'csv') {
        type = 'csv';
      }

      context.push('/convert?path=${Uri.encodeComponent(path)}&type=$type');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pick error: $e')));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _scanDocument() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result = await DocScannerService().scan().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw const DocScannerUnsupportedException('Scanner not responding.');
        },
      );
      if (!mounted) return;
      if (result.pageImagePaths.isEmpty) {
        setState(() => _isPicking = false);
        return;
      }
      _playCaptureFeedback();
      if (_currentMode == _CaptureMode.idCard) {
        await _routeScanToIdSlots(result.pageImagePaths);
        return;
      }
      final savedDoc = await _saveScannedDocument(result.pageImagePaths);
      if (!mounted) return;
      if (savedDoc != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        context.pushReplacement('/scan/${savedDoc.id}');
      } else {
        setState(() => _isPicking = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scanner error: $e')));
    }
  }

  Future<void> _routeScanToIdSlots(List<String> paths) async {
    final appDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory(p.join(appDir.path, 'manual_crop_pages'));
    await scansDir.create(recursive: true);

    if (paths.isNotEmpty && _idFrontPath == null) {
      final outPath = p.join(scansDir.path, 'manual_${DateTime.now().microsecondsSinceEpoch}_front.jpg');
      await File(paths[0]).copy(outPath);
      setState(() => _idFrontPath = outPath);
    }
    if (paths.length > 1 && _idBackPath == null) {
      final outPath = p.join(scansDir.path, 'manual_${DateTime.now().microsecondsSinceEpoch}_back.jpg');
      await File(paths[1]).copy(outPath);
      setState(() => _idBackPath = outPath);
    }

    if (_idFrontPath != null && _idBackPath != null) {
      await _exportIdCard();
    } else {
      setState(() => _stage = _Stage.pickImage);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Front side captured. Now capture the back side.'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _exportIdCard() async {
    setState(() => _stage = _Stage.saving);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final outPath = await _exportService.exportIdCardPdf(
        frontPath: _idFrontPath!,
        backPath: _idBackPath!,
        title: 'ID Card ${DateTime.now().millisecondsSinceEpoch}',
        outputDirectoryPath: appDir.path,
      );
      _log.log('CROP', 'ID Card PDF exported: $outPath');
      if (!mounted) return;

            if (!mounted) return;

      await _showIdCardResultSheet(outPath);
      if (!mounted) return;

      setState(() {
        _idFrontPath = null;
        _idBackPath = null;
        _stage = _Stage.pickImage;
      });
    } catch (e) {
      _log.log('CROP', 'ID Card export error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating ID PDF: $e')));
      setState(() {
        _idFrontPath = null;
        _idBackPath = null;
        _stage = _Stage.pickImage;
      });
    }
  }

  Future<ScanDocument?> _saveScannedDocument(List<String> pagePaths) async {
    setState(() => _stage = _Stage.saving);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'manual_crop_pages'));
      await scansDir.create(recursive: true);

      final savedPaths = <String>[];
      for (int i = 0; i < pagePaths.length; i++) {
        final outPath = p.join(scansDir.path, 'manual_${DateTime.now().microsecondsSinceEpoch}_$i.jpg');
        await File(pagePaths[i]).copy(outPath);
        savedPaths.add(outPath);
      }

      String ocrText = '';
      try {
        final result = await _ocrService.recognizeText(imagePath: savedPaths.first, script: OcrScript.latin);
        ocrText = result.fullText;
      } catch (_) {}

      final now = DateTime.now();
      final document = ScanDocument(
        id: '${now.microsecondsSinceEpoch}',
        title: 'Scan ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        pageCount: savedPaths.length,
        pagePaths: savedPaths,
        createdAt: now,
        updatedAt: now,
        ocrText: ocrText,
        thumbnailPath: savedPaths.first,
      );

      final success = await _scanProvider.importDocument(document);
      return success ? document : null;
    } catch (e) {
      return null;
    } finally {
      if (mounted) setState(() => _stage = _Stage.pickImage);
    }
  }

  Future<void> _showIdCardResultSheet(String pdfPath) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ID Card PDF Generated', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await _shareService.shareFiles(filePaths: [pdfPath]);
                  } catch (_) {}
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Share PDF'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final now = DateTime.now();
                  final doc = ScanDocument(
                    id: '${now.microsecondsSinceEpoch}',
                    title: 'ID Card ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                    pageCount: 2,
                    pagePaths: [_idFrontPath!, _idBackPath!],
                    createdAt: now,
                    updatedAt: now,
                    ocrText: '',
                    thumbnailPath: _idFrontPath!,
                  );
                  final success = await _scanProvider.importDocument(doc);
                  if (!mounted) return;
                  if (success) {
                    context.pushReplacement('/scan/${doc.id}');
                  }
                },
                icon: const Icon(Icons.save_alt),
                label: const Text('Save as Document'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cropAndSave(String sourcePath, {bool isIdFront = false, bool isIdBack = false}) async {
    final ratios = _getAspectRatios();
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: _currentMode == _CaptureMode.idCard ? 'Crop ID Card' : 'Crop Document',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: ratios,
        ),
        IOSUiSettings(
          title: _currentMode == _CaptureMode.idCard ? 'Crop ID Card' : 'Crop Document',
          aspectRatioPresets: ratios,
        ),
      ],
    );

    if (!mounted || croppedFile == null) return;

    setState(() => _stage = _Stage.saving);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(p.join(appDir.path, 'manual_crop_pages'));
      await scansDir.create(recursive: true);

      final outPath = p.join(scansDir.path, 'manual_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(croppedFile.path).copy(outPath);

      if (isIdFront || isIdBack) {
        if (isIdFront) {
          setState(() => _idFrontPath = outPath);
        } else {
          setState(() => _idBackPath = outPath);
        }
        
        if (_idFrontPath != null && _idBackPath != null) {
          await _exportIdCard();
        } else {
          setState(() => _stage = _Stage.pickImage);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Front side captured. Now capture the back side.'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }

      // Standard single-page flow
      String ocrText = '';
      try {
        final result = await _ocrService.recognizeText(imagePath: outPath, script: OcrScript.latin);
        ocrText = result.fullText;
      } catch (_) {}

      final now = DateTime.now();
      final document = ScanDocument(
        id: '${now.microsecondsSinceEpoch}',
        title: 'Scan ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        pageCount: 1,
        pagePaths: [outPath],
        createdAt: now,
        updatedAt: now,
        ocrText: ocrText,
        thumbnailPath: outPath,
      );

      final success = await _scanProvider.importDocument(document);
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document saved'), duration: Duration(seconds: 2)));
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        context.pushReplacement('/scan/${document.id}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _stage = _Stage.pickImage);
    }
  }

  String _getModeCaption() {
    switch (_currentMode) {
      case _CaptureMode.docs:
        return 'Flexible crop: Original, Square, 4:3, 3:2, 16:9';
      case _CaptureMode.ocr:
        return 'Text crop: Original, Square, 4:3';
      case _CaptureMode.idCard:
        return 'Two-sided ID capture: Front + Back';
      case _CaptureMode.passport:
        return 'Passport crop: 4:3 or Original';
    }
  }

  Widget _buildModeCard(String label, IconData icon, _CaptureMode mode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final isSelected = _currentMode == mode;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMode = mode;
          _idFrontPath = null; // Reset ID state when changing modes
          _idBackPath = null;
        });
      },
      child: Container(
        width: 74,
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
            Icon(icon, color: isSelected ? accent : textSecondary, size: 24),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: isSelected ? accent : textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_ocrService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(_getModeLabel(), style: TextStyle(color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _stage == _Stage.saving
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _buildModeCard('Document', Icons.description_outlined, _CaptureMode.docs),
                        _buildModeCard('OCR Text', Icons.text_snippet_outlined, _CaptureMode.ocr),
                        _buildModeCard('ID Card', Icons.credit_card_outlined, _CaptureMode.idCard),
                        _buildModeCard('Passport', Icons.badge_outlined, _CaptureMode.passport),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Center(
                      child: Text(
                        _getModeCaption(),
                        style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    
                    // ID Card State Indicator
                    if (_currentMode == _CaptureMode.idCard) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppShape.cardRadius)),
                        child: Column(
                          children: [
                            Text(
                              _idFrontPath == null ? 'Step 1: Capture Front Side' : 
                              _idBackPath == null ? 'Step 2: Capture Back Side' : 'Generating PDF...',
                              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
                            ),
                            if (_idFrontPath != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  const SizedBox(width: 4),
                                  Text('Front side captured', style: TextStyle(color: textSecondary, fontSize: 12)),
                                  const SizedBox(width: 12),
                                  TextButton(
                                    onPressed: () => setState(() { _idFrontPath = null; _idBackPath = null; }),
                                    child: const Text('Reset', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    if (_isPicking)
                      const Center(child: CircularProgressIndicator())
                    else
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _scanDocument,
                            icon: const Icon(Icons.document_scanner),
                            label: const Text('Auto Scan'),
                            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.buttonRadius))),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: Text(_currentMode == _CaptureMode.idCard ? 
                              (_idFrontPath == null ? 'Capture Front Side' : 'Capture Back Side') : 'Camera'),
                            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.buttonRadius))),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: Text(_currentMode == _CaptureMode.idCard ? 
                              (_idFrontPath == null ? 'Import Front Side' : 'Import Back Side') : 'Import'),
                            style: ElevatedButton.styleFrom(backgroundColor: surface, foregroundColor: textPrimary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.buttonRadius))),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (_currentMode != _CaptureMode.idCard) ...[
                            ElevatedButton.icon(
                              onPressed: _pickAndConvertDocument,
                              icon: const Icon(Icons.transform_outlined),
                              label: const Text('Import & Convert Document'),
                              style: ElevatedButton.styleFrom(backgroundColor: surface, foregroundColor: textPrimary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.buttonRadius))),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
