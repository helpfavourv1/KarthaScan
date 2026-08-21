// lib/screens/manual_crop_screen.dart
import 'dart:async' show unawaited;
import 'dart:io' show Directory, File;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/debug_log_service.dart';
import '../core/services/ocr_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/manual_crop_overlay.dart';

enum _Stage { pickImage, crop, saving }

Future<Uint8List> _warpInIsolate(Map<String, dynamic> params) async {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final List<dynamic> cornersRaw = params['corners'] as List<dynamic>;
  final bool applyGrayscale = params['grayscale'] as bool;
  final double scaleX = params['scaleX'] as double;
  final double scaleY = params['scaleY'] as double;

  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Could not decode image');

  final List<List<double>> corners = cornersRaw.map((dynamic c) {
    return (c as List<dynamic>).map((dynamic v) => v as double).toList();
  }).toList();

  final double tlX = corners[0][0] * scaleX;
  final double tlY = corners[0][1] * scaleY;
  final double trX = corners[1][0] * scaleX;
  final double trY = corners[1][1] * scaleY;
  final double brX = corners[2][0] * scaleX;
  final double brY = corners[2][1] * scaleY;
  final double blX = corners[3][0] * scaleX;
  final double blY = corners[3][1] * scaleY;

  final img.Image warped = img.Image(width: 1000, height: 1400);
  for (int y = 0; y < 1400; y++) {
    final double t = 1400 <= 1 ? 0 : y / (1400 - 1);
    for (int x = 0; x < 1000; x++) {
      final double s = 1000 <= 1 ? 0 : x / (1000 - 1);
      final double srcX = (1 - s) * (1 - t) * tlX +
          s * (1 - t) * trX +
          s * t * brX +
          (1 - s) * t * blX;
      final double srcY = (1 - s) * (1 - t) * tlY +
          s * (1 - t) * trY +
          s * t * brY +
          (1 - s) * t * blY;
      final int clampedX = srcX.round().clamp(0, decoded.width - 1);
      final int clampedY = srcY.round().clamp(0, decoded.height - 1);
      warped.setPixel(x, y, decoded.getPixel(clampedX, clampedY));
    }
  }

  final img.Image finalImage = applyGrayscale ? img.grayscale(warped) : warped;
  return img.encodeJpg(finalImage, quality: 90);
}

class ManualCropScreen extends StatefulWidget {
  const ManualCropScreen({super.key});

  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  static const Size _displaySize = Size(360, 480);
  late final ScanProvider _scanProvider;
  final OcrService _ocrService = OcrService();
  final GlobalKey<ManualCropOverlayState> _overlayKey = GlobalKey<ManualCropOverlayState>();
  final DebugLogService _log = DebugLogService();

