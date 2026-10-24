// test/fill_v2_test.dart
//
// Fill v2: text typed straight onto the page. Covers the model (legacy vs flow),
// the exported pixels, and the typing dock.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/fill_snippet.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/fill_editor_dock.dart';

void main() {
  group('model', () {
    test('legacy fill is not flow; sized fill is, and both survive JSON', () {
      const SignaturePlacement p = SignaturePlacement(pctX: 0.5, pctY: 0.5);
      const StampLayer legacy = StampLayer(id: 'a', pageIndex: 0, kind: 'fill', placement: p, text: 'x');
      final StampLayer flow = legacy.copyWith(boxWidth: 0.4, fillSize: 0.03);
      expect(legacy.isFlowFill, isFalse);
      expect(flow.isFlowFill, isTrue);
      final StampLayer back = StampLayer.fromJson(flow.toJson());
      expect(back.boxWidth, 0.4);
      expect(back.fillSize, 0.03);
      expect(back.isFlowFill, isTrue);
      expect(StampLayer.fromJson(legacy.toJson()).isFlowFill, isFalse);
    });

    test('other kinds are never flow fill', () {
      const SignaturePlacement p = SignaturePlacement(pctX: 0.5, pctY: 0.5);
      const StampLayer t = StampLayer(id: 'a', pageIndex: 0, kind: 'text', placement: p, boxWidth: 0.4, fillSize: 0.03);
      expect(t.isFlowFill, isFalse);
    });
  });

  group('export', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fill_v2'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<img.Image> exported(StampLayer layer) async {
      final img.Image page = img.Image(width: 600, height: 800);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));
      final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
      final DateTime now = DateTime(2026, 1, 1);
      final ScanDocument doc = ScanDocument(
        id: 'd', title: 'T', pageCount: 1, pagePaths: <String>[f.path],
        createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
        stampLayers: <StampLayer>[layer],
      );
      final Directory out = Directory('${dir.path}/out')..createSync();
      final List<String> files = await ExportService().export(
        document: doc, format: ExportFormat.png, outputDirectoryPath: out.path,
      );
      return img.decodePng(File(files.first).readAsBytesSync())!;
    }

    int dark(img.Image im, int x0, int y0, int x1, int y1) {
      int n = 0;
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          if (im.getPixel(x, y).r < 100) n++;
        }
      }
      return n;
    }

    test('fill text lands at its place and nowhere else', () async {
      final img.Image im = await exported(const StampLayer(
        id: 'f', pageIndex: 0, kind: 'fill',
        placement: SignaturePlacement(pctX: 0.5, pctY: 0.5),
        text: 'HELLO', boxWidth: 0.6, fillSize: 0.05, color: 0xFF000000,
      ));
      expect(dark(im, 100, 340, 500, 460), greaterThan(200), reason: 'text missing near the centre');
      expect(dark(im, 0, 0, 600, 200), 0, reason: 'ink above the text');
      expect(dark(im, 0, 600, 600, 800), 0, reason: 'ink below the text');
    });

    test('long text wraps inside its box instead of running off the page', () async {
      final img.Image im = await exported(const StampLayer(
        id: 'f', pageIndex: 0, kind: 'fill',
        placement: SignaturePlacement(pctX: 0.5, pctY: 0.3),
        text: 'one two three four five six seven eight nine ten eleven twelve',
        boxWidth: 0.4, fillSize: 0.05, color: 0xFF000000,
      ));
      // Box is 240px wide centred at x=300 → x 180..420. Nothing outside it.
      expect(dark(im, 0, 0, 170, 800), 0, reason: 'ink left of the box');
      expect(dark(im, 430, 0, 600, 800), 0, reason: 'ink right of the box');
      expect(dark(im, 180, 0, 420, 800), greaterThan(300));
    });
  });

  group('dock', () {
    Future<StampLayer> pumpDock(WidgetTester tester, List<StampLayer> sink) async {
      const StampLayer start = StampLayer(
        id: 'f', pageIndex: 0, kind: 'fill',
        placement: SignaturePlacement(pctX: 0.5, pctY: 0.5), boxWidth: 0.4, fillSize: 0.03,
      );
      StampLayer draft = start;
      bool done = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(builder: (BuildContext c, StateSetter set) {
            return FillEditorDock(
              draft: draft,
              snippets: const <FillSnippet>[],
              onChanged: (StampLayer n) => set(() {
                draft = n;
                sink.add(n);
              }),
              onDone: () => done = true,
              onSaveSnippet: (String _) {},
              onDeleteSnippet: (String _) {},
              accent: Colors.blue,
              surface: Colors.white,
              textPrimary: Colors.black,
            );
          }),
        ),
      ));
      await tester.pump();
      expect(done, isFalse);
      return start;
    }

    testWidgets('typing updates the draft on every keystroke', (WidgetTester tester) async {
      final List<StampLayer> sink = <StampLayer>[];
      await pumpDock(tester, sink);
      await tester.enterText(find.byKey(const ValueKey<String>('fillTextField')), 'Hi');
      await tester.pump();
      expect(sink.last.text, 'Hi');
    });

    testWidgets('size and width buttons change the draft and respect limits', (WidgetTester tester) async {
      final List<StampLayer> sink = <StampLayer>[];
      await pumpDock(tester, sink);
      await tester.tap(find.byIcon(Icons.text_increase));
      await tester.pump();
      expect(sink.last.fillSize, greaterThan(0.03));
      for (int i = 0; i < 60; i++) {
        await tester.tap(find.byIcon(Icons.text_increase));
      }
      await tester.pump();
      expect(sink.last.fillSize, lessThanOrEqualTo(0.12));
      await tester.tap(find.byIcon(Icons.width_wide));
      await tester.pump();
      expect(sink.last.boxWidth, closeTo(0.45, 1e-9));
    });

    test('todayText is DD-MM-YYYY', () {
      expect(FillEditorDock.todayText(DateTime(2026, 3, 7)), '07-03-2026');
    });
  });
}
