// test/rotation_export_test.dart
//
// The editor preview rotates the whole page (erasing and layers included).
// Export must match: erase/draw in the unrotated frame, rotate last.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/export_service.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rotation_export_test');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 40x20 white page, top-left quarter erased in black (x 0..10, y 0..10).
  Future<img.Image> render(int turns) async {
    final img.Image page = img.Image(width: 40, height: 20);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final File file = File('${dir.path}/page.png')
      ..writeAsBytesSync(img.encodePng(page));
    final DateTime now = DateTime(2026, 1, 1);
    final ScanDocument doc = ScanDocument(
      id: 'd',
      title: 'T',
      pageCount: 1,
      pagePaths: <String>[file.path],
      createdAt: now,
      updatedAt: now,
      ocrText: '',
      thumbnailPath: file.path,
      pageTransforms: <int, PageTransform>{
        0: PageTransform(
          rotationTurns: turns,
          eraserStrokes: <Map<String, dynamic>>[
            <String, dynamic>{
              'points': <List<double>>[
                <double>[0, 0],
                <double>[0.25, 0.5],
              ],
              'color': 0xFF000000,
              'width': 0.05,
              'rect': true,
            },
          ],
        ),
      },
    );
    final bytes = await ExportService().renderPageForOutput(doc, 0);
    return img.decodePng(bytes)!;
  }

  bool dark(img.Image image, int x, int y) => image.getPixel(x, y).r < 128;

  test('no rotation: erased corner stays top-left', () async {
    final img.Image out = await render(0);
    expect(out.width, 40);
    expect(dark(out, 3, 3), isTrue);
    expect(dark(out, 36, 3), isFalse);
  });

  test('90 degrees clockwise: erased corner moves to top-right', () async {
    final img.Image out = await render(1);
    expect((out.width, out.height), (20, 40));
    expect(dark(out, 17, 3), isTrue);
    expect(dark(out, 3, 3), isFalse);
    expect(dark(out, 3, 36), isFalse);
  });

  test('180 degrees: erased corner moves to bottom-right', () async {
    final img.Image out = await render(2);
    expect(dark(out, 36, 16), isTrue);
    expect(dark(out, 3, 3), isFalse);
  });

  test('270 degrees: erased corner moves to bottom-left', () async {
    final img.Image out = await render(3);
    expect((out.width, out.height), (20, 40));
    expect(dark(out, 3, 36), isTrue);
    expect(dark(out, 17, 3), isFalse);
  });
}
