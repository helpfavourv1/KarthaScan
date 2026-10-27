import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Side length, in pixels, a seal logo is stored at. The logo is drawn inside a
/// circle about a fifth of the seal, so this is already generous.
const int sealLogoSize = 256;

/// Prepares a picked picture as a seal logo: centre-cropped to a square, shrunk to
/// [sealLogoSize], cut to a circle, and optionally with its white background made
/// transparent. Small on purpose: the picture is saved inside every seal made from
/// it (and with every copy), so a full photo would bloat the document.
Uint8List prepareSealLogo(Uint8List raw, {bool removeWhite = false}) {
  final img.Image? decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  final img.Image upright = img.bakeOrientation(decoded);
  final int side = upright.width < upright.height ? upright.width : upright.height;
  final img.Image square = img.copyCrop(
    upright,
    x: (upright.width - side) ~/ 2,
    y: (upright.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final img.Image small = img.copyResize(square, width: sealLogoSize, height: sealLogoSize, interpolation: img.Interpolation.average).convert(numChannels: 4);

  const double c = sealLogoSize / 2;
  for (int y = 0; y < sealLogoSize; y++) {
    for (int x = 0; x < sealLogoSize; x++) {
      final double dx = x + 0.5 - c, dy = y + 0.5 - c;
      final double dist = (dx * dx + dy * dy);
      final img.Pixel p = small.getPixel(x, y);
      // Soft one-pixel edge on the circle.
      final double edge = (c - math.sqrt(dist)).clamp(0.0, 1.0);
      double alpha = edge;
      if (removeWhite) {
        final num m = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
        if (m >= 245) {
          alpha = 0;
        } else if (m >= 215) {
          alpha *= (245 - m) / 30;
        }
      }
      p.a = (alpha * 255).round();
    }
  }
  return Uint8List.fromList(img.encodePng(small, level: 9));
}
