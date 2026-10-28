@Timeout(Duration(seconds: 60))
library;

// Watermark: layouts (single, diagonal, tiled), logo pictures, page choice,
// the model, the sheet, and the exported page.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/utils/page_range.dart';
import 'package:katharscan/core/utils/watermark_draw.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/watermark_sheet.dart';

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

WatermarkLayer wm({
  String text = 'DRAFT',
  String layout = 'single',
  double rotation = 0,
  double scale = 1,
  double opacity = 1,
  int color = 0xFFFF0000,
  String? image,
}) =>
    WatermarkLayer(
      id: 'w1', pageIndex: 0, text: text, layout: layout, imagePath: image, opacity: opacity, color: color,
      placement: SignaturePlacement(pctX: 0.5, pctY: 0.5, rotationDegrees: rotation, scale: scale),
    );

bool redish(img.Pixel p) => p.r > 200 && p.g < 120 && p.b < 120 && p.a > 0;

Future<img.Image> exportPage(WidgetTester tester, WatermarkLayer layer, {int w = 1200, int h = 1600}) async {
  return (await tester.runAsync<img.Image>(() async {
    final Directory dir = Directory.systemTemp.createTempSync('wm_export');
    addTearDown(() => dir.deleteSync(recursive: true));
    final img.Image page = img.Image(width: w, height: h);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
    final DateTime now = DateTime.now();
    final ScanDocument doc = ScanDocument(
      id: 'd', title: 't', pageCount: 1, pagePaths: <String>[f.path], createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
      watermarkLayers: <WatermarkLayer>[layer],
    );
    return img.decodeImage(await ExportService().renderPageForOutput(doc, 0))!;
  }))!;
}

int redInRect(img.Image im, int x0, int y0, int x1, int y1) {
  int n = 0;
  for (int y = y0; y < y1; y += 2) {
    for (int x = x0; x < x1; x += 2) {
      if (redish(im.getPixel(x, y))) n++;
    }
  }
  return n;
}

