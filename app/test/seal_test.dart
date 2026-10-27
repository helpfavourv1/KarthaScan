// Custom seal: drawing (shapes, fitting, size, scripts, worn look), logo preparation,
// the saved-seal library, the data model, the editor sheet and the export.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/seal_design.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/seal_library.dart';
import 'package:katharscan/core/utils/seal_draw.dart';
import 'package:katharscan/core/utils/seal_logo.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/seal_stamp_sheet.dart';
import 'package:katharscan/widgets/text_stamp_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double S = 400;

StampLayer layer({
  String text = 'ACME CO',
  String sub = '',
  String shape = 'oval',
  String center = 'star',
  int color = 0xFFDD2222,
  int? textColor,
  double scale = 1.0,
  bool ink = false,
  String id = 'seal1',
}) =>
    StampLayer(
      id: id, pageIndex: 0, kind: 'seal', placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5),
      text: text, sealSubtext: sub, sealShape: shape, sealCenter: center, color: color,
      sealTextColor: textColor, sealTextScale: scale, sealInk: ink,
    );

class Px {
  Px(this.w, this.h, this.rgba);
  final int w, h;
  final Uint8List rgba;
  int a(int x, int y) => rgba[(y * w + x) * 4 + 3];
  int r(int x, int y) => rgba[(y * w + x) * 4];
  int g(int x, int y) => rgba[(y * w + x) * 4 + 1];
  int b(int x, int y) => rgba[(y * w + x) * 4 + 2];
  int get inkCount {
    int n = 0;
    for (int i = 3; i < rgba.length; i += 4) {
      if (rgba[i] > 40) n++;
    }
    return n;
  }

  /// left, top, right, bottom of everything drawn
  List<int> get bbox {
    int l = w, t = h, r = -1, b = -1;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (a(x, y) > 40) {
          if (x < l) l = x;
          if (x > r) r = x;
          if (y < t) t = y;
          if (y > b) b = y;
        }
      }
    }
    return <int>[l, t, r, b];
  }
}

Future<Px> render(WidgetTester tester, StampLayer l, {ui.Image? logo}) async {
  return (await tester.runAsync<Px>(() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    drawSeal(c, S, l, centerImage: logo);
    final ui.Image im = await rec.endRecording().toImage(S.round(), S.round());
    final ByteData bd = (await im.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return Px(S.round(), S.round(), bd.buffer.asUint8List());
  }))!;
}

