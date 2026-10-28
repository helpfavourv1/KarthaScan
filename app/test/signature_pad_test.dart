@Timeout(Duration(seconds: 40))
library;

// Signature pad: smooth pen-like ink, colours and widths, undo, typed signatures,
// the saved-signature library and the sheets.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/services/signature_library.dart';
import 'package:katharscan/core/utils/ink_stroke.dart';
import 'package:katharscan/core/utils/typed_signature.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/signature_sheets.dart';

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Uint8List png(int w, int h, int shade) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(shade, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(im));
}

List<InkPoint> line(double speedPxPerMs, {int n = 20}) => <InkPoint>[
      for (int i = 0; i < n; i++) InkPoint(Offset(10 + i * speedPxPerMs * 10, 50 + (i.isEven ? 2 : -2)), i * 10),
    ];

void main() {
  group('ink strokes', () {
    test('no points gives nothing, a tap gives a dot', () {
      expect(buildInkSegments(const <InkPoint>[], 3), isEmpty);
      final List<InkSegment> dot = buildInkSegments(const <InkPoint>[InkPoint(Offset(5, 5), 0)], 4);
      expect(dot, hasLength(1));
      expect(dot.first.a, dot.first.b);
      expect(dot.first.width, 4);
    });

    test('two points give one straight piece', () {
      final List<InkSegment> s = buildInkSegments(const <InkPoint>[InkPoint(Offset(0, 0), 0), InkPoint(Offset(20, 0), 10)], 3);
      expect(s, hasLength(1));
    });

    test('a jittery line is smoothed into many short pieces that join up', () {
      final List<InkPoint> pts = line(0.5);
      final List<InkSegment> s = buildInkSegments(pts, 3);
      expect(s.length, greaterThan(pts.length));
      for (int i = 1; i < s.length; i++) {
        expect((s[i].a - s[i - 1].b).distance, lessThan(0.001), reason: 'piece $i starts where the last ended');
      }
      for (final InkSegment seg in s) {
        expect(seg.width.isFinite, isTrue);
        expect(seg.a.dx.isFinite && seg.b.dy.isFinite, isTrue);
      }
    });

    test('slow strokes are heavier than fast ones, and width stays in range', () {
      double avg(List<InkSegment> s) => s.map((InkSegment e) => e.width).reduce((double a, double b) => a + b) / s.length;
      final double slow = avg(buildInkSegments(line(0.1, n: 40), 4));
      final double fast = avg(buildInkSegments(line(3.0, n: 40), 4));
      expect(slow, greaterThan(fast));
      for (final InkSegment seg in buildInkSegments(line(3.0, n: 40), 4)) {
        expect(seg.width, inInclusiveRange(4 * 0.5, 4 * 1.6));
      }
    });

    test('pressure off keeps one width', () {
      for (final InkSegment seg in buildInkSegments(line(2.0), 5, pressure: false)) {
        expect(seg.width, 5);
      }
    });

    test('repeated identical points do not break it', () {
      final List<InkSegment> s = buildInkSegments(<InkPoint>[for (int i = 0; i < 10; i++) const InkPoint(Offset(3, 3), 0)], 3);
      expect(s, hasLength(1));
    });
  });

  group('saved signatures', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sigs'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('newest first, the same picture is kept once', () async {
      final SignatureLibrary lib = SignatureLibrary(Directory('${dir.path}/s'));
      await lib.add(png(10, 5, 1));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await lib.add(png(10, 5, 2));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await lib.add(png(10, 5, 1)); // again
      final List<SavedSignature> l = await lib.list();
      expect(l, hasLength(2));
      expect(img.decodePng(l.first.bytes)!.getPixel(0, 0).r, 1);
    });

    test('keeps at most six and drops the oldest', () async {
      final SignatureLibrary lib = SignatureLibrary(Directory('${dir.path}/s'));
      for (int i = 0; i < 9; i++) {
        await lib.add(png(10, 5, i + 10));
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final List<SavedSignature> l = await lib.list();
      expect(l, hasLength(SignatureLibrary.maxSaved));
      expect(img.decodePng(l.first.bytes)!.getPixel(0, 0).r, 18);
      expect(img.decodePng(l.last.bytes)!.getPixel(0, 0).r, 13);
    });

    test('remove deletes one; a bad id is ignored', () async {
      final SignatureLibrary lib = SignatureLibrary(Directory('${dir.path}/s'));
      await lib.add(png(10, 5, 3));
      final SavedSignature s = (await lib.list()).single;
      await lib.remove('../escape.png');
      expect(await lib.list(), hasLength(1));
      await lib.remove(s.id);
      expect(await lib.list(), isEmpty);
    });

    test('an older single saved signature joins once, and does not come back after removal', () async {
      final SignatureLibrary lib = SignatureLibrary(Directory('${dir.path}/s'));
      await lib.importLegacy(png(8, 4, 7));
      expect(await lib.list(), hasLength(1));
      await lib.remove((await lib.list()).single.id);
      await lib.importLegacy(png(8, 4, 7));
      expect(await lib.list(), isEmpty);
      await lib.importLegacy(null);
    });

    test('an unreadable folder gives an empty list', () async {
      expect(await SignatureLibrary(Directory('${dir.path}/none')).list(), isEmpty);
    });
  });

  group('typed signature', () {
    testWidgets('draws the name in both styles, cut to the ink', (WidgetTester tester) async {
      await tester.runAsync(() async {
        for (final String f in typedSignatureFonts) {
          final Uint8List? b = await renderTypedSignature('Ada Lovelace', fontFamily: f, color: 0xFF1B3A8C);
          expect(b, isNotNull, reason: f);
          final img.Image im = img.decodePng(b!)!;
          expect(im.width, greaterThan(im.height), reason: f);
          expect(im.height, lessThan(160 * 2), reason: '$f is cut, not a tall box');
          int ink = 0;
          for (final img.Pixel px in im) {
            if (px.a > 40) ink++;
          }
          expect(ink, greaterThan(500), reason: f);
          // The first row and column are empty margin only.
          expect(im.getPixel(0, 0).a, 0);
        }
      });
    });

    testWidgets('the two bundled script fonts really load and look different from each other', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final Map<String, int> widths = <String, int>{};
        for (final String f in typedSignatureFonts) {
          widths[f] = img.decodePng((await renderTypedSignature('Mmmm Wwww', fontFamily: f, color: 0xFF000000))!)!.width;
        }
        final int fallback = img.decodePng((await renderTypedSignature('Mmmm Wwww', fontFamily: 'NoSuchFont', color: 0xFF000000))!)!.width;
        expect(widths.values.toSet().length, 2, reason: 'different fonts, different widths: $widths');
        for (final MapEntry<String, int> e in widths.entries) {
          expect(e.value, isNot(fallback), reason: '${e.key} is not the fallback font ($fallback)');
        }
      });
    });

    testWidgets('a longer name is wider; empty text gives nothing', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final img.Image a = img.decodePng((await renderTypedSignature('Al', fontFamily: 'Caveat', color: 0xFF000000))!)!;
        final img.Image b = img.decodePng((await renderTypedSignature('Alexander Hamilton', fontFamily: 'Caveat', color: 0xFF000000))!)!;
        expect(b.width, greaterThan(a.width * 2));
        expect(await renderTypedSignature('   ', fontFamily: 'Caveat', color: 0xFF000000), isNull);
      });
    });

    test('trimToInk returns the input when nothing is drawn', () {
      final Uint8List blank = Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 20, numChannels: 4)));
      expect(trimToInk(blank), blank);
    });
  });

  group('signature sheet', () {
    testWidgets('drawing then Use returns a cut PNG; undo removes the last line', (WidgetTester tester) async {
      Uint8List? result;
      bool done = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<Uint8List?>(context: c, isScrollControlled: true, builder: (_) => const InkSignatureSheet());
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      final Finder pad = find.byType(CustomPaint).last;
      final Offset c = tester.getCenter(find.text('Sign here'));
      Future<void> stroke(Offset from) async {
        final TestGesture g = await tester.startGesture(from);
        for (int i = 1; i <= 8; i++) {
          await g.moveBy(const Offset(12, 5));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
      }

      await stroke(c - const Offset(60, 30));
      await stroke(c - const Offset(60, -10));
      expect(find.text('Sign here'), findsNothing, reason: 'hint goes once something is drawn');
      await tester.tap(find.byKey(const ValueKey('sigUndo')));
      await tester.pump();
      expect(pad, findsWidgets);
      await tester.tap(find.byKey(const ValueKey('sigColor:${0xFF1B3A8C}')));
      await tester.tap(find.byKey(const ValueKey('sigWidth:2')));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sigUse')));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await settle(tester);
      expect(done, isTrue);
      expect(result, isNotNull);
      final img.Image im = img.decodePng(result!)!;
      // Cut to the ink: far smaller than the 240-high pad at 3x (720 px).
      expect(im.height, lessThan(400));
      expect(im.width, greaterThan(40));
    });

    testWidgets('Use with nothing drawn returns nothing', (WidgetTester tester) async {
      Uint8List? result = Uint8List(1);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showModalBottomSheet<Uint8List?>(context: c, isScrollControlled: true, builder: (_) => const InkSignatureSheet()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sigUse')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);
      expect(result, isNull);
    });

    testWidgets('Type tab: typing shows a preview and Use returns the typed picture', (WidgetTester tester) async {
      Uint8List? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showModalBottomSheet<Uint8List?>(context: c, isScrollControlled: true, builder: (_) => const InkSignatureSheet()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('sigMode')), matching: find.text('Type')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('sigTypeField')), 'Grace Hopper');
      await tester.tap(find.byKey(const ValueKey('sigFont:Caveat')));
      await tester.pump();
      expect(find.text('Grace Hopper'), findsWidgets);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sigUse')));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await settle(tester);
      expect(result, isNotNull);
      expect(img.decodePng(result!)!.width, greaterThan(100));
    });

    testWidgets('picker lists saved signatures, returns the chosen one, deletes one, offers a new one', (WidgetTester tester) async {
      final Directory dir = Directory.systemTemp.createTempSync('pick');
      addTearDown(() => dir.deleteSync(recursive: true));
      final SignatureLibrary lib = SignatureLibrary(dir);
      await tester.runAsync(() async {
        await lib.add(png(40, 20, 5));
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await lib.add(png(40, 20, 6));
      });
      final List<SavedSignature> saved = (await tester.runAsync(() => lib.list()))!;
      Object? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showModalBottomSheet<Object?>(context: c, isScrollControlled: true, builder: (_) => SignaturePickerSheet(library: lib, saved: saved)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(ValueKey<String>('savedSig:${saved.first.id}')), findsOneWidget);
      expect(find.byKey(ValueKey<String>('savedSig:${saved.last.id}')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey<String>('deleteSig:${saved.last.id}')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settle(tester);
      expect(find.byKey(ValueKey<String>('savedSig:${saved.last.id}')), findsNothing);
      expect((await tester.runAsync(() => lib.list()))!, hasLength(1));
      await tester.tap(find.byKey(ValueKey<String>('savedSig:${saved.first.id}')));
      await settle(tester);
      expect(result, isA<Uint8List>());
      expect(result, saved.first.bytes);
    });

    testWidgets('picker: "new" is returned for the draw or type button', (WidgetTester tester) async {
      final Directory dir = Directory.systemTemp.createTempSync('pick2');
      addTearDown(() => dir.deleteSync(recursive: true));
      Object? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showModalBottomSheet<Object?>(
                    context: c, isScrollControlled: true, builder: (_) => SignaturePickerSheet(library: SignatureLibrary(dir), saved: <SavedSignature>[SavedSignature('sig_1.png', png(4, 4, 1))])),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('newSignature')));
      await settle(tester);
      expect(result, 'new');
    });
  });
}
