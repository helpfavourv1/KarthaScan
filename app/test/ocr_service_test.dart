import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ocr_service.dart';

void main() {
  group('OcrScript', () {
    test('Only Latin script is available', () {
      expect(OcrScript.values.length, 1);
      expect(OcrScript.latin, isNotNull);
    });
  });
}
