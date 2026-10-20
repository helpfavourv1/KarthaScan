import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'debug_log_service.dart';
import 'tess_data.dart';
import '../models/ocr_block.dart';
import '../utils/constants.dart';
import '../utils/app_locale.dart';

enum OcrScript {
  latin,
  chinese,
  korean,
  japanese,
  devanagari,
  arabic,
  russian,
  ukrainian,
  greek,
  hebrew,
  thai,
  bengali;

  /// Tesseract language code for scripts ML Kit does not cover, else null.
  String? get tessCode => switch (this) {
        OcrScript.arabic => 'ara',
        OcrScript.russian => 'rus',
        OcrScript.ukrainian => 'ukr',
        OcrScript.greek => 'ell',
        OcrScript.hebrew => 'heb',
        OcrScript.thai => 'tha',
        OcrScript.bengali => 'ben',
        _ => null,
      };

  bool get usesTesseract => tessCode != null;
}

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

/// Asks Google Play services to download an OCR language pack (Android). The
/// recognizer alone does not start the download reliably. iOS bundles the
/// models, so the missing channel there counts as ready.
class OcrModels {
  OcrModels._();

  static const MethodChannel _channel = MethodChannel('com.zdmgold.katharscan/ocr_models');
  static final Set<OcrScript> _ready = <OcrScript>{};

  /// Last error text from Play services per script, for the settings screen.
  static final Map<OcrScript, String> lastError = <OcrScript, String>{};

  /// 'ready', 'downloading', 'missing' (only when [install] is false) or
  /// 'unavailable' (no answer from Play services; the recognizer is then
  /// tried anyway).
  static Future<String> ensure(OcrScript script, {bool install = true}) async {
    if (script == OcrScript.latin || _ready.contains(script)) return 'ready';
    try {
      final String? r = await _channel.invokeMethod<String>('ensure', <String, Object>{'script': script.name, 'install': install});
      if (r == 'ready') _ready.add(script);
      lastError.remove(script);
      return r ?? 'unavailable';
    } on MissingPluginException {
      _ready.add(script);
      return 'ready';
    } on PlatformException catch (e) {
      lastError[script] = e.message ?? e.code;
      return 'unavailable';
    }
  }

