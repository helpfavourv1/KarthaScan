@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/export_job.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/compress_sheet.dart';

img.Image noisy(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 3);
  for (final p in im) {
    p..r = (p.x * 7 + p.y * 13) % 256
      ..g = (p.x * 3 + p.y * 5 + (p.x * p.y) % 17) % 256
      ..b = (p.x ^ p.y) % 256;
  }
  return im;
}

void main() {
  test('a PDF is squeezed under the chosen size, a JPG page too', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('ctarget');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final List<String> paths = <String>[];
    for (int i = 0; i < 3; i++) {
      final File f = File('${tmp.path}/p$i.png')..writeAsBytesSync(img.encodePng(noisy(1600, 2200)));
      paths.add(f.path);
    }
    final DateTime now = DateTime(2026, 1, 1);
    final ScanDocument doc = ScanDocument(id: 'd', title: 'T', pageCount: 3, pagePaths: paths, createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: paths.first);
    final Directory out = Directory('${tmp.path}/o')..createSync();
    final int target = 600 * 1024;
    final List<String> pdf = await ExportService().export(document: doc, format: ExportFormat.pdf, outputDirectoryPath: out.path, targetBytes: target);
    final int size = File(pdf.first).lengthSync();
    expect(size, lessThan((target * 1.15).round()), reason: 'the whole PDF fits the chosen size (plus a little PDF overhead)');
    expect(size, greaterThan(50 * 1024));
    final List<String> jpg = await ExportService().export(document: doc, format: ExportFormat.jpg, outputDirectoryPath: out.path, targetBytes: target);
    for (final String j in jpg) {
      expect(File(j).lengthSync(), lessThan((target * 1.2).round()));
    }
  });

  test('cleaned copy for OCR keeps the picture size and flattens a shadow', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('ocrclean');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final img.Image page = img.Image(width: 300, height: 200, numChannels: 3);
    for (final p in page) {
      final double shade = 1 - 0.5 * p.x / 299;
      p..r = (235 * shade).round()..g = (230 * shade).round()..b = (220 * shade).round();
    }
    final File f = File('${tmp.path}/p.png')..writeAsBytesSync(img.encodePng(page));
    final String? clean = await OcrService.cleanedCopy(f.path);
    expect(clean, isNotNull);
    final img.Image c = img.decodeImage(File(clean!).readAsBytesSync())!;
    expect(c.width, 300);
    expect(c.height, 200);
    expect((c.getPixel(5, 100).r - c.getPixel(294, 100).r).abs(), lessThan(25));
    expect(OcrService.worthCleaning('hi'), isTrue);
    expect(OcrService.worthCleaning('x' * 100), isFalse);
  });

  testWidgets('compress sheet: target size and black-and-white are returned', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final Directory tmp = Directory.systemTemp.createTempSync('csheet');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final File f = File('${tmp.path}/p.png')..writeAsBytesSync(img.encodePng(noisy(300, 400)));
    final DateTime now = DateTime(2026, 1, 1);
    final ScanDocument doc = ScanDocument(id: 'd', title: 'T', pageCount: 1, pagePaths: [f.path], createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path);
    CompressChoice? result;
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await showModalBottomSheet<CompressChoice>(context: ctx, isScrollControlled: true, builder: (_) => CompressSheet(document: doc)),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (int i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.ensureVisible(find.byKey(const ValueKey<String>('compressTarget:2')));
      await tester.tap(find.byKey(const ValueKey<String>('compressTarget:2')));
      await tester.ensureVisible(find.byKey(const ValueKey<String>('compressBw')));
      await tester.tap(find.byKey(const ValueKey<String>('compressBw')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey<String>('compressGo')));
      await tester.tap(find.byKey(const ValueKey<String>('compressGo')));
      await tester.pumpAndSettle();
      expect(result!.targetMB, 2);
      expect(result!.blackWhite, isTrue);
    } catch (e, st) {
      fail('XXXERR ${e.toString().split("\n").first} @ ${st.toString().split("\n").take(3).join(" | ")}');
    }
  });
}
