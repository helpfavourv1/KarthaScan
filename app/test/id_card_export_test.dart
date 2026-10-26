// test/id_card_export_test.dart
//
// ID card mode: front and back are stacked on one page and delivered as a PDF and
// one picture. Checked on pixels and on the files, including awkward inputs.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/services/export_service.dart';

void main() {
  late Directory dir;
  late Directory out;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('id_card');
    out = Directory('${dir.path}/out')..createSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String side(String name, int w, int h, img.Color color, {int border = 0}) {
    final img.Image im = img.Image(width: w, height: h);
    img.fill(im, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(im, x1: border, y1: border, x2: w - border - 1, y2: h - border - 1, color: color);
    final File f = File('${dir.path}/$name.png')..writeAsBytesSync(img.encodePng(im));
    return f.path;
  }

  Future<Map<String, String>> run(String front, String back, {String title = 'ID Card 1', IdCardLayout layout = IdCardLayout.fullWidth}) =>
      ExportService().exportIdCardPdf(frontPath: front, backPath: back, title: title, outputDirectoryPath: out.path, layout: layout);

  bool isRed(img.Pixel p) => p.r > 200 && p.g < 60 && p.b < 60;
  bool isBlue(img.Pixel p) => p.b > 200 && p.r < 100 && p.g > 80 && p.g < 160;

  test('front is on top, back below, white gap between, one A4 PDF page', () async {
    final String front = side('front', 1000, 630, img.ColorRgb8(255, 0, 0));
    final String back = side('back', 800, 500, img.ColorRgb8(60, 120, 255));
    final Map<String, String> r = await run(front, back);
    final img.Image sheet = img.decodePng(File(r['image']!).readAsBytesSync())!;
    expect(sheet.width, 1200);
    final int frontH = (630 * 1200 / 1000).round();
    final int backH = (500 * 1200 / 800).round();
    expect(sheet.height, frontH + 40 + backH);
    expect(isRed(sheet.getPixel(600, frontH ~/ 2)), isTrue, reason: 'front should be on top');
    expect(isBlue(sheet.getPixel(600, frontH + 40 + backH ~/ 2)), isTrue, reason: 'back should be below');
    final img.Pixel gap = sheet.getPixel(600, frontH + 20);
    expect(gap.r > 250 && gap.g > 250 && gap.b > 250, isTrue, reason: 'gap between the two sides must be white');
    final Uint8List pdf = File(r['pdf']!).readAsBytesSync();
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(String.fromCharCodes(pdf)).length, 1);
    expect(File(r['pdf']!).lengthSync(), greaterThan(1000));
  });

  test('black scanner borders around each side are trimmed away', () async {
    final String front = side('f', 1000, 640, img.ColorRgb8(255, 0, 0), border: 60);
    final String back = side('b', 1000, 640, img.ColorRgb8(60, 120, 255), border: 60);
    final img.Image sheet = img.decodePng(File((await run(front, back))['image']!).readAsBytesSync())!;
    expect(isRed(sheet.getPixel(3, 3)), isTrue, reason: 'black border left on the front');
    expect(isBlue(sheet.getPixel(sheet.width - 4, sheet.height - 4)), isTrue, reason: 'black border left on the back');
  });

  test('a dark card is not mistaken for a black border and trimmed away', () async {
    final String front = side('f', 1000, 630, img.ColorRgb8(0, 0, 90));
    final String back = side('b', 1000, 630, img.ColorRgb8(10, 10, 10));
    final img.Image sheet = img.decodePng(File((await run(front, back))['image']!).readAsBytesSync())!;
    // Nothing may be cut off by more than the 15 percent border allowance per side.
    expect(sheet.height, greaterThan((756 + 40 + 756) * 0.7), reason: 'dark card was cropped away: ${sheet.height}');
  });

  test('portrait front with a landscape back still produces both sides in full width', () async {
    final String front = side('f', 600, 900, img.ColorRgb8(255, 0, 0));
    final String back = side('b', 900, 600, img.ColorRgb8(60, 120, 255));
    final img.Image sheet = img.decodePng(File((await run(front, back))['image']!).readAsBytesSync())!;
    expect(sheet.width, 1200);
    expect(sheet.height, 1800 + 40 + 800);
    expect(isRed(sheet.getPixel(10, 900)), isTrue);
    expect(isBlue(sheet.getPixel(1190, 1800 + 40 + 400)), isTrue);
  });

  group('real size (default)', () {
    test('A4 canvas, 85.6 mm wide cards centred, white outside, front above back', () async {
      final String front = side('f', 1000, 640, img.ColorRgb8(255, 0, 0));
      final String back = side('b', 1000, 640, img.ColorRgb8(60, 120, 255));
      final Map<String, String> r = await run(front, back, layout: IdCardLayout.realSize);
      final img.Image sheet = img.decodePng(File(r['image']!).readAsBytesSync())!;
      expect(sheet.width, 2480);
      expect(sheet.height, 3508);
      expect(isRed(sheet.getPixel(1240, 354 + 100)), isTrue, reason: 'front near the top');
      expect(isBlue(sheet.getPixel(1240, 354 + 647 + 118 + 100)), isTrue, reason: 'back below the front');
      final img.Pixel left = sheet.getPixel(300, 500);
      expect(left.r > 250 && left.g > 250 && left.b > 250, isTrue, reason: 'white outside the card');
      expect(isRed(sheet.getPixel(734 + 20, 354 + 100)), isTrue, reason: 'card left edge ~ x 734');
      final img.Pixel just = sheet.getPixel(734 - 20, 354 + 100);
      expect(just.r > 250 && just.g > 250, isTrue);
      expect(String.fromCharCodes(File(r['pdf']!).readAsBytesSync().take(5)), '%PDF-');
    });

    test('portrait cards that are too tall shrink to fit the page', () async {
      final String front = side('f', 600, 1800, img.ColorRgb8(255, 0, 0));
      final String back = side('b', 600, 1800, img.ColorRgb8(60, 120, 255));
      final Map<String, String> r = await run(front, back, layout: IdCardLayout.realSize);
      final img.Image sheet = img.decodePng(File(r['image']!).readAsBytesSync())!;
      expect(sheet.height, 3508);
      expect(isRed(sheet.getPixel(1240, 700)), isTrue);
      expect(isBlue(sheet.getPixel(1240, 3508 - 700)), isTrue);
    });

    test('12 MP photos work', () async {
      final String front = side('f', 4000, 3000, img.ColorRgb8(255, 0, 0));
      final String back = side('b', 4000, 3000, img.ColorRgb8(60, 120, 255));
      final Map<String, String> r = await run(front, back, layout: IdCardLayout.realSize);
      expect(img.decodePng(File(r['image']!).readAsBytesSync())!.width, 2480);
    });
  });

  test('large photos (12 MP each) are handled', () async {
    final String front = side('f', 4000, 3000, img.ColorRgb8(255, 0, 0));
    final String back = side('b', 4000, 3000, img.ColorRgb8(60, 120, 255));
    final Map<String, String> r = await run(front, back);
    expect(img.decodePng(File(r['image']!).readAsBytesSync())!.width, 1200);
    expect(File(r['pdf']!).lengthSync(), greaterThan(1000));
  });

  test('an unreadable back image fails cleanly and leaves no files behind', () async {
    final String front = side('f', 400, 250, img.ColorRgb8(255, 0, 0));
    final File bad = File('${dir.path}/bad.png')..writeAsBytesSync(Uint8List.fromList(<int>[1, 2, 3, 4, 5]));
    await expectLater(run(front, bad.path), throwsA(isA<ExportFailedException>()));
    expect(out.listSync(), isEmpty);
  });

  test('a missing file fails cleanly', () async {
    final String front = side('f', 400, 250, img.ColorRgb8(255, 0, 0));
    await expectLater(run(front, '${dir.path}/nope.png'), throwsA(isA<ExportFailedException>()));
    expect(out.listSync(), isEmpty);
  });

  test('awkward titles stay inside the output folder', () async {
    final String front = side('f', 400, 250, img.ColorRgb8(255, 0, 0));
    final String back = side('b', 400, 250, img.ColorRgb8(60, 120, 255));
    final Map<String, String> r = await run(front, back, title: '../../ID: a/b*?"<>|');
    for (final String path in <String>[r['pdf']!, r['image']!]) {
      expect(File(path).parent.path, out.path, reason: 'file escaped the output folder: $path');
      expect(File(path).existsSync(), isTrue);
    }
  });

  test('running it twice with the same title does not mix up the results', () async {
    final String front = side('f', 400, 250, img.ColorRgb8(255, 0, 0));
    final String back = side('b', 400, 250, img.ColorRgb8(60, 120, 255));
    final Map<String, String> a = await run(front, back, title: 'Same');
    final Map<String, String> b = await run(back, front, title: 'Same');
    final img.Image second = img.decodePng(File(b['image']!).readAsBytesSync())!;
    expect(isBlue(second.getPixel(600, 10)), isTrue, reason: 'second run should have the blue side on top');
    expect(a['pdf'], isNotNull);
  });
}
