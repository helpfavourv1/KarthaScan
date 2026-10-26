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

  Future<Map<String, String>> run(String front, String back, {String title = 'ID Card 1'}) =>
      ExportService().exportIdCardPdf(frontPath: front, backPath: back, title: title, outputDirectoryPath: out.path);

  bool isRed(img.Pixel p) => p.r > 200 && p.g < 60 && p.b < 60;
  bool isBlue(img.Pixel p) => p.b > 200 && p.r < 60 && p.g < 60;

  test('front is on top, back below, white gap between, one A4 PDF page', () async {
    final String front = side('front', 1000, 630, img.ColorRgb8(255, 0, 0));
    final String back = side('back', 800, 500, img.ColorRgb8(0, 0, 255));
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
    final String back = side('b', 1000, 640, img.ColorRgb8(0, 0, 255), border: 60);
    final img.Image sheet = img.decodePng(File((await run(front, back))['image']!).readAsBytesSync())!;
    expect(isRed(sheet.getPixel(3, 3)), isTrue, reason: 'black border left on the front');
    expect(isBlue(sheet.getPixel(sheet.width - 4, sheet.height - 4)), isTrue, reason: 'black border left on the back');
  });

  test('portrait front with a landscape back still produces both sides in full width', () async {
    final String front = side('f', 600, 900, img.ColorRgb8(255, 0, 0));
    final String back = side('b', 900, 600, img.ColorRgb8(0, 0, 255));
    final img.Image sheet = img.decodePng(File((await run(front, back))['image']!).readAsBytesSync())!;
    expect(sheet.width, 1200);
    expect(sheet.height, 1800 + 40 + 800);
    expect(isRed(sheet.getPixel(10, 900)), isTrue);
    expect(isBlue(sheet.getPixel(1190, 1800 + 40 + 400)), isTrue);
  });

  test('large photos (12 MP each) are handled', () async {
    final String front = side('f', 4000, 3000, img.ColorRgb8(255, 0, 0));
    final String back = side('b', 4000, 3000, img.ColorRgb8(0, 0, 255));
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
    final String back = side('b', 400, 250, img.ColorRgb8(0, 0, 255));
    final Map<String, String> r = await run(front, back, title: '../../ID: a/b*?"<>|');
    for (final String path in <String>[r['pdf']!, r['image']!]) {
      expect(File(path).parent.path, out.path, reason: 'file escaped the output folder: $path');
      expect(File(path).existsSync(), isTrue);
    }
  });

  test('running it twice with the same title does not mix up the results', () async {
    final String front = side('f', 400, 250, img.ColorRgb8(255, 0, 0));
    final String back = side('b', 400, 250, img.ColorRgb8(0, 0, 255));
    final Map<String, String> a = await run(front, back, title: 'Same');
    final Map<String, String> b = await run(back, front, title: 'Same');
    final img.Image second = img.decodePng(File(b['image']!).readAsBytesSync())!;
    expect(isBlue(second.getPixel(600, 10)), isTrue, reason: 'second run should have the blue side on top');
    expect(a['pdf'], isNotNull);
  });
}
