@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/rotate_resize_sheet.dart';

void main() {
  testWidgets('resize sheet: paper and dpi presets, real size estimate, enlarge warning', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final Directory tmp = Directory.systemTemp.createTempSync('rsz');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // A noisy picture so the JPEG size really depends on the pixel count.
    final img.Image src = img.Image(width: 600, height: 800, numChannels: 4);
    for (final p in src) {
      p..r = (p.x * 7 + p.y * 13) % 256
        ..g = (p.x * 3 + p.y * 5) % 256
        ..b = (p.x ^ p.y) % 256
        ..a = 255;
    }
    final File f = File('${tmp.path}/p.png')..writeAsBytesSync(img.encodePng(src));
    (int, int)? result;
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await showModalBottomSheet<(int, int)>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => RotateResizeSheet(mode: RotateResizeMode.resize, imagePath: f.path),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      Future<void> wait() async {
        for (int i = 0; i < 20; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await wait();
      String width() => tester.widget<TextField>(find.byType(TextField).first).controller!.text;
      String height() => tester.widget<TextField>(find.byType(TextField).last).controller!.text;
      expect(width(), '600');

      // Shrinking: no warning; the estimate is a real number, smaller than at full size.
      String estimate() => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').firstWhere((t) => t.startsWith('≈'));
      final String full = estimate();
      await tester.ensureVisible(find.text('25%'));
      await tester.tap(find.text('25%'));
      await wait();
      expect(find.byKey(const Key('upscaleWarning')), findsNothing);
      final String small = estimate();
      double mb(String s) => double.parse(RegExp(r'≈ ([0-9.]+) MB').firstMatch(s)!.group(1)!);
      expect(mb(small), lessThan(mb(full)));

      // A4 at 150 dpi is 1240 x 1754 px; the page (3:4) is wider than A4's shape,
      // so the width decides: 1240 x 1654, the same 3:4 shape.
      await tester.ensureVisible(find.byKey(const Key('paper:a4')));
      await tester.tap(find.byKey(const Key('paper:a4')));
      await tester.tap(find.byKey(const Key('dpi:150')));
      await wait();
      expect(int.parse(width()), closeTo(1240, 1));
      expect(int.parse(height()), closeTo(1654, 1));
      expect(find.byKey(const Key('upscaleWarning')), findsOneWidget, reason: 'bigger than the 600 x 800 page');

      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();
      expect(result!.$1, closeTo(1240, 1));
      expect(result!.$2, closeTo(1654, 1));
    } catch (e, st) {
      // ignore: avoid_print
      print('XXXERR $e\n${st.toString().split("\n").take(8).join("\n")}');
      fail('XXXERR ${e.toString().split("\n").first} @ ${st.toString().split("\n").take(3).join(" | ")}');
    }
  });
}
