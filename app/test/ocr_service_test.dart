// test/ocr_service_test.dart
//
// Unit tests: OCR on sample image, empty image handling, language
// detection (Section 16 file #71).
//
// HONESTY NOTE: google_mlkit_text_recognition wraps a native platform
// channel (ML Kit on Android, VisionKit-adjacent on iOS). A plain
// `flutter test` run is a headless Dart VM with no device/emulator and no
// platform channel implementation registered — calling the real
// TextRecognizer.processImage() here would fail, not because OcrService
// is broken, but because there's no ML Kit to call. Properly mocking that
// channel would require knowing its exact internal method-call protocol
// (channel name, method names, argument shapes), which is not part of
// the package's public Dart API and wasn't independently verified
// anywhere in this project — inventing a mock protocol would mean testing
// against assumptions, not against anything real, which is worse than no
// test. So: what's genuinely testable without a device (the OcrScript
// enum's Pro gate, the exception types, OcrResult's shape) is tested for
// real below. What needs actual ML Kit is marked `skip:` with the reason
// stated, not silently omitted or faked.
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/ocr_block.dart';
import 'package:katharscan/core/services/ocr_service.dart';

void main() {
  group('OcrScriptProGate', () {
    test('latin is the only free script', () {
      expect(OcrScript.latin.isProOnly, isFalse);
    });

    test('every non-latin script is Pro-gated', () {
      for (final OcrScript script in OcrScript.values) {
        if (script == OcrScript.latin) continue;
        expect(
          script.isProOnly,
          isTrue,
          reason: '${script.name} should be Pro-gated',
        );
      }
    });

    test('covers exactly the scripts ML Kit Text Recognition supports', () {
      // Verified against the package's own docs during Phase 2 — no
      // Arabic, no Hebrew. If this list ever grows, ocr_service.dart's
      // file header comment and the paywall/settings copy referencing
      // "CJK, Hindi" need updating in the same change.
      final Set<String> names = OcrScript.values.map((s) => s.name).toSet();
      expect(
        names,
        equals(<String>{'latin', 'chinese', 'devanagari', 'japanese', 'korean'}),
      );
    });
  });

  group('OcrUnavailableException', () {
    test('carries the exact Section 14 tooltip copy through to toString', () {
      const OcrUnavailableException error =
          OcrUnavailableException('OCR unavailable on this device.');
      expect(error.message, 'OCR unavailable on this device.');
      expect(error.toString(), contains('OCR unavailable on this device.'));
    });
  });

  group('OcrResult', () {
    test('holds full text and blocks together', () {
      const OcrBoundingBox box =
          OcrBoundingBox(left: 0, top: 0, width: 10, height: 10);
      const OcrBlock block = OcrBlock(
        text: 'hello',
        boundingBox: box,
        confidence: 1.0,
        language: 'en',
      );
      const OcrResult result = OcrResult(fullText: 'hello', blocks: <OcrBlock>[block]);

      expect(result.fullText, 'hello');
      expect(result.blocks, hasLength(1));
      expect(result.blocks.single.text, 'hello');
    });
  });

  group('OcrService.recognizeText (requires a connected device)', () {
    test(
      'runs OCR on a sample image and returns recognized text',
      () {},
      skip: 'Needs a real device/emulator — ML Kit\'s platform channel is '
          'not available in a headless flutter test run, and this '
          'project has no verified mock protocol for it. Run on a real '
          'device or via integration_test instead.',
    );

    test(
      'throws OcrUnavailableException for an unreadable/empty image path',
      () {},
      skip: 'Same platform-channel limitation as above.',
    );

    test(
      'detects Chinese/Japanese/Korean/Devanagari text when the matching '
      'OcrScript is requested',
      () {},
      skip: 'Same platform-channel limitation as above.',
    );
  });
}
