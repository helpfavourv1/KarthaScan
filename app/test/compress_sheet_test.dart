// test/compress_sheet_test.dart
//
// The compress sheet's numbers come from really encoding the edited page, so they
// must be ordered Small < Medium < Original and match what export produces.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/export_job.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/compress_sheet.dart';

Future<void> settleMeasure(WidgetTester tester) async {
  for (int i = 0; i < 150; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
}

void main() {
  late Directory dir;
  late ScanDocument doc;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('compress_sheet');
    final Random rnd = Random(7);
    final img.Image page = img.Image(width: 1600, height: 2200);
    for (int y = 0; y < page.height; y++) {
      for (int x = 0; x < page.width; x++) {
        final int n = 200 + rnd.nextInt(55);
        page.setPixelRgb(x, y, n, n - (x ~/ 40) % 30, n - (y ~/ 50) % 30);
      }
    }
    final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
    final DateTime now = DateTime(2026, 1, 1);
    doc = ScanDocument(
      id: 'd', title: 'T', pageCount: 2, pagePaths: <String>[f.path, f.path],
      createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('estimates are ordered and non-zero for PDF and JPG, empty for others', () async {
    for (final ExportFormat f in <ExportFormat>[ExportFormat.pdf, ExportFormat.jpg]) {
      final Map<CompressionTier, int> s = await ExportService().estimateSizes(doc, f);
      expect(s[CompressionTier.small], greaterThan(0), reason: '$f');
      expect(s[CompressionTier.small]!, lessThan(s[CompressionTier.medium]!), reason: '$f small<medium');
      expect(s[CompressionTier.medium]!, lessThan(s[CompressionTier.original]!), reason: '$f medium<original');
    }
    expect(await ExportService().estimateSizes(doc, ExportFormat.txt), isEmpty);
  });

  test('JPG estimate matches the real export within 10 percent', () async {
    final Map<CompressionTier, int> s = await ExportService().estimateSizes(doc, ExportFormat.jpg);
    for (final CompressionTier t in CompressionTier.values) {
      final Directory out = Directory('${dir.path}/o_${t.name}')..createSync();
      final List<String> files = await ExportService().export(
        document: doc, format: ExportFormat.jpg, outputDirectoryPath: out.path, compression: t,
      );
      final int real = files.fold<int>(0, (int a, String p) => a + File(p).lengthSync());
      expect((s[t]! - real).abs() / real, lessThan(0.10), reason: '$t estimate ${s[t]} vs real $real');
    }
  });

  testWidgets('sheet shows three sizes and returns the picked format and level', (WidgetTester tester) async {
    CompressChoice? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (BuildContext c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await showModalBottomSheet<CompressChoice>(
                  isScrollControlled: true, context: c, builder: (BuildContext _) => CompressSheet(document: doc)),
                child: const Text('open'),
              ),
            ),
          )),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    // Wait for the real measurement.
    await settleMeasure(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining(RegExp(r'(MB|KB)$')), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey<String>('compressCard:small')));
    await tester.pump();
    await tester.tap(find.text('JPG'));
    await settleMeasure(tester);
    await tester.pumpAndSettle();
    final Finder go = find.byKey(const ValueKey<String>('compressGo'));
    final String where = 'seg ${tester.getRect(find.byKey(const ValueKey<String>('compressFormat')))} card ${tester.getRect(find.byKey(const ValueKey<String>('compressCard:small')))} sheet ${tester.getRect(find.byType(CompressSheet))} '
        'go at ${tester.getRect(go)} screen ${tester.view.physicalSize / tester.view.devicePixelRatio} hit ${go.hitTestable().evaluate().length}';
    await tester.tap(go);
    await tester.pumpAndSettle();
    expect(find.byType(CompressSheet), findsNothing, reason: 'sheet did not close after Compress was tapped; $where');
    expect(result?.format, ExportFormat.jpg);
    expect(result?.tier, CompressionTier.small);
  });
}
