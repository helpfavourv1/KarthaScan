import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/utils/smooth_resize.dart';

void main() {
  test('shrinking averages the pixels instead of dropping some', () {
    final img.Image lines = img.Image(width: 400, height: 40);
    img.fill(lines, color: img.ColorRgb8(255, 255, 255));
    for (int x = 0; x < 400; x += 4) {
      img.fillRect(lines, x1: x, y1: 0, x2: x, y2: 39, color: img.ColorRgb8(0, 0, 0));
    }
    final img.Image small = resizeSmooth(lines, width: 100);
    expect(small.width, 100);
    expect(small.height, 10, reason: 'one side given keeps the shape');
    for (int x = 5; x < 95; x++) {
      final num v = small.getPixel(x, 5).r;
      expect(v, inInclusiveRange(175, 205), reason: 'a quarter dark, not all white or all black (x=$x)');
    }
  });

  test('enlarging blends the edge instead of stepping', () {
    final img.Image tiny = img.Image(width: 4, height: 4);
    for (int y = 0; y < 4; y++) {
      for (int x = 0; x < 4; x++) {
        tiny.setPixelRgb(x, y, x < 2 ? 0 : 255, x < 2 ? 0 : 255, x < 2 ? 0 : 255);
      }
    }
    final img.Image big = resizeSmooth(tiny, width: 64, height: 64);
    final Set<num> shades = <num>{for (int x = 0; x < 64; x++) big.getPixel(x, 32).r.round()};
    expect(shades.length, greaterThan(6), reason: 'a smooth ramp across the edge, not two flat blocks');
  });

  test('same size is returned as it is', () {
    final img.Image a = img.Image(width: 30, height: 20);
    expect(identical(resizeSmooth(a, width: 30, height: 20), a), isTrue);
  });

  test('quarter turns are exact; other angles have soft edges', () {
    final img.Image sq = img.Image(width: 60, height: 40, numChannels: 4);
    img.fillRect(sq, x1: 0, y1: 0, x2: 59, y2: 39, color: img.ColorRgba8(255, 0, 0, 255));
    final img.Image q = rotateSmooth(sq, 90);
    expect(q.width, 40);
    expect(q.height, 60);
    final img.Image t = rotateSmooth(sq, 30);
    int soft = 0;
    for (final img.Pixel p in t) {
      if (p.a > 0 && p.a < 255) soft++;
    }
    expect(soft, greaterThan(40), reason: 'anti-aliased edge pixels');
  });

  test('straighten keeps the size, leaves no empty corner, and tilts the content', () {
    final img.Image src = img.Image(width: 200, height: 100, numChannels: 4)..clear(img.ColorRgba8(255, 255, 255, 255));
    // A black vertical bar in the middle.
    img.fillRect(src, x1: 95, y1: 0, x2: 104, y2: 99, color: img.ColorRgba8(0, 0, 0, 255));
    final img.Image t = straightenFill(src, 10);
    expect(t.width, 200);
    expect(t.height, 100);
    for (final (int x, int y) in [(0, 0), (199, 0), (0, 99), (199, 99)]) {
      expect(t.getPixel(x, y).a, 255, reason: 'corner $x,$y is filled');
    }
    // The bar is tilted: at the top it sits left of where it is at the bottom.
    int barX(int y) {
      for (int x = 0; x < 200; x++) {
        if (t.getPixel(x, y).r < 100) return x;
      }
      return -1;
    }
    expect(barX(5), isNot(barX(94)));
    expect(identical(straightenFill(src, 0), src), isTrue);
    expect(straightenZoom(0, 200, 100), closeTo(1, 1e-9));
    expect(straightenZoom(10, 200, 100), greaterThan(1));
  });
}
