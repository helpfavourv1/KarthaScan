@Timeout(Duration(seconds: 60))
library;

// Annotate: marks as editable items (select, move, recolour, erase, undo), the
// one-piece highlighter, drawing over the real page, and placement of the result.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/utils/annotation_items.dart';
import 'package:katharscan/core/utils/ink_stroke.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/annotate_sheet.dart';
import 'package:katharscan/widgets/annotation_overlay.dart';

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

const Size kBox = Size(300, 400);

AnnotationItem pen(List<Offset> pts, {int color = 0xFF000000, double width = 4}) =>
    AnnotationItem(mode: AnnotationMode.pen, color: color, width: width, points: pts);

Future<Uint8List> rasterise(WidgetTester tester, List<AnnotationItem> items, {int w = 300, int h = 100}) async {
  return (await tester.runAsync<Uint8List>(() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    for (final AnnotationItem i in items) {
      paintAnnotation(c, i);
    }
    final ui.Image im = await rec.endRecording().toImage(w, h);
    return (await im.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  }))!;
}

int alphaAt(Uint8List rgba, int w, int x, int y) => rgba[(y * w + x) * 4 + 3];

Widget overlayHost(GlobalKey<AnnotationOverlayState> key, {VoidCallback? onChanged}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: kBox.width, height: kBox.height, child: AnnotationOverlay(key: key, onChanged: onChanged)),
        ),
      ),
    );

