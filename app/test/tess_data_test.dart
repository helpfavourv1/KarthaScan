import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:katharscan/core/services/tess_data.dart';

void main() {
  test('every Tesseract script maps to a known pack', () {
    final tess = OcrScript.values.where((s) => s.usesTesseract).toList();
    expect(tess.length, 7);
    for (final s in tess) {
      expect(TessData.packs.containsKey(s.tessCode), isTrue, reason: '$s');
    }
    expect(OcrScript.latin.usesTesseract, isFalse);
    expect(OcrScript.chinese.usesTesseract, isFalse);
  });

  test('hosted language files match the pinned size and checksum', () {
    for (final e in TessData.packs.entries) {
      final f = File('../website/tessdata/${e.value.fileName}');
      expect(f.existsSync(), isTrue, reason: e.key);
      final bytes = f.readAsBytesSync();
      expect(bytes.length, e.value.bytes, reason: e.key);
      expect(sha256.convert(bytes).toString(), e.value.sha256Hex, reason: e.key);
    }
  });
}