  _Stage _stage = _Stage.pickImage;
  String? _pickedImagePath;
  bool _applyGrayscale = false;
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
        _log.log('CROP', 'Camera returned null (user cancelled)');
        setState(() => _isPicking = false);
        return;
      }
      _log.log('CROP', 'Camera returned path: ${photo.path}');
      setState(() {
        _pickedImagePath = photo.path;
        _stage = _Stage.crop;
        _isPicking = false;
      });
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
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
      final String? path = result?.files.single.path;
      if (!mounted) return;
      if (path == null) {
        _log.log('CROP', 'FilePicker returned null (user cancelled)');
        setState(() => _isPicking = false);
        return;
      }
      _log.log('CROP', 'FilePicker returned path: $path');
      setState(() {
        _pickedImagePath = path;
        _stage = _Stage.crop;
        _isPicking = false;
      });
    } catch (e) {
      _log.log('CROP', 'FilePicker error: $e');
      if (!mounted) return;
      setState(() => _isPicking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Picker error: $e')),
      );
    }
  }

  Future<void> _confirmCrop() async {
    final String? sourcePath = _pickedImagePath;
    final List<Offset>? corners = _overlayKey.currentState?.corners;
    if (sourcePath == null || corners == null || corners.length != 4) {
      _log.log('CROP', 'Confirm crop aborted: path=$sourcePath corners=$corners');
      return;
    }

    _log.log('CROP', 'Confirm crop started');
    setState(() => _stage = _Stage.saving);

    try {
      final Uint8List sourceBytes = await File(sourcePath).readAsBytes();
      _log.log('CROP', 'Source image read: ${sourceBytes.length} bytes');

      final img.Image? decoded = img.decodeImage(sourceBytes);
      if (decoded == null) throw Exception('Could not decode the selected image.');
      _log.log('CROP', 'Image decoded: ${decoded.width}x${decoded.height}');

      final double scaleX = decoded.width / _displaySize.width;
      final double scaleY = decoded.height / _displaySize.height;
      final List<List<double>> cornerList = corners.map((Offset c) => <double>[c.dx, c.dy]).toList();

      _log.log('CROP', 'Starting warp in isolate...');
      final Uint8List warpedBytes = await compute(
        _warpInIsolate,
        <String, dynamic>{
          'bytes': sourceBytes,
          'corners': cornerList,
          'grayscale': _applyGrayscale,
          'scaleX': scaleX,
          'scaleY': scaleY,
        },
      );
      _log.log('CROP', 'Warp complete: ${warpedBytes.length} bytes');

      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory scansDir = Directory(p.join(appDir.path, 'manual_crop_pages'));
      await scansDir.create(recursive: true);
      final String outPath = p.join(
        scansDir.path,
        'manual_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(outPath).writeAsBytes(warpedBytes);
      _log.log('CROP', 'Image saved to: $outPath');

      String ocrText = '';
      try {
        _log.log('CROP', 'Starting OCR...');
        final OcrResult result = await _ocrService.recognizeText(
          imagePath: outPath,
          script: OcrScript.latin,
        );
        ocrText = result.fullText;
        _log.log('CROP', 'OCR complete: ${ocrText.length} chars');
      } on OcrUnavailableException catch (e) {
        _log.log('CROP', 'OCR unavailable: $e');
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

      _log.log('CROP', 'Importing document...');
      final bool success = await _scanProvider.importDocument(document);
      if (!mounted) return;

      if (success) {
        _log.log('CROP', 'Document imported successfully → navigating home');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document saved'), duration: Duration(seconds: 2)),
        );
        context.go('/');
      } else {
        throw Exception(_scanProvider.lastError.value ?? 'Failed to save document.');
      }
    } catch (e, stackTrace) {
      _log.log('CROP', 'CRASH: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Crash details: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
      setState(() => _stage = _Stage.crop);
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
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(AppShape.cardRadius),
                ),
                child: Text(
                  l10n.docScannerUnsupportedMessage,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: AppTypography.footnoteSize,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_stage == _Stage.pickImage)
                Expanded(
                  child: Center(
                    child: _isPicking
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
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
                                    borderRadius: BorderRadius.circular(AppShape.buttonRadius),
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
                                    borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              if (_stage == _Stage.crop && _pickedImagePath != null) ...<Widget>[
                Text(
                  l10n.manualCropInstructions,
                  style: TextStyle(color: textPrimary, fontSize: AppTypography.bodySize),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: ManualCropOverlay(
                    key: _overlayKey,
                    imageSize: _displaySize,
                    imageWidget: Image.file(
                      File(_pickedImagePath!),
                      width: _displaySize.width,
                      height: _displaySize.height,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Switch(
                      value: _applyGrayscale,
                      activeThumbColor: accent,
                      onChanged: (bool value) => setState(() => _applyGrayscale = value),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l10n.manualCropApplyGrayscale,
                      style: TextStyle(color: textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: AppShape.buttonMinHeight,
                  child: ElevatedButton(
                    onPressed: _confirmCrop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                      ),
                    ),
                    child: Text(l10n.manualCropSaveButton),
                  ),
                ),
              ],
              if (_stage == _Stage.saving)
                const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}
