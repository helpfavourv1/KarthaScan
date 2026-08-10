// lib/core/services/ocr_service.dart
//
// ML Kit Text Recognition wrapper (Section 16 file #14). On-device. Latin
// script bundled free. Pro non-Latin scripts per Section 16 file #14's own
// delivery-mechanism notes: Android auto-downloads the unbundled model via
// Google Play Services + manifest meta-data; iOS bundles the language pods
// via CocoaPods. Neither of those delivery mechanisms is code this file
// can express directly — Android's meta-data goes in
// AndroidManifest.xml (file #59) and iOS's pods go in the Podfile — this
// file only needs to *request* the right script and let the platform
// project config supply the model.
//
// SCRIPT COVERAGE (verified against the current google_mlkit_text_
// recognition package docs, not assumed from memory): the package
// supports TextRecognitionScript.latin, .chinese, .devanagari, .japanese,
// .korean. It does NOT support Arabic or Hebrew script recognition at
// all — that's a real capability gap versus Section 19's original "CJK,
// Arabic, Hebrew, Hindi" Pro copy, resolved by dropping Arabic/Hebrew from
// the OCR-language promise (Devanagari covers Hindi; Arabic/Hebrew remain
// RTL *interface* languages per Section 18, not OCR scripts) rather than
// adding a second OCR engine or a cloud API, which would contradict the
// on-device/$0-cost/no-backend commitments locked in Sections 1 and 13.
//
// CONFIDENCE FIELD: the package's documented usage (pub.dev) shows
// TextBlock exposing .boundingBox, .cornerPoints, .text, and
// .recognizedLanguages — it does not document a .confidence getter on the
// Flutter wrapper's TextBlock/TextElement as part of its stable public
// API. Rather than reference a getter that may not compile against the
// pinned package version, OcrBlock.confidence is set to a documented
// sentinel (1.0) here. If a future package version adds a verified
// confidence API, this is the one place to wire it in.
//
// LAYERING: imports google_mlkit_text_recognition (a plugin) directly,
// per the confirmed core/services/ layering — uniform cross-platform
// behavior, no OS-branching logic in this file. No dart:io: the ML Kit
// Rect type returned by TextBlock.boundingBox is consumed via inferred
// typing only (`.left`/`.top`/`.width`/`.height`), never named explicitly,
// so no `dart:ui` import is needed either.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/ocr_block.dart';
import '../utils/constants.dart';

/// OCR script packs this app offers. [latin] is the free, bundled default
/// (Section 19 Free tier). Every other value is Pro-gated at the
/// UI/subscription layer (Section 19) — this enum does not enforce that
/// itself; subscription_provider.dart / paywall_screen.dart do.
enum OcrScript { latin, chinese, devanagari, japanese, korean }

extension OcrScriptProGate on OcrScript {
  bool get isProOnly => this != OcrScript.latin;
}

/// Thrown when ML Kit fails to process an image for any reason — model
/// unavailable, corrupt image, out of memory, etc. Callers (typically
/// scan_provider.dart) should catch this and disable the OCR affordance
/// with [AppPluginFailureCopy.ocrUnavailableTooltip] per Section 14. This
/// service never lets a recognition failure propagate as an unhandled
/// crash.
class OcrUnavailableException implements Exception {
  const OcrUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'OcrUnavailableException: $message';
}

class OcrResult {
  const OcrResult({required this.fullText, required this.blocks});

  final String fullText;
  final List<OcrBlock> blocks;
}

class OcrService {
  final Map<OcrScript, TextRecognizer> _recognizers = <OcrScript, TextRecognizer>{};

  /// Runs OCR on the image at [imagePath] using [script]. Throws
  /// [OcrUnavailableException] — never lets the underlying platform
  /// exception escape uncaught — on any failure, per Section 14's "never
  /// crash" rule for this exact plugin.
  Future<OcrResult> recognizeText({
    required String imagePath,
    required OcrScript script,
  }) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final TextRecognizer recognizer = _recognizerFor(script);
      final recognizedText = await recognizer.processImage(inputImage);

      final List<OcrBlock> blocks = recognizedText.blocks
          .map((block) => _blockFromMlKit(block, script))
          .toList();

      return OcrResult(fullText: recognizedText.text, blocks: blocks);
    } catch (error, stackTrace) {
      _logError('recognizeText', error, stackTrace);
      throw const OcrUnavailableException(
        AppPluginFailureCopy.ocrUnavailableTooltip,
      );
    }
  }

  /// Lightweight availability probe scan_provider.dart can use to disable
  /// the OCR button proactively (per Section 14) rather than waiting for a
  /// user-triggered failure. Attempts to construct a Latin recognizer,
  /// since Latin is the one script every install must support.
  Future<bool> isAvailable() async {
    try {
      _recognizerFor(OcrScript.latin);
      return true;
    } catch (error, stackTrace) {
      _logError('isAvailable', error, stackTrace);
      return false;
    }
  }

  TextRecognizer _recognizerFor(OcrScript script) {
    return _recognizers.putIfAbsent(
      script,
      () => TextRecognizer(script: _toMlKitScript(script)),
    );
  }

  TextRecognitionScript _toMlKitScript(OcrScript script) {
    switch (script) {
      case OcrScript.latin:
        return TextRecognitionScript.latin;
      case OcrScript.chinese:
        return TextRecognitionScript.chinese;
      case OcrScript.devanagari:
        return TextRecognitionScript.devanagari;
      case OcrScript.japanese:
        return TextRecognitionScript.japanese;
      case OcrScript.korean:
        return TextRecognitionScript.korean;
    }
  }

  OcrBlock _blockFromMlKit(TextBlock block, OcrScript requestedScript) {
    final String language = block.recognizedLanguages.isNotEmpty
        ? block.recognizedLanguages.first
        : requestedScript.name;

    return OcrBlock(
      text: block.text,
      boundingBox: OcrBoundingBox(
        left: block.boundingBox.left,
        top: block.boundingBox.top,
        width: block.boundingBox.width,
        height: block.boundingBox.height,
      ),
      // See file header: no verified cross-platform confidence API on the
      // current package version. 1.0 is a documented sentinel, not a
      // measured value.
      confidence: 1.0,
      language: language,
    );
  }

  /// Releases all opened recognizers' native resources. Call from
  /// scan_provider.dart's dispose path.
  Future<void> dispose() async {
    for (final TextRecognizer recognizer in _recognizers.values) {
      try {
        await recognizer.close();
      } catch (error, stackTrace) {
        _logError('dispose', error, stackTrace);
      }
    }
    _recognizers.clear();
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[OcrService] $operation failed: $error');
  }
}
