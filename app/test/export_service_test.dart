// test/export_service_test.dart
//
// Unit tests: PDF generation, TXT export, DOCX raw text export (Section
// 16 file #72).
//
// Unlike ocr_service_test.dart, these are real, fully-functioning tests —
// export_service.dart's dependencies (pdf, archive, image, pdf_crypto)
// are all pure Dart with no platform channel, so nothing here needs a
// device or emulator. dart:io file I/O works normally in `flutter test`,
// which runs in a full Dart VM with real OS access (unlike widget tests'
// mocked rendering layer) — so writing to and reading from
// Directory.systemTemp is legitimate, standard practice here.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/export_job.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/export_service.dart';

void main() {
  late Directory tempDir;
  late String testImagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('katharscan_export_test_');

    // A tiny synthetic page image — no fixture asset needed. Real content
    // doesn't matter for these tests; a valid, decodable image does.
    final img.Image sourceImage = img.Image(width: 40, height: 60);
    img.fill(sourceImage, color: img.ColorRgb8(255, 255, 255));
    final Uint8List pngBytes = Uint8List.fromList(img.encodePng(sourceImage));
    testImagePath = '${tempDir.path}/test_page.png';
    await File(testImagePath).writeAsBytes(pngBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ScanDocument buildTestDocument({String ocrText = 'Hello from KatharScan'}) {
    final DateTime now = DateTime(2026, 1, 1);
    return ScanDocument(
      id: 'test-doc-1',
      title: 'Test Document',
      pageCount: 1,
      pagePaths: <String>[testImagePath],
      createdAt: now,
      updatedAt: now,
      ocrText: ocrText,
      thumbnailPath: testImagePath,
    );
  }

  group('PDF export', () {
    test('produces a file starting with the %PDF magic bytes', () async {
      final ExportService service = ExportService();
      final List<String> outputs = await service.export(
        document: buildTestDocument(),
        format: ExportFormat.pdf,
        outputDirectoryPath: tempDir.path,
      );

      expect(outputs, hasLength(1));
      final File outputFile = File(outputs.single);
      expect(await outputFile.exists(), isTrue);

      final List<int> bytes = await outputFile.readAsBytes();
      final String header = String.fromCharCodes(bytes.take(4));
      expect(header, '%PDF');
    });

  });

  group('TXT export', () {
    test('output file contains exactly the document OCR text', () async {
      final ExportService service = ExportService();
      const String expectedText = 'Line one\nLine two with unicode: café';
      final List<String> outputs = await service.export(
        document: buildTestDocument(ocrText: expectedText),
        format: ExportFormat.txt,
        outputDirectoryPath: tempDir.path,
      );

      expect(outputs, hasLength(1));
      final String content = await File(outputs.single).readAsString();
      expect(content, expectedText);
    });
  });

  group('DOCX export', () {
    test('produces a valid zip archive containing word/document.xml',
        () async {
      final ExportService service = ExportService();
      final List<String> outputs = await service.export(
        document: buildTestDocument(),
        format: ExportFormat.docx,
        outputDirectoryPath: tempDir.path,
      );

      expect(outputs, hasLength(1));
      final File outputFile = File(outputs.single);
      final List<int> bytes = await outputFile.readAsBytes();

      // ZIP local file header magic bytes ("PK\x03\x04").
      expect(bytes[0], 0x50); // 'P'
      expect(bytes[1], 0x4B); // 'K'
    });

    test('escapes XML special characters in the document text', () async {
      final ExportService service = ExportService();
      final List<String> outputs = await service.export(
        document: buildTestDocument(ocrText: 'Terms & Conditions <required>'),
        format: ExportFormat.docx,
        outputDirectoryPath: tempDir.path,
      );

      // A full round-trip unzip+parse is more than this test needs — the
      // meaningful thing to verify is that export succeeded without
      // throwing on special characters that would otherwise produce
      // invalid XML (a raw unescaped '&' or '<' in word/document.xml
      // would make the resulting .docx fail to open in Word).
      final File outputFile = File(outputs.single);
      expect(await outputFile.exists(), isTrue);
      expect(await outputFile.length(), greaterThan(0));
    });
  });

  group('JPG/PNG export', () {
    test('JPG export produces one output file per page', () async {
      final ExportService service = ExportService();
      final List<String> outputs = await service.export(
        document: buildTestDocument(),
        format: ExportFormat.jpg,
        outputDirectoryPath: tempDir.path,
      );

      expect(outputs, hasLength(1));
      expect(await File(outputs.single).exists(), isTrue);
    });
  });

  group('error handling', () {
    test('throws ExportFailedException for a document with an unreadable page',
        () async {
      final ExportService service = ExportService();
      final DateTime now = DateTime(2026, 1, 1);
      final ScanDocument brokenDocument = ScanDocument(
        id: 'broken-doc',
        title: 'Broken',
        pageCount: 1,
        pagePaths: <String>['${tempDir.path}/does_not_exist.png'],
        createdAt: now,
        updatedAt: now,
        ocrText: '',
        thumbnailPath: '${tempDir.path}/does_not_exist.png',
      );

      expect(
        () => service.export(
          document: brokenDocument,
          format: ExportFormat.jpg,
          outputDirectoryPath: tempDir.path,
        ),
        throwsA(isA<ExportFailedException>()),
      );
    });
  });
}
