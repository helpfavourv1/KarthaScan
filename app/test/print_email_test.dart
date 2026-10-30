// test/print_email_test.dart
//
// Print layout (paper, margins, fit, pages per sheet, page choice) and the Print and
// Email option dialogs. The system print and share screens are not covered here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/services/print_service.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/print_email_dialogs.dart';

int pageCount(List<int> pdf) => RegExp(r'/Type\s*/Page(?![a-z])').allMatches(latin1.decode(pdf)).length;

List<List<double>> mediaBoxes(List<int> pdf) => RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]')
    .allMatches(latin1.decode(pdf))
    .map((m) => <double>[double.parse(m.group(1)!), double.parse(m.group(2)!)])
    .toList();

Widget host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  late Directory dir;
  late List<String> paths;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('print_email');
    paths = <String>[];
    for (int i = 0; i < 5; i++) {
      final img.Image im = img.Image(width: 300, height: 400);
      img.fill(im, color: img.ColorRgb8(30 * i, 100, 200));
      final File f = File('${dir.path}/p$i.jpg')..writeAsBytesSync(img.encodeJpg(im));
      paths.add(f.path);
    }
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('one page per sheet by default; page choice limits the output', () async {
    final all = await PrintService.buildPdfBytes(paths);
    expect(pageCount(all), 5);
    final some = await PrintService.buildPdfBytes(paths, pageIndices: <int>[0, 2, 4]);
    expect(pageCount(some), 3);
  });

  test('pages per sheet groups scans onto fewer sheets', () async {
    expect(pageCount(await PrintService.buildPdfBytes(paths, perSheet: 2)), 3); // 2+2+1
    expect(pageCount(await PrintService.buildPdfBytes(paths, perSheet: 4)), 2); // 4+1
    expect(pageCount(await PrintService.buildPdfBytes(paths, perSheet: 1)), 5);
  });

  test('sheet grid: 2 per sheet is sideways, 4 per sheet is a 2x2 portrait', () {
    expect(sheetGrid(2), (cols: 2, rows: 1, landscape: true));
    expect(sheetGrid(4), (cols: 2, rows: 2, landscape: false));
    expect(sheetGrid(1), (cols: 1, rows: 1, landscape: false));
  });

  test('paper sizes are the real ones', () {
    expect(PrintPaper.a5.format.width, closeTo(419.5, 0.6));
    expect(PrintPaper.a5.format.height, closeTo(595.3, 0.6));
    expect(PrintPaper.legal.format.width, closeTo(612, 0.01));
    expect(PrintPaper.legal.format.height, closeTo(1008, 0.01));
    expect(PrintPaper.letter.format.height, closeTo(792, 0.01));
    expect(PrintMargin.none.points, 0);
    expect(PrintMargin.narrow.points, lessThan(PrintMargin.normal.points));
  });

  test('the chosen paper size reaches the PDF', () async {
    final a5 = mediaBoxes(await PrintService.buildPdfBytes(paths, pageIndices: <int>[0], pageFormat: PrintPaper.a5.format));
    expect(a5.single[0], closeTo(419.5, 0.6));
    final legal = mediaBoxes(await PrintService.buildPdfBytes(paths, pageIndices: <int>[0], pageFormat: PrintPaper.legal.format));
    expect(legal.single[1], closeTo(1008, 0.5));
    final two = mediaBoxes(await PrintService.buildPdfBytes(paths, pageIndices: <int>[0, 1], perSheet: 2));
    expect(two.single[0], greaterThan(two.single[1]), reason: '2 per sheet is sideways');
  });

  test('every margin and fit combination builds', () async {
    for (final PrintMargin m in PrintMargin.values) {
      for (final PrintFit f in PrintFit.values) {
        for (final int n in <int>[1, 2, 4]) {
          final bytes = await PrintService.buildPdfBytes(paths, margin: m, fit: f, perSheet: n);
          expect(pageCount(bytes), (5 / n).ceil(), reason: '$m $f $n');
        }
      }
    }
  });

  testWidgets('print dialog: typed range "1, 3, 5-7" becomes pages and bad text is refused', (tester) async {
    PrintChoice? got;
    await tester.pumpWidget(host(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => got = await showDialog<PrintChoice>(context: ctx, builder: (_) => const PrintOptionsDialog(pageCount: 8, currentIndex: 2)),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('printMode:Range')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('printRange')), '9');
    await tester.tap(find.byKey(const ValueKey<String>('printGo')));
    await tester.pumpAndSettle();
    expect(got, isNull);
    expect(find.textContaining('8'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey<String>('printRange')), '1, 3, 5-7');
    await tester.ensureVisible(find.byKey(const ValueKey<String>('printPaper:Legal')));
    await tester.tap(find.byKey(const ValueKey<String>('printPaper:Legal')));
    await tester.ensureVisible(find.byKey(const ValueKey<String>('printPerSheet:4')));
    await tester.tap(find.byKey(const ValueKey<String>('printPerSheet:4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('printGo')));
    await tester.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.indices, <int>[0, 2, 4, 5, 6]);
    expect(got!.paper, PrintPaper.legal);
    expect(got!.perSheet, 4);
    expect(got!.margin, PrintMargin.none);
    expect(got!.fit, PrintFit.fit);
  });

  testWidgets('print dialog: All pages gives null, Current gives the open page', (tester) async {
    PrintChoice? got;
    await tester.pumpWidget(host(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => got = await showDialog<PrintChoice>(context: ctx, builder: (_) => const PrintOptionsDialog(pageCount: 8, currentIndex: 2)),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('printGo')));
    await tester.pumpAndSettle();
    expect(got!.indices, isNull);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('printMode:Current')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('printGo')));
    await tester.pumpAndSettle();
    expect(got!.indices, <int>[2]);
  });

  testWidgets('email dialog returns the typed message and the size limit', (tester) async {
    EmailChoice? got;
    await tester.pumpWidget(host(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => got = await showDialog<EmailChoice>(context: ctx, builder: (_) => const EmailOptionsDialog()),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('emailGo')));
    await tester.pumpAndSettle();
    expect(got!.message, '');
    expect(got!.targetMB, isNull);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('emailMessage')), '  Signed copy attached  ');
    await tester.tap(find.byKey(const ValueKey<String>('emailTarget:2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('emailGo')));
    await tester.pumpAndSettle();
    expect(got!.message, 'Signed copy attached');
    expect(got!.targetMB, 2);
  });
}
