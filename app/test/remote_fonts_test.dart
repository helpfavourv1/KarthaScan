// CJK text in generated PDFs: font choice, and a real PDF made with the font
// file from the repo's fonts_remote folder (no network).
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/pdf_fonts.dart';
import 'package:katharscan/core/services/remote_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font choice by script', () {
    expect(RemoteFonts.neededFor('Hello Привет مرحبا'), isEmpty);
    expect(RemoteFonts.neededFor('文档 test'), <RemoteFont>[RemoteFonts.sc]);
    expect(RemoteFonts.neededFor('ひらがな 漢字'), <RemoteFont>[RemoteFonts.jp]);
    expect(RemoteFonts.neededFor('한국어 文书'), <RemoteFont>[RemoteFonts.kr]);
  });

  test('checksums in the app match the files in fonts_remote', () {
    for (final RemoteFont f in <RemoteFont>[RemoteFonts.sc, RemoteFonts.jp, RemoteFonts.kr]) {
      final File file = File('../fonts_remote/${f.fileName}');
      expect(file.lengthSync(), f.bytes, reason: f.fileName);
      expect(sha256.convert(file.readAsBytesSync()).toString(), f.sha256Hex, reason: f.fileName);
    }
  });

  test('PDFs with Chinese and Korean text are made, small, twice in one run', () async {
    RemoteFonts.directoryOverride = Directory('../fonts_remote');
    for (int i = 0; i < 2; i++) {
      const String text = '中文文档测试 한국어 문서';
      final pw.Document doc = pw.Document();
      doc.addPage(pw.Page(
        theme: await PdfFonts.theme(text: text),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context c) => pw.Text(text),
      ));
      final List<int> bytes = await doc.save();
      // The page uses only a few glyphs, so the PDF must hold a font subset,
      // not a whole 10 MB font.
      expect(bytes.length, lessThan(2 * 1024 * 1024));
    }
  });
}
