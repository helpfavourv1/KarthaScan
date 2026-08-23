import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'debug_log_service.dart';
import '../models/ocr_block.dart';
import '../utils/constants.dart';

enum OcrScript { latin, chinese, japanese, korean }

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

  Future<OcrResult> recognizeText({
    required String imagePath,
    required OcrScript script,
  }) async {
    _log.log('OCR', 'recognizeText started: path=$imagePath script=$script');
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final TextRecognizer recognizer = _recognizerFor(script);

      final recognizedText = await recognizer.processImage(inputImage).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw const OcrUnavailableException('OCR engine timed out.');
        },
      );

      final List<OcrBlock> blocks = recognizedText.blocks
          .map((block) => _blockFromMlKit(block, script))
          .toList();

      return OcrResult(fullText: recognizedText.text, blocks: blocks);
    } on OcrUnavailableException {
      rethrow;
    } catch (error) {
      throw const OcrUnavailableException(
        AppPluginFailureCopy.ocrUnavailableTooltip,
      );
    }
  }

  Future<bool> isAvailable() async {
    try {
      _recognizerFor(OcrScript.latin);
      return true;
    } catch (_) {
      return false;
    }
  }

  TextRecognizer _recognizerFor(OcrScript script) {
    return _recognizers.putIfAbsent(
      script,
      () => TextRecognizer(script: _toMlKitScript(script)),
    );
  }

  // Issue 6: Fix Devanagari mapping (was returning Latin)
  TextRecognitionScript _toMlKitScript(OcrScript script) {
    switch (script) {
      case OcrScript.latin:
        return TextRecognitionScript.latin;
      case OcrScript.chinese:
        return TextRecognitionScript.chinese;
        } catch (_) {
          return TextRecognitionScript.latin;
        }
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
