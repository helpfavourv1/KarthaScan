// lib/screens/manual_crop_screen.dart
//
// Gallery picker → manual crop overlay → grayscale/B&W filter → save as
// scan (Section 16 file #75). UX copy is Section 14's exact required
// fallback message (l10n.docScannerUnsupportedMessage) — this screen is
// where doc_scanner_service.dart's DocScannerUnsupportedException routes
// to, per Section 14: never a dead end.
//
// GALLERY PICKER: reuses file_picker (FileType.image) rather than adding
// a separate image_picker dependency — file_picker is already locked for
// Device Migration's import flow and its image-type filter integrates
// with each platform's native photo picker, so a second package for the
// same underlying capability isn't needed.
//
// PERSPECTIVE CORRECTION: the 4 dragged corners are mapped to a
// rectangle via bilinear corner interpolation (nearest-neighbor pixel
// sampling), not a true projective homography. This is a deliberate,
// documented simplification — matching Section 16 file #74's own
// "simulate perspective correction" wording — chosen because it's simple,
// well-understood math this project can implement correctly with
// confidence, for a fallback flow that only exists because the primary
// scanner already failed on this device.
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
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
  }

  Future<void> _pickImage() async {
    if (_started) return;
    _started = true;
    final FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.image);
    final String? path = result?.files.single.path;
    if (!mounted) return;
    if (path == null) {
      context.pop();
      return;
    }
    setState(() {
      _pickedImagePath = path;
      _stage = _Stage.crop;
    });
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

      // Map the overlay's display-space corners back to the source
      // image's actual pixel space.
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

      // Still run OCR on the manually-cropped page — this fallback flow
      // shouldn't produce a lesser (non-searchable) document just because
      // the primary scanner was unavailable. A failure here is handled
      // the same way scan_provider.dart's normal capture flow handles
      // it: the page is still saved, just without OCR text.
      String ocrText = '';
      try {
        final OcrResult result = await _ocrService.recognizeText(
          imagePath: outPath,
          script: OcrScript.latin,
        );
        ocrText = result.fullText;
      } on OcrUnavailableException {
        // Leave ocrText empty — never block saving the scan itself.
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
        setState(() => _stage = _Stage.crop);
      }
    } catch (_) {
      if (!mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.genericErrorMessage)),
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

  /// Bilinear corner interpolation — see this file's header for why this
  /// is a documented approximation rather than a true projective
  /// homography.
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

    if (_stage == _Stage.pickImage && !_started) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) => _pickImage());
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(l10n.manualCropTitle, style: TextStyle(color: textPrimary)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Section 14's exact required fallback copy — this is why
              // the user is on this screen at all, per
              // doc_scanner_service.dart's UNSUPPORTED handling.
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
              if (_stage == _Stage.pickImage)
                const Expanded(child: Center(child: CircularProgressIndicator())),
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
