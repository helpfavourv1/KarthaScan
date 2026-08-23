import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ocr_service.dart';

void main() {
  group('OcrScript', () {
    test('All scripts are available without Pro gating', () {
      expect(OcrScript.values.length, 5);
      expect(OcrScript.latin, isNotNull);
      expect(OcrScript.chinese, isNotNull);
      expect(OcrScript.devanagari, isNotNull);
      expect(OcrScript.japanese, isNotNull);
      expect(OcrScript.korean, isNotNull);
    });
  });
}