  /// Requests the download and waits (up to [timeout]) until Play services has
  /// finished it. Returns true when the pack is ready.
  static Future<bool> download(OcrScript script, {Duration timeout = const Duration(minutes: 3)}) async {
    String state = await ensure(script);
    final DateTime end = DateTime.now().add(timeout);
    while (state == 'downloading' && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      state = await ensure(script, install: false);
    }
    return state == 'ready';
  }
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
    if (script.usesTesseract) return _recognizeWithTesseract(imagePath, script);
    try {
      if (await OcrModels.ensure(script) == 'downloading') {
        final result = (AppLocale.l10n.ocrLanguagePackNotReady, false);
        _scriptFailures[script] = result;
        throw OcrUnavailableException(result.$1);
      }
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

  /// Share of words that look like real words: letters in one consistent case
  /// pattern, or plain numbers. Latin recognition of a Cyrillic or Greek page
  /// returns long lookalike strings ("BnarogapuM", "3akas") that score low.
  static double wordQuality(String text) {
    int good = 0;
    int total = 0;
    final RegExp letters = RegExp(r'^\p{L}+$', unicode: true);
    final RegExp number = RegExp(r'^[\d.,:/\-%]+$');
    for (final String raw in text.split(RegExp(r'\s+'))) {
      final String t = raw.replaceAll(RegExp(r'^[\p{P}\p{S}]+|[\p{P}\p{S}]+$', unicode: true), '');
      if (t.length < 3) continue;
      total++;
      if (number.hasMatch(t)) {
        good++;
      } else if (letters.hasMatch(t)) {
        final bool lower = t == t.toLowerCase();
        final bool upper = t == t.toUpperCase();
        final bool capital = t.substring(1) == t.substring(1).toLowerCase();
        if (lower || upper || capital) good++;
      }
    }
    return total == 0 ? 1 : good / total;
  }

  /// True when the Latin result has enough text but reads like misread
  /// letters from another alphabet.
  static bool looksGarbled(String text) => visibleLength(text) >= 12 && wordQuality(text) < 0.6;

  /// Recognizes text with the Latin script first. If that finds almost
  /// nothing, tries Chinese, Japanese and Korean (skipping scripts already
  /// known to be unavailable) and keeps the clearly better result.
  Future<OcrResult> recognizeTextAuto({required String imagePath}) async {
    OcrResult best = await recognizeText(imagePath: imagePath, script: OcrScript.latin);
    if (!needsScriptFallback(best.fullText)) {
      if (looksGarbled(best.fullText)) return _betterFromInstalledPacks(imagePath, best);
      return best;
    }

    for (final OcrScript script in const <OcrScript>[
      OcrScript.chinese,
      OcrScript.japanese,
      OcrScript.korean,
      OcrScript.devanagari,
    ]) {
      // Only a script that can never work is skipped; "still downloading" is retried.
      if (lastFailureFor(script)?.$2 ?? false) continue;
      try {
        final OcrResult candidate = await recognizeText(imagePath: imagePath, script: script);
        if (isClearlyBetter(best.fullText, candidate.fullText)) best = candidate;
        // Enough text found: the remaining scripts would only repeat the work.
        if (!needsScriptFallback(best.fullText)) break;
      } on OcrUnavailableException {
        // Script not available on this device; keep what we have.
      }
    }
    if (!needsScriptFallback(best.fullText)) return best;

    // Tesseract packs the user already installed. Never downloaded here: a
    // scan must not start a 4 MB download by itself.
    for (final OcrScript script in OcrScript.values.where((OcrScript s) => s.usesTesseract)) {
      if (!await TessData.isInstalled(script.tessCode!)) continue;
      try {
        final OcrResult candidate = await _recognizeWithTesseract(imagePath, script);
        if (isClearlyBetter(best.fullText, candidate.fullText)) best = candidate;
        if (!needsScriptFallback(best.fullText)) break;
      } on OcrUnavailableException {
        // Keep what we have.
      }
    }
    return best;
  }

  /// Tries the Tesseract packs the user installed and keeps a result whose
  /// words are clearly more word-like than the Latin guess.
  Future<OcrResult> _betterFromInstalledPacks(String imagePath, OcrResult latin) async {
    OcrResult best = latin;
    double bestQuality = wordQuality(latin.fullText);
    for (final OcrScript script in OcrScript.values.where((OcrScript s) => s.usesTesseract)) {
      if (!await TessData.isInstalled(script.tessCode!)) continue;
      try {
        final OcrResult candidate = await _recognizeWithTesseract(imagePath, script);
        final double q = wordQuality(candidate.fullText);
        if (q > bestQuality + 0.2 && visibleLength(candidate.fullText) >= visibleLength(latin.fullText) * 0.5) {
          best = candidate;
          bestQuality = q;
        }
      } on OcrUnavailableException {
        // Keep what we have.
      }
    }
    return best;
  }

  static const MethodChannel _tessChannel = MethodChannel('com.zdmgold.katharscan/tess_ocr');

  /// Tesseract OCR (Android). The language file is downloaded on first use.
  Future<OcrResult> _recognizeWithTesseract(String imagePath, OcrScript script) async {
    final String code = script.tessCode!;
    if (!Platform.isAndroid) {
      final result = (AppLocale.l10n.ocrStatusUnsupported, true);
      _scriptFailures[script] = result;
      throw OcrUnavailableException(result.$1);
    }
    try {
      if (!await TessData.ensure(code)) {
        final result = (AppLocale.l10n.ocrNoInternetMessage, false);
        _scriptFailures[script] = result;
        throw OcrUnavailableException(result.$1);
      }
      final Map<Object?, Object?>? raw = await _tessChannel
          .invokeMapMethod<Object?, Object?>('extract', <String, Object>{
        'imagePath': imagePath,
        'dataPath': (await TessData.root()).path,
        'language': code,
      }).timeout(const Duration(seconds: 90));
      final List<Object?> lines = (raw?['lines'] as List<Object?>?) ?? const <Object?>[];
      final List<OcrBlock> blocks = <OcrBlock>[];
      for (final Object? l in lines) {
        final Map<Object?, Object?> m = l! as Map<Object?, Object?>;
        final String text = (m['text'] as String? ?? '').trim();
        if (text.isEmpty) continue;
        blocks.add(OcrBlock(
          text: text,
          boundingBox: OcrBoundingBox(
            left: (m['left'] as num).toDouble(),
            top: (m['top'] as num).toDouble(),
            width: (m['width'] as num).toDouble(),
            height: (m['height'] as num).toDouble(),
          ),
          confidence: ((m['confidence'] as num?) ?? 100).toDouble() / 100,
          language: code,
        ));
      }
      _scriptFailures.remove(script);
      return OcrResult(fullText: ((raw?['text'] as String?) ?? '').trim(), blocks: blocks);
    } on OcrUnavailableException {
      rethrow;
    } catch (error) {
      _log.log('OCR', 'Tesseract failed for $script: $error');
      final result = (AppPluginFailureCopy.ocrUnavailableTooltip, true);
      _scriptFailures[script] = result;
      throw OcrUnavailableException(result.$1);
    }
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
      case OcrScript.devanagari:
        return TextRecognitionScript.devanagiri;
      default:
        throw StateError('$script is handled by Tesseract');
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
