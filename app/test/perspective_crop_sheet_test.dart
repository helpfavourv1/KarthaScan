@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/perspective_crop_sheet.dart';

void main() {
  testWidgets('crop sheet: auto-detect, drag a corner from the touch-down point, confirm', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    try {
    final Directory dir = Directory.systemTemp.createTempSync('crop');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File f = File('${dir.path}/p.png');
    final img.Image src = img.Image(width: 400, height: 300, numChannels: 4)..clear(img.ColorRgba8(40, 30, 20, 255));
    img.fillRect(src, x1: 80, y1: 50, x2: 320, y2: 260, color: img.ColorRgba8(240, 240, 235, 255));
    f.writeAsBytesSync(img.encodePng(src));

    CropResult? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showModalBottomSheet<CropResult>(context: ctx, isScrollControlled: true, builder: (_) => PerspectiveCropSheet(imagePath: f.path)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // Real async: file read, image decode and the detection isolate.
    for (int i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('cropConfirm')), findsOneWidget);
    expect(find.text('Crop'), findsWidgets);

    // Corner handle is dragged from exactly where the finger lands.
    final Rect area = tester.getRect(find.byKey(const Key('cropArea')));
    final double s = area.width / 400 < area.height / 300 ? area.width / 400 : area.height / 300;
    final Offset origin = Offset(area.center.dx - 200 * s, area.center.dy - 150 * s);
    final Offset tl = origin + Offset(80 * s, 50 * s);
    final TestGesture g = await tester.startGesture(tl);
    await g.moveTo(tl + const Offset(3, 0));
    await g.moveTo(tl + const Offset(30, 30));
    await g.up();
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('cropAspect:square')));
    await tester.tap(find.byKey(const Key('cropAspect:square')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cropConfirm')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.aspect, 1.0);
    expect(result!.quad[0].dx, closeTo(110, 12), reason: 'the dragged corner moved about 30 screen px in photo units');
    expect(result!.quad[2].dx, closeTo(320, 10));
    } catch (e, st) {
      // ignore: avoid_print
      print('XXXERR $e\n${st.toString().split("\n").take(8).join("\n")}');
      rethrow;
    }
  });
}
