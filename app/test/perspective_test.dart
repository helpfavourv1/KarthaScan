import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/utils/perspective.dart';

void main() {
  test('an upright quad warps to the same pixels as a crop', () {
    final img.Image src = img.Image(width: 100, height: 80, numChannels: 4);
    for (final p in src) {
      p..r = p.x * 2
        ..g = p.y * 3
        ..b = 7
        ..a = 255;
    }
    final quad = <Offset>[const Offset(10, 10), const Offset(59, 10), const Offset(59, 49), const Offset(10, 49)];
    final img.Image out = warpQuad(src, quad)!;
    expect(out.width, 49);
    expect(out.height, 39);
    expect(out.getPixel(0, 0).r, src.getPixel(10, 10).r);
    // The last output pixel lands exactly on the bottom-right corner.
    expect(out.getPixel(48, 38).g, src.getPixel(59, 49).g);
  });

  test('a tilted page is straightened and aspect forces the shape', () {
    final img.Image src = img.Image(width: 200, height: 200, numChannels: 4)..clear(img.ColorRgba8(0, 0, 0, 255));
    final quad = <Offset>[const Offset(40, 20), const Offset(180, 40), const Offset(160, 180), const Offset(20, 150)];
    final img.Image out = warpQuad(src, quad, aspect: 0.5)!;
    expect(out.width / out.height, closeTo(0.5, 0.01));
    expect(quadOutputSize(quad).width, greaterThan(100));
  });

  test('twisted or tiny quads are refused', () {
    expect(isUsableQuad(const [Offset(0, 0), Offset(50, 50), Offset(50, 0), Offset(0, 50)]), isFalse);
    expect(isUsableQuad(const [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)]), isFalse);
    expect(isUprightRect(const [Offset(0, 0), Offset(9, 0), Offset(9, 9), Offset(0, 9)]), isTrue);
  });

  test('auto-detect finds a light page on a dark table', () {
    final img.Image src = img.Image(width: 400, height: 300, numChannels: 4)..clear(img.ColorRgba8(40, 30, 20, 255));
    img.fillRect(src, x1: 80, y1: 50, x2: 320, y2: 260, color: img.ColorRgba8(240, 240, 235, 255));
    final q = detectDocumentQuad(src)!;
    expect(q[0].dx, closeTo(80, 8));
    expect(q[0].dy, closeTo(50, 8));
    expect(q[2].dx, closeTo(320, 8));
    expect(q[2].dy, closeTo(260, 8));
    expect(detectDocumentQuad(img.Image(width: 200, height: 200, numChannels: 4)..clear(img.ColorRgba8(200, 200, 200, 255))), isNull);
  });

  test('page transform keeps the quad through json and sizes the page', () {
    final t = PageTransform(
      cropRect: const Rect.fromLTRB(20, 20, 180, 180),
      cropQuad: const [Offset(40, 20), Offset(180, 40), Offset(160, 180), Offset(20, 150)],
      cropAspect: 0.7,
    );
    final back = PageTransform.fromJson(t.toJson());
    expect(back.cropQuad, t.cropQuad);
    expect(back.cropAspect, 0.7);
    expect(back.croppedSize!.width / back.croppedSize!.height, closeTo(0.7, 0.01));
    expect(t.copyWith(clearCropQuad: true).cropQuad, isNull);
  });
}
