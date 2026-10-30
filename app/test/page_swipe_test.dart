// A sideways swipe on the page turns to the next one only when swiping is allowed,
// and a zoomed-in page keeps its swipes for panning.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/document_canvas.dart';

void main() {
  late Directory dir;
  late List<String> paths;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('swipe');
    paths = <String>[];
    for (int i = 0; i < 3; i++) {
      final img.Image im = img.Image(width: 300, height: 400);
      img.fill(im, color: img.ColorRgb8(40 * i, 200, 100));
      paths.add((File('${dir.path}/p$i.png')..writeAsBytesSync(img.encodePng(im))).path);
    }
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<int>> pump(WidgetTester tester, {required bool swipe}) async {
    final List<int> seen = <int>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DocumentCanvas(
          pagePaths: paths,
          physics: const NeverScrollableScrollPhysics(),
          swipeEnabled: swipe,
          onPageChanged: seen.add,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return seen;
  }

  testWidgets('swipe turns the page when allowed', (tester) async {
    final List<int> seen = await pump(tester, swipe: true);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(seen, <int>[1]);
  });

  testWidgets('swipe does nothing while editing', (tester) async {
    final List<int> seen = await pump(tester, swipe: false);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(seen, isEmpty);
  });

  testWidgets('a zoomed-in page does not turn on a sideways drag', (tester) async {
    final List<int> seen = await pump(tester, swipe: true);
    final Offset c = tester.getCenter(find.byType(PageView));
    // Pinch out to zoom in.
    final TestGesture a = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
    final TestGesture b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
    for (int i = 1; i <= 10; i++) {
      await a.moveTo(c - Offset(20.0 + i * 12, 0));
      await b.moveTo(c + Offset(20.0 + i * 12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(seen, isEmpty, reason: 'zoomed page must keep the drag for panning');
  });
}