Future<void> drag(WidgetTester tester, Offset from, Offset to, {int steps = 6}) async {
  final TestGesture g = await tester.startGesture(from);
  for (int i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pump();
}

void main() {
  group('marks', () {
    test('a smooth path stays within the points it passes through', () {
      final Path p = smoothPath(<Offset>[const Offset(0, 0), const Offset(50, 40), const Offset(100, 0), const Offset(150, 40)]);
      final Rect b = p.getBounds();
      expect(b.left, greaterThanOrEqualTo(-0.1));
      expect(b.right, lessThanOrEqualTo(150.1));
      expect(b.top, greaterThanOrEqualTo(-0.1));
      expect(b.bottom, lessThanOrEqualTo(40.1));
      expect(smoothPath(const <Offset>[]).getBounds(), Rect.zero);
    });

    test('hit testing: pen near the line, rectangle on its outline only, ellipse ring, arrow', () {
      final AnnotationItem line = pen(<Offset>[const Offset(10, 10), const Offset(110, 10)]);
      expect(annotationHit(line, const Offset(60, 14), 6), isTrue);
      expect(annotationHit(line, const Offset(60, 40), 6), isFalse);
      const AnnotationItem box = AnnotationItem(mode: AnnotationMode.rect, color: 0xFF000000, width: 4, points: <Offset>[Offset(20, 20), Offset(120, 100)]);
      expect(annotationHit(box, const Offset(20, 60), 6), isTrue, reason: 'left edge');
      expect(annotationHit(box, const Offset(70, 60), 6), isFalse, reason: 'inside is not a hit');
      const AnnotationItem oval = AnnotationItem(mode: AnnotationMode.ellipse, color: 0xFF000000, width: 4, points: <Offset>[Offset(0, 0), Offset(100, 60)]);
      expect(annotationHit(oval, const Offset(50, 0), 6), isTrue, reason: 'top of the ring');
      expect(annotationHit(oval, const Offset(50, 30), 6), isFalse, reason: 'centre');
      const AnnotationItem arrow = AnnotationItem(mode: AnnotationMode.arrow, color: 0xFF000000, width: 4, points: <Offset>[Offset(0, 0), Offset(100, 100)]);
      expect(annotationHit(arrow, const Offset(50, 52), 6), isTrue);
      expect(annotationHit(arrow, const Offset(100, 0), 6), isFalse);
    });

    test('moving a mark shifts every point; bounds cover the mark and its width', () {
      final AnnotationItem m = pen(<Offset>[const Offset(10, 10), const Offset(30, 50)], width: 10).moved(const Offset(5, -5));
      expect(m.points.first, const Offset(15, 5));
      final Rect b = annotationBounds(m);
      expect(b.left, lessThan(15));
      expect(b.bottom, greaterThan(45));
    });

    testWidgets('highlighter is one even band: going back over the same line does not darken it', (WidgetTester tester) async {
      const AnnotationItem once = AnnotationItem(mode: AnnotationMode.highlighter, color: 0xFFFFEB3B, width: 20, points: <Offset>[Offset(20, 50), Offset(280, 50)]);
      final AnnotationItem twice = once.copyWith(points: const <Offset>[Offset(20, 50), Offset(280, 50), Offset(20, 50), Offset(280, 50)]);
      final Uint8List a = await rasterise(tester, <AnnotationItem>[once]);
      final Uint8List b = await rasterise(tester, <AnnotationItem>[twice]);
      final int single = alphaAt(a, 300, 150, 50);
      expect(single, inInclusiveRange(95, 110), reason: '40% cover');
      for (final int x in <int>[60, 100, 150, 200, 250]) {
        expect(alphaAt(a, 300, x, 50), single, reason: 'even along the band at $x');
        expect(alphaAt(b, 300, x, 50), single, reason: 'no beads or double cover at $x');
      }
      // Two separate strokes on top of each other do build up, like a real marker.
      final Uint8List c = await rasterise(tester, <AnnotationItem>[once, once]);
      expect(alphaAt(c, 300, 150, 50), greaterThan(single + 40));
    });

    testWidgets('a pen line is drawn solid and smooth, a tap leaves a dot', (WidgetTester tester) async {
      final Uint8List a = await rasterise(tester, <AnnotationItem>[
        pen(<Offset>[const Offset(20, 20), const Offset(60, 60), const Offset(100, 20), const Offset(140, 60)], width: 6),
        pen(<Offset>[const Offset(200, 50)], width: 12),
      ]);
      expect(alphaAt(a, 300, 200, 50), 255, reason: 'dot centre');
      expect(alphaAt(a, 300, 150, 90), 0, reason: 'empty elsewhere');
    });
  });

  group('overlay editing', () {
    testWidgets('drawing adds a mark; undo and redo swap it; a tap leaves a dot', (WidgetTester tester) async {
      final GlobalKey<AnnotationOverlayState> key = GlobalKey();
      await tester.pumpWidget(overlayHost(key));
      final Rect r = tester.getRect(find.byType(AnnotationOverlay));
      await drag(tester, r.topLeft + const Offset(30, 40), r.topLeft + const Offset(200, 60));
      expect(key.currentState!.itemCount, 1);
      await tester.tapAt(r.topLeft + const Offset(150, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(key.currentState!.itemCount, 2);
      key.currentState!.undo();
      key.currentState!.undo();
      expect(key.currentState!.itemCount, 0);
      key.currentState!.redo();
      expect(key.currentState!.itemCount, 1);
      expect(key.currentState!.canRedo, isTrue);
      key.currentState!.clear();
      expect(key.currentState!.isEmpty, isTrue);
      key.currentState!.undo();
      expect(key.currentState!.itemCount, 1, reason: 'clear is one undo step');
    });

    testWidgets('select a mark, recolour, move, delete; each is one undo step', (WidgetTester tester) async {
      final GlobalKey<AnnotationOverlayState> key = GlobalKey();
      int changes = 0;
      await tester.pumpWidget(overlayHost(key, onChanged: () => changes++));
      final Rect r = tester.getRect(find.byType(AnnotationOverlay));
      final AnnotationOverlayState s = key.currentState!;
      s.setMode(AnnotationMode.rect);
      await drag(tester, r.topLeft + const Offset(40, 60), r.topLeft + const Offset(200, 160));
      expect(s.itemCount, 1);
      s.setMode(AnnotationMode.select);
      // Inside the box is not a hit; the outline is.
      await tester.tapAt(r.topLeft + const Offset(120, 110));
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.hasSelection, isFalse);
      await tester.tapAt(r.topLeft + const Offset(40, 110));
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.hasSelection, isTrue);
      s.setColor(Colors.red);
      expect(s.selectedItem!.color, Colors.red.toARGB32());
      s.setWidth(10);
      s.endWidthAdjust();
      s.setWidth(12);
      s.endWidthAdjust();
      expect(s.selectedItem!.width, 12);
      final Offset before = s.selectedItem!.points.first;
      await drag(tester, r.topLeft + const Offset(40, 110), r.topLeft + const Offset(90, 140));
      expect(s.selectedItem!.points.first.dx, greaterThan(before.dx + 20));
      expect(changes, greaterThan(3));
      // Undo steps back through move, width (twice), colour.
      s.undo();
      expect(s.items.single.points.first, before);
      s.undo();
      s.undo();
      expect(s.items.single.width, 4);
      s.undo();
      expect(s.items.single.color, 0xFF000000);
      // Select again and delete.
      await tester.tapAt(r.topLeft + const Offset(40, 110));
      await tester.pump(const Duration(milliseconds: 400));
      s.deleteSelected();
      expect(s.isEmpty, isTrue);
      s.undo();
      expect(s.itemCount, 1);
    });

    testWidgets('eraser removes only the marks it crosses, as one undo step', (WidgetTester tester) async {
      final GlobalKey<AnnotationOverlayState> key = GlobalKey();
      await tester.pumpWidget(overlayHost(key));
      final Rect r = tester.getRect(find.byType(AnnotationOverlay));
      final AnnotationOverlayState s = key.currentState!;
      await drag(tester, r.topLeft + const Offset(30, 50), r.topLeft + const Offset(250, 50));
      await drag(tester, r.topLeft + const Offset(30, 150), r.topLeft + const Offset(250, 150));
      await drag(tester, r.topLeft + const Offset(30, 250), r.topLeft + const Offset(250, 250));
      expect(s.itemCount, 3);
      s.setMode(AnnotationMode.eraser);
      await drag(tester, r.topLeft + const Offset(140, 30), r.topLeft + const Offset(140, 170), steps: 14);
      expect(s.itemCount, 1, reason: 'the two upper lines are gone, the lower stays');
      s.undo();
      expect(s.itemCount, 3);
    });

    testWidgets('a shape that is only tapped is not kept; only marks are exported', (WidgetTester tester) async {
      final GlobalKey<AnnotationOverlayState> key = GlobalKey();
      await tester.pumpWidget(overlayHost(key));
      final Rect r = tester.getRect(find.byType(AnnotationOverlay));
      final AnnotationOverlayState s = key.currentState!;
      s.setMode(AnnotationMode.ellipse);
      final TestGesture g = await tester.startGesture(r.topLeft + const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 20));
      await g.moveBy(const Offset(1, 0));
      await g.up();
      await tester.pump();
      expect(s.isEmpty, isTrue);
      expect(await tester.runAsync(() => s.exportPng()), isNull, reason: 'nothing drawn gives nothing');
    });
  });

  group('placement of the result', () {
    test('the cut drawing is placed by where and how wide the ink was', () {
      final img.Image frame = img.Image(width: 400, height: 300, numChannels: 4);
      img.fillRect(frame, x1: 100, y1: 50, x2: 199, y2: 89, color: img.ColorRgba8(255, 0, 0, 255));
      final AnnotateResult r = trimAnnotation(Uint8List.fromList(img.encodePng(frame)))!;
      final img.Image cut = img.decodePng(r.bytes)!;
      expect(cut.width, 100);
      expect(cut.height, 40);
      expect(r.pctX, closeTo(150 / 400, 0.001));
      expect(r.pctY, closeTo(70 / 300, 0.001));
      expect(r.scale, closeTo((100 / 400) / 0.28, 0.001));
    });

    test('a blank frame gives nothing; unreadable bytes give nothing', () {
      expect(trimAnnotation(Uint8List.fromList(img.encodePng(img.Image(width: 50, height: 50, numChannels: 4)))), isNull);
      expect(trimAnnotation(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    });

    testWidgets('exported page: the drawing lands exactly where it was drawn', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final Directory dir = Directory.systemTemp.createTempSync('ann_export');
        addTearDown(() => dir.deleteSync(recursive: true));
        // A frame the shape of the page, with a red bar drawn at known fractions.
        final img.Image frame = img.Image(width: 1000, height: 1400, numChannels: 4);
        img.fillRect(frame, x1: 200, y1: 700, x2: 599, y2: 739, color: img.ColorRgba8(255, 0, 0, 255));
        final AnnotateResult r = trimAnnotation(Uint8List.fromList(img.encodePng(frame)))!;
        final File ann = File('${dir.path}/ann.png')..writeAsBytesSync(r.bytes);
        // The real page is bigger than the frame: placement is by fractions.
        final img.Image page = img.Image(width: 2000, height: 2800);
        img.fill(page, color: img.ColorRgb8(255, 255, 255));
        final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
        final DateTime now = DateTime.now();
        final ScanDocument doc = ScanDocument(
          id: 'd', title: 't', pageCount: 1, pagePaths: <String>[f.path], createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
          annotateLayers: <AnnotateLayer>[
            AnnotateLayer(id: 'a', pageIndex: 0, bytesPath: ann.path, placement: SignaturePlacement(pctX: r.pctX, pctY: r.pctY, scale: r.scale)),
          ],
        );
        final img.Image out = img.decodeImage(await ExportService().renderPageForOutput(doc, 0))!;
        bool red(int x, int y) {
          final img.Pixel p = out.getPixel(x, y);
          return p.r > 200 && p.g < 60 && p.b < 60;
        }

        // Bar was x 200..599 of 1000 and y 700..739 of 1400: on the 2000x2800 page that is
        // x 400..1199, y 1400..1479.
        expect(red(800, 1440), isTrue, reason: 'centre of the bar');
        expect(red(420, 1420), isTrue, reason: 'near the left end');
        expect(red(1180, 1460), isTrue, reason: 'near the right end');
        expect(red(380, 1440), isFalse, reason: 'left of the bar');
        expect(red(1220, 1440), isFalse, reason: 'right of the bar');
        expect(red(800, 1380), isFalse, reason: 'above the bar');
        expect(red(800, 1500), isFalse, reason: 'below the bar');
      });
    });
  });

  group('sheet over the real page', () {
    testWidgets('drawing over the page returns the ink where it was drawn', (WidgetTester tester) async {
      final Directory dir = Directory.systemTemp.createTempSync('ann_sheet');
      addTearDown(() => dir.deleteSync(recursive: true));
      final img.Image page = img.Image(width: 800, height: 1000);
      img.fill(page, color: img.ColorRgb8(240, 240, 240));
      final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
      AnnotateResult? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showModalBottomSheet<AnnotateResult?>(context: c, isScrollControlled: true, builder: (_) => AnnotateSheet(pagePath: f.path)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      for (int i = 0; i < 40 && find.byType(AnnotationOverlay).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // ignore: avoid_print
      print('ANNERR loaded=${find.byType(AnnotationOverlay).evaluate().isNotEmpty} spinner=${find.byType(CircularProgressIndicator).evaluate().isNotEmpty} ex=${tester.takeException()}');
      final Rect frame = tester.getRect(find.byType(AnnotationOverlay));
      expect(frame.width / frame.height, closeTo(0.8, 0.01), reason: 'the drawing area has the page shape');
      await drag(tester, Offset(frame.left + frame.width * 0.2, frame.top + frame.height * 0.3), Offset(frame.left + frame.width * 0.6, frame.top + frame.height * 0.3), steps: 12);
      await tester.tap(find.byKey(const ValueKey('annConfirm')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
      await settle(tester);
      expect(result, isNotNull);
      expect(result!.pctX, closeTo(0.4, 0.03));
      expect(result!.pctY, closeTo(0.3, 0.03));
      expect(result!.scale, closeTo(0.4 / 0.28, 0.2));
    });

    testWidgets('highlighter selection, tools and a blank sheet still work without a page', (WidgetTester tester) async {
      AnnotateResult? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showModalBottomSheet<AnnotateResult?>(context: c, isScrollControlled: true, builder: (_) => const AnnotateSheet()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await settle(tester);
      for (final AnnotationMode m in AnnotationMode.values) {
        expect(find.byKey(ValueKey<String>('annMode:${m.name}')), findsOneWidget, reason: m.name);
      }
      await tester.tap(find.byKey(const ValueKey('annMode:highlighter')));
      await tester.pump();
      final Rect frame = tester.getRect(find.byType(AnnotationOverlay));
      await drag(tester, frame.center - const Offset(60, 0), frame.center + const Offset(60, 0));
      expect(find.byKey(const ValueKey('annClear')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('annConfirm')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1200)));
      await settle(tester);
      expect(result, isNotNull);
      expect(img.decodePng(result!.bytes)!.height, lessThan(300));
    });
  });
}
