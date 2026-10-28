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

/// Turns [src] by [degrees]. Quarter turns are exact; other angles are smoothed
/// (the default would leave stair-steps along every edge).
img.Image rotateSmooth(img.Image src, num degrees) {
  final bool quarter = degrees % 90 == 0;
  return img.copyRotate(src, angle: degrees, interpolation: quarter ? img.Interpolation.nearest : img.Interpolation.cubic);
}
