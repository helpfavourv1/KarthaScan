import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ocr_service.dart';

void main() {
  group('OcrScript', () {
    test('Latin, Chinese, Korean and Japanese scripts are available', () {
      expect(OcrScript.values.length, 4);
      expect(OcrScript.latin, isNotNull);
    });
  });

  group('OCR script fallback helpers', () {
    test('visibleLength ignores whitespace', () {
      expect(OcrService.visibleLength(' a b\n\tc '), 3);
      expect(OcrService.visibleLength(''), 0);
    });

    test('needsScriptFallback triggers only for almost-empty text', () {
      expect(OcrService.needsScriptFallback(''), isTrue);
      expect(OcrService.needsScriptFallback('abc def'), isTrue);
      expect(OcrService.needsScriptFallback('This is a full line of text'), isFalse);
    });

    test('isClearlyBetter needs a clear margin', () {
      expect(OcrService.isClearlyBetter('', '你好世界你好世界你好世界'), isTrue);
      expect(OcrService.isClearlyBetter('abcdefghij', 'abcdefghijk'), isFalse);
      expect(OcrService.isClearlyBetter('abcdefghijklmnopqrst', 'a' * 22), isFalse);
      expect(OcrService.isClearlyBetter('abcd', 'a' * 12), isTrue);
    });
  });
}
