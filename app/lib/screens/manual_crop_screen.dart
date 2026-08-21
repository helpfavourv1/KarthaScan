// lib/screens/manual_crop_screen.dart
import 'dart:async' show unawaited;
import 'dart:io' show Directory, File;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/debug_log_service.dart';
import '../core/services/doc_scanner_service.dart';
import '../core/services/ocr_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

enum _Stage { pickImage, saving }

class ManualCropScreen extends StatefulWidget {
  const ManualCropScreen({super.key});

  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  late final ScanProvider _scanProvider;
  final OcrService _ocrService = OcrService();
  final DebugLogService _log = DebugLogService();

  _Stage _stage = _Stage.pickImage;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _log.log('CROP', 'ManualCropScreen initialized');
  }

  Future<void> _takePhoto() async {
    if (_isPicking) return;
    _log.log('CROP', 'Camera button tapped');
    setState(() => _isPicking = true);
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (!mounted) return;
      if (photo == null) {
        _log.log('CROP', 'Camera cancelled');
        setState(() => _isPicking = false);
        return;
      }
      _log.log('CROP', 'Camera path: ${photo.path}');
      setState(() => _isPicking = false);
      await _cropAndSave(photo.path);
    } catch (e) {
      _log.log('CROP', 'Camera error: $e');
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e')),
      );
    }
  }

  Future<void> _pickImage() async {
    if (_isPicking) return;
    _log.log('CROP', 'Import button tapped');
    setState(() => _isPicking = true);
    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.any);
      final String? path = result?.files.single.path;
      if (!mounted) return;
      if (path == null) {
        _log.log('CROP', 'Import cancelled');
        setState(() => _isPicking = false);
        return;
      }
      final String ext = p.extension(path).toLowerCase();
      const List<String> validExts = <String>[
        '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'
      ];
      if (!validExts.contains(ext)) {
        _log.log('CROP', 'Import rejected non-image: $path');
        setState(() => _isPicking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an image file (JPG, PNG, GIF, BMP, WEBP).'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      _log.log('CROP', 'Import path: $path');
      setState(() => _isPicking = false);
      await _cropAndSave(path);
    } catch (e) {
      _log.log('CROP', 'Import error: $e');
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import error: $e')),
      );
    }
  }

  Future<void> _scanDocument() async {
    if (_isPicking) return;
    _log.log('CROP', 'Scan button tapped');
    setState(() => _isPicking = true);
    try {
      final DocScanResult result = await DocScannerService().scan();
      if (!mounted) return;
      if (result.pageImagePaths.isEmpty) {
        _log.log('CROP', 'Scanner returned empty');
        setState(() => _isPicking = false);
        return;
      }
      _log.log('CROP', 'Scanner path: ${result.pageImagePaths.first}');
      setState(() => _isPicking = false);
      await _cropAndSave(result.pageImagePaths.first);
    } on DocScannerUnsupportedException catch (_) {
      _log.log('CROP', 'Scanner unsupported on this device');
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Document scanner not available on this device. Use Camera or Import instead.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      _log.log('CROP', 'Scanner error: $e');
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scanner error: $e')),
      );
    }
  }

  Future<void> _cropAndSave(String sourcePath) async {
    _log.log('CROP', 'Opening cropper: $sourcePath');
    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: 'Crop Document',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: <CropAspectRatioPreset>[
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Crop Document',
          aspectRatioPresets: <CropAspectRatioPreset>[
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio3x2,
          ],
        ),
      ],
    );

    if (!mounted) return;
    if (croppedFile == null) {
      _log.log('CROP', 'Crop cancelled');
      return;
    }
    _log.log('CROP', 'Cropped: ${croppedFile.path}');

    setState(() => _stage = _Stage.saving);

    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory scansDir =
          Directory(p.join(appDir.path, 'manual_crop_pages'));
      await scansDir.create(recursive: true);
      final String outPath = p.join(
        scansDir.path,
        'manual_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(croppedFile.path).copy(outPath);
      _log.log('CROP', 'Saved to: $outPath');

      String ocrText = '';
      try {
        _log.log('CROP', 'Starting OCR...');
        final OcrResult result = await _ocrService.recognizeText(
          imagePath: outPath,
          script: OcrScript.latin,
        );
        ocrText = result.fullText;
        _log.log('CROP', 'OCR done: ${ocrText.length} chars');
      } on OcrUnavailableException catch (_) {
        _log.log('CROP', 'OCR unavailable');
      }

      final DateTime now = DateTime.now();
      final ScanDocument document = ScanDocument(
        id: '${now.microsecondsSinceEpoch}',
        title: _defaultTitle(now),
        pageCount: 1,
        pagePaths: <String>[outPath],
        createdAt: now,
        updatedAt: now,
        ocrText: ocrText,
        thumbnailPath: outPath,
      );

      _log.log('CROP', 'Importing...');
      final bool success = await _scanProvider.importDocument(document);
      if (!mounted) return;

      if (success) {
        _log.log('CROP', 'Saved → home');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document saved'),
            duration: Duration(seconds: 2),
          ),
        );
        context.go('/');
      } else {
        throw Exception(
          _scanProvider.lastError.value ?? 'Failed to save document.',
        );
      }
        } catch (e) {
      _log.log('CROP', 'CRASH: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _stage = _Stage.pickImage);
    }
  }

  String _defaultTitle(DateTime when) {
    final String date =
        '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    final String time =
        '${when.hour.toString().padLeft(2, '0')}.${when.minute.toString().padLeft(2, '0')}';
    return 'Scan $date $time';
  }

  @override
  void dispose() {
    unawaited(_ocrService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color surface =
        isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(l10n.manualCropTitle, style: TextStyle(color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _stage == _Stage.saving
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius:
                            BorderRadius.circular(AppShape.cardRadius),
                      ),
                      child: Text(
                        l10n.docScannerUnsupportedMessage,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: AppTypography.footnoteSize,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_isPicking)
                      const Center(child: CircularProgressIndicator())
                    else
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ElevatedButton.icon(
                            onPressed: _scanDocument,
                            icon: const Icon(Icons.document_scanner),
                            label: const Text('Scan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShape.buttonRadius,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShape.buttonRadius,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('Import'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: surface,
                              foregroundColor: textPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShape.buttonRadius,
                                ),
                              ),
                            ),
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
