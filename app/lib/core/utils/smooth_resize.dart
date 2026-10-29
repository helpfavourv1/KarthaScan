import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Resizes [src] to [width] x [height] (give one to keep the shape, or both).
///
/// The image package resizes with nearest-neighbour unless told otherwise, which
/// makes text jagged when a page is shrunk and edges stair-stepped when a picture
/// is enlarged. This picks the right method for the direction: area average when
/// the result has fewer pixels, cubic when it has more.
img.Image resizeSmooth(img.Image src, {int? width, int? height}) {
  assert(width != null || height != null);
  final int tw = width ?? ((src.width * height! / src.height).round().clamp(1, 1 << 20));
  final int th = height ?? ((src.height * width! / src.width).round().clamp(1, 1 << 20));
  if (tw == src.width && th == src.height) return src;
  final bool shrinking = tw * th < src.width * src.height;
  return img.copyResize(
    src,
    width: tw,
    height: th,
    interpolation: shrinking ? img.Interpolation.average : img.Interpolation.cubic,
  );
}

/// Turns [src] clockwise by [degrees]. Quarter turns are exact; other angles are
/// sampled smoothly (bilinear, alpha-aware) so edges are soft, not stair-stepped,
/// and the corners that open up are transparent.
img.Image rotateSmooth(img.Image src, num degrees) {
  if (degrees % 90 == 0) {
    return img.copyRotate(src, angle: degrees, interpolation: img.Interpolation.nearest);
  }
  final double a = degrees * math.pi / 180;
  final double c = math.cos(a), sn = math.sin(a);
  final int sw = src.width, sh = src.height;
  final int ow = (sw * c.abs() + sh * sn.abs()).ceil(), oh = (sw * sn.abs() + sh * c.abs()).ceil();
  final img.Image base = (src.format == img.Format.uint8 && src.numChannels == 4) ? src : src.convert(format: img.Format.uint8, numChannels: 4);
  final Uint8List s = base.getBytes(order: img.ChannelOrder.rgba);
  final Uint8List out = Uint8List(ow * oh * 4);
  final double ocx = ow / 2, ocy = oh / 2, scx = sw / 2, scy = sh / 2;
  int o = 0;
  for (int y = 0; y < oh; y++) {
    for (int x = 0; x < ow; x++) {
      final double u = x + 0.5 - ocx, v = y + 0.5 - ocy;
      final double fx = u * c + v * sn + scx - 0.5, fy = -u * sn + v * c + scy - 0.5;
      final int x0 = fx.floor(), y0 = fy.floor();
      final double tx = fx - x0, ty = fy - y0;
      double r = 0, g = 0, b = 0, al = 0;
      for (int k = 0; k < 4; k++) {
        final int xx = x0 + (k & 1), yy = y0 + (k >> 1);
        if (xx < 0 || yy < 0 || xx >= sw || yy >= sh) continue;
        final double wgt = ((k & 1) == 1 ? tx : 1 - tx) * ((k >> 1) == 1 ? ty : 1 - ty);
        final int i = (yy * sw + xx) * 4;
        final double pa = s[i + 3] / 255 * wgt;
        r += s[i] * pa;
        g += s[i + 1] * pa;
        b += s[i + 2] * pa;
        al += pa;
      }
      if (al > 0) {
        out[o] = (r / al + 0.5).toInt().clamp(0, 255);
        out[o + 1] = (g / al + 0.5).toInt().clamp(0, 255);
        out[o + 2] = (b / al + 0.5).toInt().clamp(0, 255);
        out[o + 3] = (al * 255 + 0.5).toInt().clamp(0, 255);
      }
      o += 4;
    }
  }
  return img.Image.fromBytes(width: ow, height: oh, bytes: out.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
}
