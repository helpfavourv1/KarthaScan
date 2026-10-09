import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'debug_log_service.dart';
import '../models/ocr_block.dart';
import '../utils/constants.dart';
import '../utils/app_locale.dart';

enum OcrScript { latin, chinese, korean, japanese }

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
  final DebugLogService _log = DebugLogService();

  static final Map<OcrScript, (String, bool)> _scriptFailures = <OcrScript, (String, bool)>{};

  /// Last classified failure for a script, or null if none recorded.
  static (String, bool)? lastFailureFor(OcrScript script) => _scriptFailures[script];

  /// Clears a recorded failure so the script becomes selectable again.
  static void clearFailureFor(OcrScript script) => _scriptFailures.remove(script);

  Future<OcrResult> recognizeText({
    required String imagePath,
    required OcrScript script,
  }) async {
    _log.log('OCR', 'recognizeText started: path=$imagePath script=$script');
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final TextRecognizer recognizer = _recognizerFor(script);

      final recognizedText = await recognizer.processImage(inputImage).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          throw const OcrUnavailableException('OCR engine timed out.');
        },
      );

      final List<OcrBlock> blocks = recognizedText.blocks
          .map((block) => _blockFromMlKit(block, script))
          .toList();

      _scriptFailures.remove(script);
      return OcrResult(fullText: recognizedText.text, blocks: blocks);
    } on OcrUnavailableException {
      rethrow;
    } on PlatformException catch (e) {
      _log.log('OCR', 'PlatformException caught: ${e.message}');
      final result = _classify(e);
      _scriptFailures[script] = result;
      throw OcrUnavailableException(result.$1);
    } catch (error) {
      _log.log('OCR', 'Unhandled OCR error: $error');
      final result = _classify(error);
      _scriptFailures[script] = result;
      throw OcrUnavailableException(result.$1);
    }
  }

  /// Pages OCR'd per imported document. Keeps long PDF imports responsive.
  static const int maxOcrPages = 20;

  /// Number of visible (non-whitespace) characters in [text].
  static int visibleLength(String text) => text.replaceAll(RegExp(r'\s'), '').length;

  /// True when a Latin pass found so little text that another script may do
  /// better (for example a Chinese, Japanese or Korean page).
  static bool needsScriptFallback(String latinText) => visibleLength(latinText) < 12;

  /// True when [candidate] is clearly more complete than [current], so a
  /// similar result from another script does not replace a good Latin one.
  static bool isClearlyBetter(String current, String candidate) {
    final int have = visibleLength(current);
    final int found = visibleLength(candidate);
    return found > have + 5 && found >= have * 1.5;
  }

  /// Recognizes text with the Latin script first. If that finds almost
  /// nothing, tries Chinese, Japanese and Korean (skipping scripts already
  /// known to be unavailable) and keeps the clearly better result.
  Future<OcrResult> recognizeTextAuto({required String imagePath}) async {
    OcrResult best = await recognizeText(imagePath: imagePath, script: OcrScript.latin);
    if (!needsScriptFallback(best.fullText)) return best;

    for (final OcrScript script in const <OcrScript>[
      OcrScript.chinese,
      OcrScript.japanese,
      OcrScript.korean,
    ]) {
      if (lastFailureFor(script) != null) continue;
      try {
        final OcrResult candidate = await recognizeText(imagePath: imagePath, script: script);
        if (isClearlyBetter(best.fullText, candidate.fullText)) best = candidate;
      } on OcrUnavailableException {
        // Script not available on this device; keep what we have.
      }
    }
    return best;
  }

  /// OCR for the first [maxPages] pages, joined in page order. A page that
  /// fails is skipped; if OCR is unavailable altogether, returns what was
  /// read so far.
  Future<String> recognizeTextForPages(
    List<String> imagePaths, {
    int maxPages = maxOcrPages,
  }) async {
    final StringBuffer combined = StringBuffer();
    final int count = imagePaths.length < maxPages ? imagePaths.length : maxPages;
    for (int i = 0; i < count; i++) {
      try {
        final OcrResult result = await recognizeTextAuto(imagePath: imagePaths[i]);
        if (result.fullText.trim().isEmpty) continue;
        if (combined.isNotEmpty) combined.writeln();
        combined.write(result.fullText);
      } on OcrUnavailableException {
        break;
      } catch (error) {
        _log.log('OCR', 'Page ${i + 1} skipped: $error');
      }
    }
    return combined.toString();
  }

  Future<bool> isAvailable() async {
    try {
      _recognizerFor(OcrScript.latin);
      return true;
    } catch (_) {
      return false;
    }
  }

  (String, bool) _classify(Object error) {
    final String msg = error.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('internet') || msg.contains('connection')) {
      return (AppLocale.l10n.ocrNoInternetMessage, false);
    }
    if (msg.contains('download') || msg.contains('install') ||
        msg.contains('unavailable') || msg.contains('not available') || msg.contains('timeout')) {
      return (AppLocale.l10n.ocrLanguagePackNotReady, false);
    }
    return (AppPluginFailureCopy.ocrUnavailableTooltip, true);
  }

  TextRecognizer _recognizerFor(OcrScript script) {
    return _recognizers.putIfAbsent(
      script,
      () {
        try {
          return TextRecognizer(script: _toMlKitScript(script));
        } catch (e) {
          _log.log('OCR', 'Recognizer creation failed for $script: $e');
          final result = _classify(e);
          _scriptFailures[script] = result;
          throw OcrUnavailableException(result.$1);
        }
      },
    );
  }

  TextRecognitionScript _toMlKitScript(OcrScript script) {
    switch (script) {
      case OcrScript.latin:
        return TextRecognitionScript.latin;
      case OcrScript.chinese:
        return TextRecognitionScript.chinese;
      case OcrScript.korean:
        return TextRecognitionScript.korean;
      case OcrScript.japanese:
        return TextRecognitionScript.japanese;
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
      confidence: 1.0,
      language: language,
    );
  }

  Future<void> dispose() async {
    for (final TextRecognizer recognizer in _recognizers.values) {
      try {
        await recognizer.close();
      } catch (_) {}
    }
    _recognizers.clear();
  }
}
