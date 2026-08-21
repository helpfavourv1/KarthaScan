// lib/screens/manual_crop_screen.dart
import 'dart:async' show unawaited;
import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/ocr_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/manual_crop_overlay.dart';

enum _Stage { pickImage, crop, saving }

class ManualCropScreen extends StatefulWidget {
  const ManualCropScreen({super.key});

  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  static const Size _displaySize = Size(360, 480);

  late final ScanProvider _scanProvider;
  final OcrService _ocrService = OcrService();
  final GlobalKey<ManualCropOverlayState> _overlayKey =
      GlobalKey<ManualCropOverlayState>();

  _Stage _stage = _Stage.pickImage;
  String? _pickedImagePath;
  bool _applyGrayscale = false;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
  }

  Future<void> _pickImage() async {
    if (_isPicking) return;
    
    setState(() {
      _isPicking = true;
    });

    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.image);
      final String? path = result?.files.single.path;
      
      if (!mounted) return;
      
      if (path == null) {
        // User closed the picker without selecting. Do not loop, do not pop.
        setState(() {
          _isPicking = false;
        });
        return;
      }
      
      setState(() {
        _pickedImagePath = path;
        _stage = _Stage.crop;
        _isPicking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPicking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Picker error: $e")),
      );
    }
  }

  Future<void> _confirmCrop() async {
    final String? sourcePath = _pickedImagePath;
    final List<Offset>? corners = _overlayKey.currentState?.corners;
    if (sourcePath == null || corners == null || corners.length != 4) return;

    setState(() => _stage = _Stage.saving);

    try {
      final Uint8List sourceBytes = await File(sourcePath).readAsBytes();
      final img.Image? decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        throw Exception('Could not decode the selected image.');
      }

      final double scaleX = decoded.width / _displaySize.width;
      final double scaleY = decoded.height / _displaySize.height;
      final List<Offset> sourceCorners = corners
          .map((Offset c) => Offset(c.dx * scaleX, c.dy * scaleY))
          .toList();

      img.Image warped = _warpQuadToRectangle(
        decoded,
        sourceCorners,
        outputWidth: 1000,
        outputHeight: 1400,
      );

      if (_applyGrayscale) {
        warped = img.grayscale(warped);
      }

      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory scansDir =
          Directory(p.join(appDir.path, 'manual_crop_pages'));
      await scansDir.create(recursive: true);
      final String outPath = p.join(
        scansDir.path,
        'manual_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(outPath).writeAsBytes(img.encodeJpg(warped, quality: 90));

      String ocrText = '';
      try {
        final OcrResult result = await _ocrService.recognizeText(
          imagePath: outPath,
          script: OcrScript.latin,
        );
        ocrText = result.fullText;
      } on OcrUnavailableException {
        // Handled silently
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

      final bool success = await _scanProvider.importDocument(document);
      if (!mounted) return;
      if (success) {
        context.pop();
      } else {
        throw Exception(_scanProvider.lastError.value ?? "Failed to save document.");
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      
      debugPrint('CROP CRASH: $e\n$stackTrace'); 
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Crash details: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (_stage == _Stage.saving) {
            _stage = _Stage.crop;
          }
        });
      }
    }
  }

  String _defaultTitle(DateTime when) {
    final String date =
        '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    final String time =
        '${when.hour.toString().padLeft(2, '0')}.${when.minute.toString().padLeft(2, '0')}';
    return 'Scan $date $time';
  }

  img.Image _warpQuadToRectangle(
    img.Image source,
    List<Offset> corners, {
    required int outputWidth,
    required int outputHeight,
  }) {
    final Offset topLeft = corners[0];
    final Offset topRight = corners[1];
    final Offset bottomRight = corners[2];
    final Offset bottomLeft = corners[3];

    final img.Image output = img.Image(width: outputWidth, height: outputHeight);

    for (int y = 0; y < outputHeight; y++) {
      final double t = outputHeight <= 1 ? 0 : y / (outputHeight - 1);
      for (int x = 0; x < outputWidth; x++) {
        final double s = outputWidth <= 1 ? 0 : x / (outputWidth - 1);

        final double srcX = (1 - s) * (1 - t) * topLeft.dx +
            s * (1 - t) * topRight.dx +
            s * t * bottomRight.dx +
            (1 - s) * t * bottomLeft.dx;
        final double srcY = (1 - s) * (1 - t) * topLeft.dy +
            s * (1 - t) * topRight.dy +
            s * t * bottomRight.dy +
            (1 - s) * t * bottomLeft.dy;

        final int clampedX = srcX.round().clamp(0, source.width - 1);
        final int clampedY = srcY.round().clamp(0, source.height - 1);

        output.setPixel(x, y, source.getPixel(clampedX, clampedY));
      }
    }

    return output;
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
                  style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              
              // NEW: The manual Import button phase
              if (_stage == _Stage.pickImage)
                Expanded(
                  child: Center(
                    child: _isPicking 
                      ? const CircularProgressIndicator()
                      : ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Import'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                            ),
                          ),
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
