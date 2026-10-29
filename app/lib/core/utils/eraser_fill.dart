import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;

/// The colour to paint over an erased spot so it blends with the page: the middle
/// (median) colour of a ring of samples just outside the marked area. For a
/// brush stroke the ring follows the stroke on both sides; for a box it runs
/// around the box. Points and [width] are in the same units as [displayW] x
/// [displayH], the size the page is drawn at. Returns 0xAARRGGBB (opaque), or
/// null if nothing could be sampled.
int? autoFillColor(img.Image page, {required List<Offset> points, required double width, required bool isBox, required double displayW, required double displayH}) {
  if (points.isEmpty || displayW <= 0 || displayH <= 0) return null;
  final List<Offset> samples = <Offset>[];
  final double reach = width / 2 + 6;
  if (isBox && points.length >= 2) {
    final Rect r = Rect.fromPoints(points[0], points[1]).inflate(6);
    const int perSide = 8;
    for (int i = 0; i <= perSide; i++) {
      final double t = i / perSide;
      samples
        ..add(Offset(r.left + r.width * t, r.top))
        ..add(Offset(r.left + r.width * t, r.bottom))
        ..add(Offset(r.left, r.top + r.height * t))
        ..add(Offset(r.right, r.top + r.height * t));
    }
  } else {
    final int n = math.min(points.length, 24);
    for (int k = 0; k < n; k++) {
      final int i = n == 1 ? 0 : (k * (points.length - 1) / (n - 1)).round();
      final Offset p = points[i];
      final Offset a = points[math.max(0, i - 1)], b = points[math.min(points.length - 1, i + 1)];
      Offset d = b - a;
      d = d.distance == 0 ? const Offset(1, 0) : d / d.distance;
      final Offset normal = Offset(-d.dy, d.dx);
      samples
        ..add(p + normal * reach)
        ..add(p - normal * reach);
      if (points.length == 1) {
        samples
          ..add(p + const Offset(1, 0) * reach)
          ..add(p - const Offset(1, 0) * reach);
      }
    }
  }
  final List<int> rs = <int>[], gs = <int>[], bs = <int>[];
  for (final Offset s in samples) {
    final int x = (s.dx / displayW * page.width).round(), y = (s.dy / displayH * page.height).round();
    if (x < 0 || y < 0 || x >= page.width || y >= page.height) continue;
    final img.Pixel px = page.getPixel(x, y);
    rs.add(px.r.toInt());
    gs.add(px.g.toInt());
    bs.add(px.b.toInt());
  }
  if (rs.isEmpty) return null;
  int med(List<int> v) {
    v.sort();
    return v[v.length ~/ 2];
  }

  return 0xFF000000 | (med(rs).clamp(0, 255) << 16) | (med(gs).clamp(0, 255) << 8) | med(bs).clamp(0, 255);
}
