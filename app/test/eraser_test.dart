@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/utils/eraser_fill.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/eraser_overlay.dart';

void main() {
  test('auto colour takes the paper colour around a mark, not the ink under it', () {
    final img.Image page = img.Image(width: 200, height: 100, numChannels: 4)..clear(img.ColorRgba8(230, 220, 190, 255));
    img.fillRect(page, x1: 60, y1: 40, x2: 140, y2: 60, color: img.ColorRgba8(10, 10, 10, 255)); // a line of ink
    final int? c = autoFillColor(page, points: const [Offset(60, 50), Offset(100, 50), Offset(140, 50)], width: 16, isBox: false, displayW: 200, displayH: 100);
    expect(c, 0xFFE6DCBE);
    final int? box = autoFillColor(page, points: const [Offset(60, 40), Offset(140, 60)], width: 10, isBox: true, displayW: 200, displayH: 100);
    expect(box, 0xFFE6DCBE);
    expect(autoFillColor(page, points: const [], width: 10, isBox: false, displayW: 200, displayH: 100), isNull);
  });

  testWidgets('eraser: a stroke starts where the finger lands, takes the page colour, and zoom mode does not draw', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final Directory tmp = Directory.systemTemp.createTempSync('eras');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final File f = File('${tmp.path}/p.png')..writeAsBytesSync(img.encodePng(img.Image(width: 400, height: 300, numChannels: 4)..clear(img.ColorRgba8(200, 210, 230, 255))));
    List<Map<String, dynamic>>? result;
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await showModalBottomSheet<List<Map<String, dynamic>>>(context: ctx, isScrollControlled: true, builder: (_) => EraserSheet(imagePath: f.path)),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (int i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      final Offset from = area.center - const Offset(40, 0);

      // Zoom mode on: a drag moves the page, it does not erase.
      await tester.tap(find.byKey(const Key('eraserHand')));
      await tester.pump();
      await tester.dragFrom(from, const Offset(60, 0));
      await tester.pump();
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton).last).onPressed, isNull, reason: 'nothing was erased in zoom mode');
      await tester.tap(find.byKey(const Key('eraserHand')));
      await tester.pump();

      // Erase: the first point is exactly where the finger went down.
      final TestGesture g = await tester.startGesture(from);
      await g.moveTo(from + const Offset(2, 0));
      await g.moveTo(from + const Offset(50, 0));
      await g.up();
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      final Map<String, dynamic> s = result!.single;
      expect(s['color'], 0xFFC8D2E6, reason: 'painted with the colour of the page around the mark');
      final List<dynamic> first = (s['points'] as List).first as List;
      final double expectedX = (from.dx - area.left) / area.width;
      expect((first[0] as double), closeTo(expectedX, 0.01), reason: 'starts at the touch-down point, not ~18 px later');
    } catch (e, st) {
      fail('XXXERR ${e.toString().split("\n").first} @ ${st.toString().split("\n").take(3).join(" | ")}');
    }
  });
}
