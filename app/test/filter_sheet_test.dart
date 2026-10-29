@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/services/export_service.dart' show FilterType;
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/filter_preview_sheet.dart';

void main() {
  testWidgets('filter sheet: final slider value is shown, Magic colour is offered, apply-all is returned', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final Directory tmp = Directory.systemTemp.createTempSync('fsheet');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final File f = File('${tmp.path}/p.png')..writeAsBytesSync(img.encodePng(img.Image(width: 400, height: 300, numChannels: 4)..clear(img.ColorRgba8(100, 100, 100, 255))));
    FilterChoice? result;
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await showModalBottomSheet<FilterChoice>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => FilterPreviewSheet(
                imagePath: f.path,
                // A page that is already cropped: the preview is built from it.
                transform: const PageTransform(cropRect: Rect.fromLTWH(0, 0, 200, 300)),
                pageCount: 3,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      Future<void> wait() async {
        for (int i = 0; i < 25; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await wait();
      expect(find.byKey(const Key('filter:magicColor')), findsOneWidget);
      // The preview is of the cropped page: 200 x 300.
      final Image shown = tester.widgetList<Image>(find.byType(Image)).first;
      final img.Image decoded = img.decodeImage((shown.image as MemoryImage).bytes)!;
      expect(decoded.width / decoded.height, closeTo(200 / 300, 0.02));

      // Drag the brightness slider to the end and let go at once: the picture ends at that value.
      await tester.drag(find.byKey(const Key('brightnessSlider')), const Offset(3000, 0));
      await wait();
      final Image after = tester.widgetList<Image>(find.byType(Image)).first;
      final img.Image lit = img.decodeImage((after.image as MemoryImage).bytes)!;
      expect(lit.getPixel(10, 10).r, greaterThan(200), reason: 'brightness at the maximum is what the preview shows');

      await tester.tap(find.byKey(const Key('filter:magicColor')));
      await wait();
      await tester.ensureVisible(find.byKey(const Key('filterApplyAll')));
      await tester.tap(find.byKey(const Key('filterApplyAll')));
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.filter, FilterType.magicColor);
      expect(result!.applyAll, isTrue);
      expect(result!.brightness, closeTo(1, 0.001));
    } catch (e, st) {
      // ignore: avoid_print
      print('XXXERR $e\n${st.toString().split("\n").take(8).join("\n")}');
      rethrow;
    }
  });
}
