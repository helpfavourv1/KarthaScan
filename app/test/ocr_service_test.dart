import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ocr_service.dart';

void main() {
  group('OcrScript', () {
    test('Latin, Chinese, Korean and Japanese scripts are available', () {
      expect(OcrScript.values.length, 4);
      expect(OcrScript.latin, isNotNull);
    });
  });
}