void main() {
  group('drawing', () {
    testWidgets('each shape has its own outline and stays inside the canvas', (WidgetTester tester) async {
      for (final String shape in <String>['oval', 'round', 'rectangle']) {
        final Px p = await render(tester, layer(shape: shape));
        final List<int> b = p.bbox;
        expect(b[0], greaterThan(S * 0.01), reason: '$shape touches the left edge');
        expect(b[1], greaterThan(S * 0.01), reason: '$shape touches the top edge');
        expect(b[2], lessThan(S * 0.99), reason: '$shape touches the right edge');
        expect(b[3], lessThan(S * 0.99), reason: '$shape touches the bottom edge');
        final int w = b[2] - b[0], h = b[3] - b[1];
        if (shape == 'oval') expect(w, greaterThan(h * 1.15), reason: 'oval is landscape');
        if (shape == 'round') expect((w - h).abs(), lessThan(S * 0.04), reason: 'round is a circle');
        if (shape == 'rectangle') expect(w, greaterThan(h * 1.3), reason: 'box is landscape');
      }
    });

    testWidgets('very long text never leaves the outer ring, for every shape', (WidgetTester tester) async {
      const String longText = 'ACME INTERNATIONAL HOLDINGS LIMITED COMPANY OF LONDON AND PARIS';
      for (final String shape in <String>['oval', 'round', 'rectangle']) {
        final Px p = await render(tester, layer(shape: shape, text: longText, sub: longText));
        const double c = S / 2;
        for (int y = 0; y < p.h; y++) {
          for (int x = 0; x < p.w; x++) {
            if (p.a(x, y) <= 60) continue;
            if (shape == 'rectangle') {
              expect(x >= S * 0.03 - 8 && x <= S * 0.97 + 8 && y >= S * 0.20 - 8 && y <= S * 0.80 + 8, isTrue, reason: 'box: ink outside at $x,$y');
            } else {
              final double a = S * 0.4875, bb = shape == 'round' ? S * 0.4875 : S * 0.3775;
              final double v = ((x - c) * (x - c)) / (a * a) + ((y - c) * (y - c)) / (bb * bb);
              expect(v <= 1.03, isTrue, reason: '$shape: ink outside the ring at $x,$y');
            }
          }
        }
      }
    });

    testWidgets('long text is shrunk to fit, short text is not', (WidgetTester tester) async {
      final Px shortPx = await render(tester, layer(text: 'ACME'));
      final Px longPx = await render(tester, layer(text: 'ACME INTERNATIONAL HOLDINGS LIMITED COMPANY OF LONDON'));
      final Px ringsOnly = await render(tester, layer(text: ' '));
      // More letters means more ink, but not in proportion: the long text was scaled down.
      final int shortInk = shortPx.inkCount - ringsOnly.inkCount;
      final int longInk = longPx.inkCount - ringsOnly.inkCount;
      expect(longInk, greaterThan(shortInk));
      expect(longInk, lessThan(shortInk * 13 * 0.8), reason: '13x the letters must not be 13x the ink');
    });

    testWidgets('the size setting changes the lettering over its whole range', (WidgetTester tester) async {
      final Px rings = await render(tester, layer(text: ' '));
      final List<int> inks = <int>[];
      for (final double s in <double>[0.5, 0.65, 0.8, 1.0]) {
        inks.add((await render(tester, layer(text: 'ACME CO', scale: s))).inkCount - rings.inkCount);
      }
      for (int i = 1; i < inks.length; i++) {
        expect(inks[i], greaterThan(inks[i - 1]), reason: 'bigger setting must give bigger lettering: $inks');
      }
    });

    testWidgets('Arabic is set straight and fully inside the ring', (WidgetTester tester) async {
      final Px rings = await render(tester, layer(text: ' ', shape: 'round'));
      final Px ar = await render(tester, layer(text: 'شركة المثال المحدودة', sub: 'لندن', shape: 'round'));
      expect(ar.inkCount, greaterThan(rings.inkCount + 200));
      final List<int> b = ar.bbox;
      expect(b[0], greaterThan(0));
      expect(b[2], lessThan(S));
    });

    test('letters are grouped the way a person counts them', () {
      expect(splitClusters('ABC').length, 3);
      expect(splitClusters('éx').length, 2, reason: 'accent stays with its letter');
      expect(splitClusters('😀A').length, 2, reason: 'a surrogate pair is one letter');
      expect(splitClusters('कार्य').length, lessThan('कार्य'.runes.length));
      expect(splitClusters(''), isEmpty);
    });

    testWidgets('lettering colour is separate from the rings', (WidgetTester tester) async {
      final Px p = await render(tester, layer(text: 'ACME CO', color: 0xFFDD2222, textColor: 0xFF1F4E9C));
      int blue = 0, red = 0;
      for (int y = 0; y < p.h; y++) {
        for (int x = 0; x < p.w; x++) {
          if (p.a(x, y) < 200) continue;
          if (p.b(x, y) > 120 && p.r(x, y) < 80) blue++;
          if (p.r(x, y) > 180 && p.b(x, y) < 80) red++;
        }
      }
      expect(blue, greaterThan(100), reason: 'lettering is blue');
      expect(red, greaterThan(500), reason: 'rings and star stay red');
    });

    testWidgets('the worn look is the same every time and removes some ink, not most', (WidgetTester tester) async {
      final Px clean = await render(tester, layer(text: 'ACME CO'));
      final Px a = await render(tester, layer(text: 'ACME CO', ink: true));
      final Px b = await render(tester, layer(text: 'ACME CO', ink: true));
      final Px other = await render(tester, layer(text: 'ACME CO', ink: true, id: 'seal2'));
      expect(a.rgba, b.rgba, reason: 'same seal, same marks');
      expect(a.rgba == other.rgba, isFalse, reason: 'a different seal wears differently');
      expect(a.inkCount, lessThan(clean.inkCount));
      expect(a.inkCount, greaterThan(clean.inkCount * 0.6));
    });

    testWidgets('opacity lowers the ink strength', (WidgetTester tester) async {
      final StampLayer l = layer().copyWith(opacity: 0.5);
      final Px p = await render(tester, l);
      int strong = 0;
      for (int i = 3; i < p.rgba.length; i += 4) {
        if (p.rgba[i] > 160) strong++;
      }
      expect(strong, 0);
      expect(p.inkCount, greaterThan(500));
    });
  });

  group('logo', () {
    test('a large photo becomes a small circular picture', () {
      final img.Image photo = img.Image(width: 2600, height: 1950);
      for (int y = 0; y < photo.height; y++) {
        for (int x = 0; x < photo.width; x += 1) {
          photo.setPixelRgb(x, y, (x * 255 ~/ photo.width), (y * 255 ~/ photo.height), 128);
        }
      }
      final Uint8List out = prepareSealLogo(Uint8List.fromList(img.encodeJpg(photo, quality: 90)));
      final img.Image d = img.decodePng(out)!;
      expect((d.width, d.height), (256, 256));
      expect(d.getPixel(2, 2).a, 0, reason: 'corner outside the circle is transparent');
      expect(d.getPixel(128, 128).a, 255);
      expect(out.length, lessThan(200 * 1024), reason: 'stored with every seal, so it must be small');
    });

    test('white background can be made transparent, the artwork stays', () {
      final img.Image logo = img.Image(width: 300, height: 300);
      img.fill(logo, color: img.ColorRgb8(255, 255, 255));
      img.fillCircle(logo, x: 150, y: 150, radius: 40, color: img.ColorRgb8(200, 0, 0));
      final img.Image d = img.decodePng(prepareSealLogo(Uint8List.fromList(img.encodePng(logo)), removeWhite: true))!;
      expect(d.getPixel(128, 128).a, 255, reason: 'red artwork kept');
      expect(d.getPixel(128, 128).r, greaterThan(150));
      expect(d.getPixel(100, 60).a, 0, reason: 'white inside the circle removed');
      final img.Image kept = img.decodePng(prepareSealLogo(Uint8List.fromList(img.encodePng(logo))))!;
      expect(kept.getPixel(100, 60).a, 255, reason: 'without the switch white stays');
    });

    test('a file that is not a picture comes back unchanged instead of crashing', () {
      final Uint8List junk = Uint8List.fromList(<int>[1, 2, 3, 4]);
      expect(prepareSealLogo(junk), junk);
    });
  });

  group('saved seals', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    SealDesign d(String t, {int color = 0xFFDD2222}) => SealDesign(text: t, color: color);

    test('save, list newest first, delete', () async {
      final SealLibrary lib = SealLibrary();
      await lib.save(d('A'));
      final List<SavedSeal> two = await lib.save(d('B'));
      expect(two.map((SavedSeal s) => s.design.text), <String>['B', 'A']);
      final List<SavedSeal> after = await lib.delete(two.first.id);
      expect(after.map((SavedSeal s) => s.design.text), <String>['A']);
      expect((await SealLibrary().load()).length, 1, reason: 'survives a reload');
    });

    test('saving the same look again moves it to the front instead of duplicating', () async {
      final SealLibrary lib = SealLibrary();
      await lib.save(d('A'));
      await lib.save(d('B'));
      final List<SavedSeal> v = await lib.save(d('A'));
      expect(v.map((SavedSeal s) => s.design.text), <String>['A', 'B']);
    });

    test('keeps the newest 12', () async {
      final SealLibrary lib = SealLibrary();
      List<SavedSeal> v = <SavedSeal>[];
      for (int i = 0; i < 15; i++) {
        v = await lib.save(d('S$i'));
      }
      expect(v.length, SealLibrary.maxSeals);
      expect(v.first.design.text, 'S14');
      expect(v.any((SavedSeal s) => s.design.text == 'S0'), isFalse);
    });

    test('a damaged entry does not hide the rest, and a damaged store does not crash', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'saved_seals_v1': '[{"id":"x","design":{"text":"OK"}}, 5, {"id":"y"}]',
      });
      final List<SavedSeal> v = await SealLibrary().load();
      expect(v.length, 1);
      expect(v.first.design.text, 'OK');
      SharedPreferences.setMockInitialValues(<String, Object>{'saved_seals_v1': 'not json'});
      expect(await SealLibrary().load(), isEmpty);
    });

    test('the logo is saved with the design', () async {
      final Uint8List logo = Uint8List.fromList(<int>[9, 8, 7]);
      final List<SavedSeal> v = await SealLibrary().save(SealDesign(text: 'L', center: 'image', logo: logo));
      expect((await SealLibrary().load()).first.design.logo, logo);
      expect(v.length, 1);
    });
  });

  group('model', () {
    test('a seal saved before the new settings keeps looking the same', () {
      final StampLayer old = StampLayer.fromJson(<String, dynamic>{
        'id': 'a', 'pageIndex': 0, 'kind': 'seal', 'pctX': 0.5, 'pctY': 0.5, 'text': 'OLD', 'fontSize': 40,
        'sealShape': 'oval', 'sealSubtext': 'X', 'sealCenter': 'star',
      });
      expect(old.sealTextScale, 1.0);
      expect(old.sealFont, 'sans');
      expect(old.sealInk, isFalse);
      expect(old.sealTextColor, isNull);
    });

    test('new settings round-trip and can be cleared', () {
      final StampLayer l = layer(textColor: 0xFF1F4E9C, scale: 0.7, ink: true).copyWith(sealFont: 'serif');
      final StampLayer back = StampLayer.fromJson(l.toJson());
      expect((back.sealTextColor, back.sealTextScale, back.sealFont, back.sealInk), (0xFF1F4E9C, 0.7, 'serif', true));
      expect(l.copyWith(clearSealTextColor: true).sealTextColor, isNull);
      expect(l.copyWith(text: 'X').sealTextColor, 0xFF1F4E9C, reason: 'unrelated edits keep it');
    });
  });

  group('editor sheet', () {
    Widget host(Widget child) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Builder(builder: (BuildContext c) => child)),
        );

    testWidgets('shows a live preview, applies every choice and returns them', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      StampResult? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<StampResult>(context: c, isScrollControlled: true, builder: (_) => const SealStampSheet());
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sealPreview')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('sealMainText')), 'NORTH LTD');
      await tester.tap(find.byKey(const ValueKey('sealShape:round')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('sealFont:serif')));
      await tester.tap(find.byKey(const ValueKey('sealFont:serif')));
      await tester.ensureVisible(find.byKey(const ValueKey('sealInk')));
      await tester.tap(find.byKey(const ValueKey('sealInk')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('sealTextSize')));
      await tester.drag(find.byKey(const ValueKey('sealTextSize')), const Offset(-2000, 0));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('sealConfirm')));
      await tester.tap(find.byKey(const ValueKey('sealConfirm')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.text, 'NORTH LTD');
      expect(result!.sealShapeValue, 'round');
      expect(result!.sealFontValue, 'serif');
      expect(result!.sealInkValue, isTrue);
      expect(result!.sealTextScaleValue, closeTo(0.5, 0.02), reason: 'slider dragged to its low end');
    });

    testWidgets('a saved seal appears and fills the editor when tapped', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await SealLibrary().save(const SealDesign(text: 'SAVED CO', shape: 'rectangle', ink: true));
      await tester.pumpWidget(host(const SealStampSheet()));
      await tester.pumpAndSettle();
      final Finder saved = find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('savedSeal:'));
      expect(saved, findsOneWidget);
      await tester.tap(saved);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'SAVED CO'), findsOneWidget);
      final ChoiceChip box = tester.widget<ChoiceChip>(find.byKey(const ValueKey('sealShape:rectangle')));
      expect(box.selected, isTrue);
    });

    testWidgets('Save this seal puts it in the library', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(host(const SealStampSheet()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('sealMainText')), 'MY STAMP');
      await tester.ensureVisible(find.byKey(const ValueKey('sealSave')));
      await tester.tap(find.byKey(const ValueKey('sealSave')));
      await tester.pumpAndSettle();
      final List<SavedSeal> v = await tester.runAsync(() => SealLibrary().load()) ?? <SavedSeal>[];
      expect(v.single.design.text, 'MY STAMP');
    });
  });

  group('export', () {
    testWidgets('a seal is placed on the exported page at the right size, in the right colour', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final Directory dir = Directory.systemTemp.createTempSync('seal_export');
        addTearDown(() => dir.deleteSync(recursive: true));
        final img.Image page = img.Image(width: 3000, height: 4000);
        img.fill(page, color: img.ColorRgb8(255, 255, 255));
        final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
        final DateTime now = DateTime.now();
        final ScanDocument doc = ScanDocument(
          id: 'd', title: 't', pageCount: 1, pagePaths: <String>[f.path], createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
          stampLayers: <StampLayer>[layer(shape: 'round', text: 'EXPORT TEST')],
        );
        final Uint8List out = await ExportService().renderPageForOutput(doc, 0);
        final img.Image r = img.decodeImage(out)!;
        // Seal is 25% of the width = 750 px, centred; the outer ring is at 0.47 of that from the centre.
        final int x = 1500 + (750 * 0.47).round(), y = 2000;
        bool red = false;
        for (int dx = -14; dx <= 14; dx++) {
          final img.Pixel p = r.getPixel(x + dx, y);
          if (p.r > 180 && p.g < 90 && p.b < 90) red = true;
        }
        expect(red, isTrue, reason: 'ring of the seal found where it should be');
        final img.Pixel far = r.getPixel(300, 300);
        expect(far.r > 250 && far.g > 250, isTrue, reason: 'page untouched elsewhere');
      });
    });
  });
}
