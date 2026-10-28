import 'dart:math' as math;
import 'dart:ui';

/// One sampled touch point: where, and when (milliseconds since the stroke began).
class InkPoint {
  const InkPoint(this.p, this.t);
  final Offset p;
  final int t;
}

/// A short straight piece of a finished line, drawn with round ends.
class InkSegment {
  const InkSegment(this.a, this.b, this.width);
  final Offset a;
  final Offset b;
  final double width;
}

/// Turns raw touch points into smooth, pen-like pieces.
///
/// The path is rounded with quadratic curves through the midpoints of the
/// samples, and the width follows drawing speed: slow strokes are heavier,
/// fast flicks thin out, like ink from a real pen. With [pressure] off the
/// width stays at [baseWidth]. A single tap becomes a dot.
List<InkSegment> buildInkSegments(
  List<InkPoint> points,
  double baseWidth, {
  bool pressure = true,
}) {
  if (points.isEmpty) return const <InkSegment>[];
  if (points.length == 1) {
    return <InkSegment>[InkSegment(points.first.p, points.first.p, baseWidth)];
  }
  // Drop samples closer than half a pixel: they only add jitter.
  final List<InkPoint> pts = <InkPoint>[points.first];
  for (int i = 1; i < points.length; i++) {
    if ((points[i].p - pts.last.p).distance >= 0.5) pts.add(points[i]);
  }
  if (pts.length == 1) {
    return <InkSegment>[InkSegment(pts.first.p, pts.first.p, baseWidth)];
  }
  if (pts.length == 2) {
    return <InkSegment>[InkSegment(pts[0].p, pts[1].p, baseWidth)];
  }

  // Target width at each sample from the speed at that sample.
  final List<double> widths = List<double>.filled(pts.length, baseWidth);
  if (pressure) {
    double smoothed = 1.0;
    for (int i = 1; i < pts.length; i++) {
      final double dist = (pts[i].p - pts[i - 1].p).distance;
      final double dt = math.max(1, pts[i].t - pts[i - 1].t).toDouble();
      final double speed = dist / dt; // pixels per millisecond
      final double factor = (1.5 - speed * 0.55).clamp(0.55, 1.5).toDouble();
      smoothed = smoothed * 0.8 + factor * 0.2;
      widths[i] = baseWidth * smoothed;
    }
    widths[0] = widths[1];
  }

  final List<InkSegment> out = <InkSegment>[];
  Offset start = pts.first.p;
  double startW = widths.first;
  const int steps = 6;
  for (int i = 1; i < pts.length - 1; i++) {
    final Offset control = pts[i].p;
    final Offset end = Offset.lerp(pts[i].p, pts[i + 1].p, 0.5)!;
    final double endW = (widths[i] + widths[i + 1]) / 2;
    Offset prev = start;
    for (int s = 1; s <= steps; s++) {
      final double t = s / steps;
      final double u = 1 - t;
      final Offset q = start * (u * u) + control * (2 * u * t) + end * (t * t);
      final double w = startW + (endW - startW) * t;
      out.add(InkSegment(prev, q, w));
      prev = q;
    }
    start = end;
    startW = endW;
  }
  out.add(InkSegment(start, pts.last.p, widths.last));
  return out;
}

/// A smooth single outline through [points]: quadratic curves through the
/// midpoints of the samples. Drawn as one stroked path, so a translucent
/// highlighter lays down one even band instead of beads where pieces overlap.
Path smoothPath(List<Offset> points) {
  final Path path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) {
    // A tap: a zero-length line drawn with round ends is a dot.
    path.lineTo(points.first.dx + 0.01, points.first.dy);
    return path;
  }
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return path;
  }
  for (int i = 1; i < points.length - 1; i++) {
    final Offset mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}