Widget sheetHost(Widget Function(BuildContext) build, void Function(Object?) onResult) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext c) => Center(
            child: ElevatedButton(
              onPressed: () async => onResult(await showModalBottomSheet<WatermarkLayer>(context: c, isScrollControlled: true, builder: build)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  group('page range', () {
    test('reads singles, ranges, mixes and "all" as zero-based pages', () {
      expect(parsePageRange('1-3, 5', 6), <int>[0, 1, 2, 4]);
      expect(parsePageRange('2', 3), <int>[1]);
      expect(parsePageRange('all', 3), <int>[0, 1, 2]);
      expect(parsePageRange('3,1,3 2', 5), <int>[0, 1, 2]);
      expect(parsePageRange(' 4 – 5 ', 5), <int>[3, 4]);
    });
    test('anything wrong is refused rather than half applied', () {
      for (final String bad in <String>['', ' ', '0', '7', '1-9', '3-1', 'a', '1,x', '-2', '1-']) {
        expect(parsePageRange(bad, 6), isNull, reason: bad);
      }
      expect(parsePageRange('1', 0), isNull);
    });
  });

  group('tiles', () {
    test('the grid covers the page corners, is staggered, and is bounded', () {
      const ui.Size page = ui.Size(1000, 1400);
      final List<ui.Offset> c = tileCentres(page, 220, 60);
      expect(c.length, greaterThan(20));
      expect(c.any((ui.Offset o) => o.dx < -400 && o.dy < -600), isTrue);
      expect(c.any((ui.Offset o) => o.dx > 400 && o.dy > 600), isTrue);
      final Set<double> rowA = c.where((ui.Offset o) => o.dy == c.first.dy).map((ui.Offset o) => o.dx).toSet();
      final double secondRowY = c.map((ui.Offset o) => o.dy).toSet().toList()[1];
      final Set<double> rowB = c.where((ui.Offset o) => o.dy == secondRowY).map((ui.Offset o) => o.dx).toSet();
      expect(rowA.intersection(rowB), isEmpty, reason: 'rows are offset by half a step');
      expect(tileCentres(page, 6, 2).length, lessThanOrEqualTo(maxTiles * 4), reason: 'tiny tiles cannot ask for thousands');
    });

    testWidgets('text tiles reach every part of the page; empty text draws nothing', (WidgetTester tester) async {
      Future<img.Image> draw(WatermarkLayer l) async => (await tester.runAsync<img.Image>(() async {
            final ui.PictureRecorder rec = ui.PictureRecorder();
            paintWatermarkTiles(ui.Canvas(rec), const ui.Size(600, 800), l);
            final ui.Image im = await rec.endRecording().toImage(600, 800);
            final ByteData bd = (await im.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
            return img.Image.fromBytes(width: 600, height: 800, bytes: bd.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
          }))!;
      final img.Image a = await draw(wm(layout: 'tiled', rotation: -30));
      for (final List<int> q in <List<int>>[<int>[0, 0, 300, 400], <int>[300, 0, 600, 400], <int>[0, 400, 300, 800], <int>[300, 400, 600, 800]]) {
        expect(redInRect(a, q[0], q[1], q[2], q[3]), greaterThan(30), reason: 'quadrant ${q.join(',')}');
      }
      final img.Image blank = await draw(wm(text: '  ', layout: 'tiled'));
      expect(redInRect(blank, 0, 0, 600, 800), 0);
    });
  });

  group('model', () {
    test('layout and logo survive saving; older data reads as a single text watermark', () {
      final WatermarkLayer l = wm(layout: 'tiled', image: '/x/logo.png');
      final WatermarkLayer back = WatermarkLayer.fromJson(l.toJson());
      expect(back.layout, 'tiled');
      expect(back.imagePath, '/x/logo.png');
      expect(back.isTiled, isTrue);
      expect(back.isImage, isTrue);
      final Map<String, dynamic> old = l.toJson()..remove('layout')..remove('imagePath');
      final WatermarkLayer o = WatermarkLayer.fromJson(old);
      expect(o.layout, 'single');
      expect(o.imagePath, isNull);
      expect(o.isImage, isFalse);
      expect(l.copyWith(clearImage: true).imagePath, isNull);
      expect(l.copyWith(opacity: 0.3).imagePath, '/x/logo.png');
    });
    test('editing: a changed layout takes the new turn and size, an unchanged one keeps the position', () {
      final WatermarkLayer existing = wm().copyWith(placement: const SignaturePlacement(pctX: 0.2, pctY: 0.7, scale: 1.7));
      final WatermarkLayer same = applyWatermarkEdit(existing, wm().copyWith(placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5)));
      expect(same.placement, existing.placement);
      final WatermarkLayer tiled = applyWatermarkEdit(existing, wm(layout: 'tiled', rotation: -30, scale: 1));
      expect(tiled.layout, 'tiled');
      expect(tiled.placement.rotationDegrees, -30);
      expect(tiled.placement.pctX, 0.2);
    });
  });

  group('sheet', () {
    testWidgets('layouts give their turn and size; sizes follow the size slider', (WidgetTester tester) async {
      for (final List<Object> c in <List<Object>>[<Object>['single', 0.0, 1.0], <Object>['diagonal', -35.0, 2.0], <Object>['tiled', -30.0, 1.0]]) {
        WatermarkLayer? result;
        await tester.pumpWidget(sheetHost((_) => const WatermarkSheet(), (Object? r) => result = r as WatermarkLayer?));
        await tester.tap(find.text('open'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(ValueKey<String>('wmLayout:${c[0]}')));
        await tester.pump();
        await tester.ensureVisible(find.text('Add'));
        await tester.tap(find.text('Add'));
        await settle(tester);
        expect(result, isNotNull, reason: '${c[0]}');
        expect(result!.layout, c[0]);
        expect(result!.placement.rotationDegrees, c[1]);
        expect(result!.placement.scale, closeTo(c[2] as double, 0.001));
        expect(result!.text, isNotEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('page choice: this page, all pages, a valid range; a bad range is refused', (WidgetTester tester) async {
      final ValueNotifier<String> pages = ValueNotifier<String>('current');
      WatermarkLayer? result;
      await tester.pumpWidget(sheetHost((_) => WatermarkSheet(pages: pages, pageCount: 6), (Object? r) => result = r as WatermarkLayer?));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('wmPages:range')));
      await tester.tap(find.byKey(const ValueKey('wmPages:range')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('wmRange')), '1-9');
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(result, isNull, reason: 'sheet stays open');
      expect(find.textContaining('6 pages'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('wmRange')), '2-3, 6');
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(result, isNotNull);
      expect(pages.value, '2-3, 6');

      result = null;
      await tester.pumpWidget(sheetHost((_) => WatermarkSheet(pages: pages, pageCount: 6), (Object? r) => result = r as WatermarkLayer?));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('wmPages:all')));
      await tester.tap(find.byKey(const ValueKey('wmPages:all')));
      await tester.pump();
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(pages.value, 'all');
    });

    testWidgets('no page choice is offered when editing', (WidgetTester tester) async {
      await tester.pumpWidget(sheetHost((_) => WatermarkSheet(initialConfig: wm()), (Object? r) {}));
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.byKey(const ValueKey('wmPages:all')), findsNothing);
      expect(find.byKey(const ValueKey('wmLayout:tiled')), findsOneWidget);
    });

    testWidgets('a chosen logo is kept as a PNG in the app folder and returned', (WidgetTester tester) async {
      final Directory dir = Directory.systemTemp.createTempSync('wm_logo');
      addTearDown(() => dir.deleteSync(recursive: true));
      final img.Image big = img.Image(width: 2000, height: 1000);
      img.fill(big, color: img.ColorRgb8(0, 0, 255));
      final Uint8List jpg = Uint8List.fromList(img.encodeJpg(big));
      WatermarkLayer? result;
      await tester.pumpWidget(sheetHost(
        (_) => WatermarkSheet(pickImage: () async => jpg, logoDirectory: () async => dir),
        (Object? r) => result = r as WatermarkLayer?,
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wmKind')), matching: find.text('Image')));
      await settle(tester);
      // Adding before a picture is chosen does nothing.
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(result, isNull);
      await tester.runAsync(() async {
        await tester.ensureVisible(find.byKey(const ValueKey('wmChooseImage')));
        await tester.tap(find.byKey(const ValueKey('wmChooseImage')));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      await settle(tester);
      expect(find.byKey(const ValueKey('wmLogoPreview')), findsOneWidget);
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(result, isNotNull);
      expect(result!.isImage, isTrue);
      expect(result!.text, '');
      final File saved = File(result!.imagePath!);
      expect(saved.existsSync(), isTrue);
      expect(saved.path, contains('watermark_logos'));
      final img.Image kept = img.decodePng(saved.readAsBytesSync())!;
      expect(kept.width, 1024, reason: 'big pictures are made smaller');
      expect(kept.height, 512);
    });
  });

  group('exported page', () {
    testWidgets('tiled text covers the whole page; a single one stays in the middle', (WidgetTester tester) async {
      final img.Image tiled = await exportPage(tester, wm(layout: 'tiled', rotation: -30));
      for (final List<int> q in <List<int>>[<int>[0, 0, 600, 800], <int>[600, 0, 1200, 800], <int>[0, 800, 600, 1600], <int>[600, 800, 1200, 1600]]) {
        expect(redInRect(tiled, q[0], q[1], q[2], q[3]), greaterThan(60), reason: 'quadrant ${q.join(',')}');
      }
      final img.Image single = await exportPage(tester, wm());
      expect(redInRect(single, 400, 700, 800, 900), greaterThan(60), reason: 'in the middle');
      expect(redInRect(single, 0, 0, 1200, 300), 0, reason: 'nothing at the top');
    });

    testWidgets('a diagonal watermark is turned', (WidgetTester tester) async {
      final img.Image flat = await exportPage(tester, wm(scale: 2));
      final img.Image turned = await exportPage(tester, wm(scale: 2, rotation: -35));
      int rows(img.Image im) {
        int n = 0;
        for (int y = 0; y < im.height; y += 2) {
          if (redInRect(im, 0, y, im.width, y + 1) > 0) n++;
        }
        return n;
      }

      expect(rows(turned), greaterThan(rows(flat) * 2), reason: 'a turned line of text covers more rows');
    });

    testWidgets('a logo is placed in the middle at its opacity; tiled logos fill the page', (WidgetTester tester) async {
      final Directory dir = Directory.systemTemp.createTempSync('wm_logo_export');
      addTearDown(() => dir.deleteSync(recursive: true));
      final img.Image logo = img.Image(width: 200, height: 100, numChannels: 4);
      img.fill(logo, color: img.ColorRgba8(255, 0, 0, 255));
      final File lf = File('${dir.path}/logo.png')..writeAsBytesSync(img.encodePng(logo));
      final img.Image full = await exportPage(tester, wm(text: '', image: lf.path, opacity: 1));
      expect(redish(full.getPixel(600, 800)), isTrue, reason: 'centre');
      expect(redish(full.getPixel(50, 50)), isFalse, reason: 'corner');
      final img.Image half = await exportPage(tester, wm(text: '', image: lf.path, opacity: 0.5));
      final img.Pixel mid = half.getPixel(600, 800);
      expect(mid.r, 255);
      expect(mid.g, inInclusiveRange(110, 150), reason: 'half faded onto white');
      final img.Image tiles = await exportPage(tester, wm(text: '', image: lf.path, layout: 'tiled', rotation: -30));
      for (final List<int> q in <List<int>>[<int>[0, 0, 600, 800], <int>[600, 0, 1200, 800], <int>[0, 800, 600, 1600], <int>[600, 800, 1200, 1600]]) {
        expect(redInRect(tiles, q[0], q[1], q[2], q[3]), greaterThan(60), reason: 'quadrant ${q.join(',')}');
      }
    });

    testWidgets('a logo file that is gone stops the export instead of shipping an unmarked page', (WidgetTester tester) async {
      for (final String layout in <String>['single', 'tiled']) {
        final Object? caught = await tester.runAsync<Object?>(() async {
          final Directory dir = Directory.systemTemp.createTempSync('wm_missing');
          try {
            final img.Image page = img.Image(width: 300, height: 400);
            final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
            final DateTime now = DateTime.now();
            final ScanDocument doc = ScanDocument(
              id: 'd', title: 't', pageCount: 1, pagePaths: <String>[f.path], createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
              watermarkLayers: <WatermarkLayer>[wm(text: '', image: '/does/not/exist.png', layout: layout)],
            );
            await ExportService().renderPageForOutput(doc, 0);
            return null;
          } catch (e) {
            return e;
          } finally {
            dir.deleteSync(recursive: true);
          }
        });
        expect(caught, isA<ExportFailedException>(), reason: layout);
      }
    });
  });
}
