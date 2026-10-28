import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'ink_stroke.dart';

/// The tools of the annotate sheet. The first five draw; [select] picks a mark
/// to move, recolour or delete; [eraser] removes marks it is dragged across.
enum AnnotationMode { pen, highlighter, rect, arrow, ellipse, select, eraser }

/// How strongly the highlighter covers the page, so the text stays readable.
const double highlighterAlpha = 0.4;

/// One mark on the page. Immutable: every change makes a new one, which is
/// what lets undo and redo simply swap whole lists.
class AnnotationItem {
  const AnnotationItem({
    required this.mode,
    required this.color,
    required this.width,
    required this.points,
  });

  final AnnotationMode mode;
  final int color;
  final double width;

  /// Freehand: every sampled point. Shapes: the two corners (or line ends).
  final List<Offset> points;

  bool get isFreehand => mode == AnnotationMode.pen || mode == AnnotationMode.highlighter;

  AnnotationItem copyWith({int? color, double? width, List<Offset>? points}) =>
      AnnotationItem(mode: mode, color: color ?? this.color, width: width ?? this.width, points: points ?? this.points);

  AnnotationItem moved(Offset by) =>
      copyWith(points: <Offset>[for (final Offset o in points) o + by]);
}

/// Draws one mark.
void paintAnnotation(Canvas canvas, AnnotationItem item) {
  if (item.points.isEmpty) return;
  final bool hl = item.mode == AnnotationMode.highlighter;
  final Paint paint = Paint()
    ..color = hl ? Color(item.color).withValues(alpha: highlighterAlpha) : Color(item.color)
    ..strokeWidth = item.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;
  if (item.isFreehand) {
    canvas.drawPath(smoothPath(item.points), paint);
    return;
  }
  if (item.points.length < 2) return;
  final Offset a = item.points.first;
  final Offset b = item.points.last;
  switch (item.mode) {
    case AnnotationMode.rect:
      canvas.drawRect(Rect.fromPoints(a, b), paint);
    case AnnotationMode.ellipse:
      canvas.drawOval(Rect.fromPoints(a, b), paint);
    case AnnotationMode.arrow:
      canvas.drawLine(a, b, paint);
      final double angle = (b - a).direction;
      final double headLen = 12.0 + item.width * 2;
      final Offset p1 = b - Offset.fromDirection(angle - 0.5, headLen);
      final Offset p2 = b - Offset.fromDirection(angle + 0.5, headLen);
      canvas.drawPath(
        Path()..moveTo(b.dx, b.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close(),
        paint..style = PaintingStyle.fill,
      );
    default:
      break;
  }
}

/// The box around a mark, used to show what is selected.
Rect annotationBounds(AnnotationItem item) {
  if (item.points.isEmpty) return Rect.zero;
  double l = item.points.first.dx, r = l, t = item.points.first.dy, b = t;
  for (final Offset o in item.points) {
    l = math.min(l, o.dx);
    r = math.max(r, o.dx);
    t = math.min(t, o.dy);
    b = math.max(b, o.dy);
  }
  return Rect.fromLTRB(l, t, r, b).inflate(item.width / 2 + 2);
}

double _distToSegment(Offset p, Offset a, Offset b) {
  final Offset ab = b - a;
  final double len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final double t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0).toDouble();
  return (p - (a + ab * t)).distance;
}

double _distToPolyline(Offset p, List<Offset> pts, {bool closed = false}) {
  if (pts.isEmpty) return double.infinity;
  if (pts.length == 1) return (p - pts.first).distance;
  double best = double.infinity;
  for (int i = 0; i < pts.length - 1; i++) {
    best = math.min(best, _distToSegment(p, pts[i], pts[i + 1]));
  }
  if (closed) best = math.min(best, _distToSegment(p, pts.last, pts.first));
  return best;
}

/// Whether [p] is on the mark (within [tolerance] of its drawn line). Shapes
/// are hit on their outline, so tapping inside a box still reaches what is under it.
bool annotationHit(AnnotationItem item, Offset p, double tolerance) {
  final double reach = item.width / 2 + tolerance;
  if (item.isFreehand || item.points.length < 2) {
    return _distToPolyline(p, item.points) <= reach;
  }
  final Offset a = item.points.first;
  final Offset b = item.points.last;
  switch (item.mode) {
    case AnnotationMode.arrow:
      return _distToSegment(p, a, b) <= reach;
    case AnnotationMode.rect:
      final Rect r = Rect.fromPoints(a, b);
      return _distToPolyline(p, <Offset>[r.topLeft, r.topRight, r.bottomRight, r.bottomLeft], closed: true) <= reach;
    case AnnotationMode.ellipse:
      final Rect r = Rect.fromPoints(a, b);
      final List<Offset> ring = <Offset>[
        for (int i = 0; i < 48; i++)
          Offset(r.center.dx + r.width / 2 * math.cos(i * math.pi / 24), r.center.dy + r.height / 2 * math.sin(i * math.pi / 24)),
      ];
      return _distToPolyline(p, ring, closed: true) <= reach;
    default:
      return false;
  }
}

/// The result of the annotate sheet: the drawing cut to its ink, and where and
/// how large to put it so it lands exactly where it was drawn on the page.
class AnnotateResult {
  const AnnotateResult(this.bytes, this.pctX, this.pctY, this.scale);
  final Uint8List bytes;
  final double pctX;
  final double pctY;
  final double scale;
}

/// A drawing is placed by its width as a share of the page (28 % x scale), so the
/// scale that reproduces the drawn size is (inkWidth / frameWidth) / 0.28.
const double annotateBaseWidthFraction = 0.28;

/// Cuts [png] (the whole page frame, transparent where nothing is drawn) to its
/// ink and works out the placement. Null if nothing is drawn or it cannot be read.
AnnotateResult? trimAnnotation(Uint8List png) {
  try {
    final img.Image? full = img.decodePng(png);
    if (full == null || full.width < 1 || full.height < 1) return null;
    final List<int> box = img.findTrim(full, mode: img.TrimMode.transparent);
    final int x = box[0], y = box[1], w = box[2], h = box[3];
    if (w < 1 || h < 1) return null;
    // findTrim on a fully transparent picture reports the whole picture; check.
    bool ink = false;
    for (final img.Pixel px in full) {
      if (px.a > 0) {
        ink = true;
        break;
      }
    }
    if (!ink) return null;
    final img.Image cut = img.copyCrop(full, x: x, y: y, width: w, height: h);
    final double scale = ((w / full.width) / annotateBaseWidthFraction).clamp(0.1, 5.0).toDouble();
    return AnnotateResult(
      Uint8List.fromList(img.encodePng(cut)),
      ((x + w / 2) / full.width).clamp(0.0, 1.0).toDouble(),
      ((y + h / 2) / full.height).clamp(0.0, 1.0).toDouble(),
      scale,
    );
  } catch (_) {
    return null;
  }
}
