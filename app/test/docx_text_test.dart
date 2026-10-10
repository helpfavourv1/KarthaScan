import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/export_service.dart';

void main() {
  test('Arabic and Hebrew lines are marked right-to-left, Latin lines are not', () async {
    final Directory dir = Directory.systemTemp.createTempSync('docx_text_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = await ExportService()
        .buildDocxFromText('Hello\nمرحبا بالعالم\nשלום', dir.path, 'rtl');
    final Archive zip = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final String xml = utf8.decode(
        zip.findFile('word/document.xml')!.content as List<int>);
    expect('<w:bidi/>'.allMatches(xml).length, 2);
    expect(xml.contains('مرحبا'), isTrue);
  });
}
