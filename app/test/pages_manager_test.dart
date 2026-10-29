@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/pages_manager_sheet.dart';

void main() {
  testWidgets('pages manager: edited thumbnails and multi-select delete', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final Directory tmp = Directory.systemTemp.createTempSync('pm');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final List<String> paths = <String>[];
    for (int i = 0; i < 4; i++) {
      final File f = File('${tmp.path}/p$i.png')..writeAsBytesSync(img.encodePng(img.Image(width: 200, height: 300, numChannels: 4)..clear(img.ColorRgba8(200, 10 * i, 50, 255))));
      paths.add(f.path);
    }
    PagesManagerResult? result;
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await showModalBottomSheet<PagesManagerResult>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => PagesManagerSheet(
                pagePaths: paths,
                allDocuments: const [],
                transformsByPath: {paths[0]: const PageTransform(cropRect: Rect.fromLTWH(0, 0, 100, 100))},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      Future<void> wait() async {
        for (int i = 0; i < 12; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await wait();
      expect(find.byKey(const Key('editedThumb')), findsOneWidget, reason: 'only the cropped page gets a rendered thumbnail');

      await tester.tap(find.byKey(const Key('pagesSelect')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pageCheck:1')));
      await tester.tap(find.byKey(const Key('pageCheck:2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pagesDeleteSelected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pagesDeleteConfirmYes')));
      await tester.pumpAndSettle();

      // Selecting every remaining page cannot delete them all.
      await tester.tap(find.byKey(const Key('pagesSelect')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pageCheck:0')));
      await tester.tap(find.byKey(const Key('pageCheck:1')));
      await tester.pump();
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('pagesDeleteSelected'))).onPressed, isNull);

      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();
      expect(result!.paths, [paths[0], paths[3]]);
    } catch (e, st) {
      fail('XXXERR ${e.toString().split("\n").first} @ ${st.toString().split("\n").take(3).join(" | ")}');
    }
  });
}
