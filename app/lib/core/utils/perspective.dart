import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:image/image.dart' as img;

import 'smooth_resize.dart';

/// The most pixels a straightened page may have.
const int maxWarpPixels = 40000000;

double _d(Offset a, Offset b) => (a - b).distance;

/// The size of the picture made by straightening [quad] (top-left, top-right,
/// bottom-right, bottom-left, in photo pixels): as wide and tall as the longer
/// of each pair of opposite edges. With [aspect] (width / height) the height is
/// set from the width so the page has exactly that shape.
Size quadOutputSize(List<Offset> quad, {double? aspect}) {
  double w = math.max(_d(quad[0], quad[1]), _d(quad[3], quad[2]));
  double h = math.max(_d(quad[0], quad[3]), _d(quad[1], quad[2]));
  if (aspect != null && aspect > 0) h = w / aspect;
  w = w.clamp(1.0, 20000.0).toDouble();
  h = h.clamp(1.0, 20000.0).toDouble();
  if (w * h > maxWarpPixels) {
    final double k = math.sqrt(maxWarpPixels / (w * h));
    w *= k;
    h *= k;
  }
  return Size(w.roundToDouble(), h.roundToDouble());
}

/// The smallest upright box around [quad].
Rect quadBounds(List<Offset> quad) {
  double l = quad[0].dx, r = l, t = quad[0].dy, b = t;
  for (final Offset o in quad) {
    l = math.min(l, o.dx);
    r = math.max(r, o.dx);
    t = math.min(t, o.dy);
    b = math.max(b, o.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// True when the four corners already form an upright rectangle, so a plain crop
/// gives the same result as straightening.
bool isUprightRect(List<Offset> q, {double tolerance = 0.75}) {
  return (q[0].dx - q[3].dx).abs() <= tolerance &&
      (q[1].dx - q[2].dx).abs() <= tolerance &&
      (q[0].dy - q[1].dy).abs() <= tolerance &&
      (q[3].dy - q[2].dy).abs() <= tolerance;
}

/// Whether the corners make a usable four-sided shape: no crossing sides, no
/// collapsed edge. (Used to refuse a twisted selection.)
bool isUsableQuad(List<Offset> q, {double minSide = 8}) {
  if (q.length != 4) return false;
  for (int i = 0; i < 4; i++) {
    if (_d(q[i], q[(i + 1) % 4]) < minSide) return false;
  }
  // Convex and consistently turning: every cross product has the same sign.
  double? sign;
  for (int i = 0; i < 4; i++) {
    final Offset a = q[(i + 1) % 4] - q[i];
    final Offset b = q[(i + 2) % 4] - q[(i + 1) % 4];
    final double cross = a.dx * b.dy - a.dy * b.dx;
    if (cross == 0) return false;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
}

/// Solves the 8 numbers of the mapping from the straightened page back to the
/// photo: x = (h0 u + h1 v + h2) / (h6 u + h7 v + 1), y = (h3 u + h4 v + h5) / (...).
/// Null if the corners do not define one.
List<double>? solveHomography(List<Offset> dst, List<Offset> src) {
  final List<List<double>> m = List<List<double>>.generate(8, (_) => List<double>.filled(9, 0));
  for (int i = 0; i < 4; i++) {
    final double u = dst[i].dx, v = dst[i].dy, x = src[i].dx, y = src[i].dy;
    m[2 * i] = <double>[u, v, 1, 0, 0, 0, -x * u, -x * v, x];
    m[2 * i + 1] = <double>[0, 0, 0, u, v, 1, -y * u, -y * v, y];
  }
  for (int c = 0; c < 8; c++) {
    int p = c;
    for (int r = c + 1; r < 8; r++) {
      if (m[r][c].abs() > m[p][c].abs()) p = r;
    }
    if (m[p][c].abs() < 1e-9) return null;
    final List<double> t = m[c];
    m[c] = m[p];
    m[p] = t;
    for (int r = 0; r < 8; r++) {
      if (r == c) continue;
      final double f = m[r][c] / m[c][c];
      if (f == 0) continue;
      for (int k = c; k < 9; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  return <double>[for (int i = 0; i < 8; i++) m[i][8] / m[i][i]];
}

/// Straightens the part of [src] inside [quad] into an upright page, sampling
/// smoothly (bilinear). Returns null when the corners cannot be used.
img.Image? warpQuad(img.Image src, List<Offset> quad, {double? aspect}) {
  if (!isUsableQuad(quad, minSide: 2)) return null;
  final Size size = quadOutputSize(quad, aspect: aspect);
  final int w = size.width.round(), h = size.height.round();
  final List<Offset> dst = <Offset>[Offset.zero, Offset(w - 1.0, 0), Offset(w - 1.0, h - 1.0), Offset(0, h - 1.0)];
  final List<double>? H = solveHomography(dst, quad);
  if (H == null) return null;
  final img.Image base = (src.format == img.Format.uint8 && src.numChannels == 4) ? src : src.convert(format: img.Format.uint8, numChannels: 4);
  final Uint8List s = base.getBytes(order: img.ChannelOrder.rgba);
  final int sw = base.width, sh = base.height;
  final Uint8List out = Uint8List(w * h * 4);
  final double maxX = sw - 1.0, maxY = sh - 1.0;
  int o = 0;
  for (int v = 0; v < h; v++) {
    for (int u = 0; u < w; u++) {
      final double den = H[6] * u + H[7] * v + 1;
      double x = (H[0] * u + H[1] * v + H[2]) / den;
      double y = (H[3] * u + H[4] * v + H[5]) / den;
      x = x < 0 ? 0 : (x > maxX ? maxX : x);
      y = y < 0 ? 0 : (y > maxY ? maxY : y);
      final int x0 = x.floor(), y0 = y.floor();
      final int x1 = x0 + 1 > sw - 1 ? x0 : x0 + 1;
      final int y1 = y0 + 1 > sh - 1 ? y0 : y0 + 1;
      final double fx = x - x0, fy = y - y0;
      final int i00 = (y0 * sw + x0) * 4, i10 = (y0 * sw + x1) * 4, i01 = (y1 * sw + x0) * 4, i11 = (y1 * sw + x1) * 4;
      for (int c = 0; c < 3; c++) {
        final double top = s[i00 + c] * (1 - fx) + s[i10 + c] * fx;
        final double bot = s[i01 + c] * (1 - fx) + s[i11 + c] * fx;
        out[o + c] = (top * (1 - fy) + bot * fy + 0.5).toInt();
      }
      out[o + 3] = 255;
      o += 4;
    }
  }
  return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
}

/// Looks for a page lying on a different-coloured background and returns its
/// corners (top-left, top-right, bottom-right, bottom-left) in [src] pixels,
/// or null when no page stands out. The background is estimated from the
/// picture's edge; the page is the biggest connected area that differs from
/// it, and its corners are its extreme points along the two diagonals.
List<Offset>? detectDocumentQuad(img.Image src) {
  final int longest = math.max(src.width, src.height);
  final img.Image small = longest > 420 ? resizeSmooth(src, width: src.width >= src.height ? 420 : null, height: src.height > src.width ? 420 : null) : src;
  final int w = small.width, h = small.height;
  if (w < 20 || h < 20) return null;
  final img.Image rgb = small.numChannels == 4 && small.format == img.Format.uint8 ? small : small.convert(format: img.Format.uint8, numChannels: 4);
  final Uint8List px = rgb.getBytes(order: img.ChannelOrder.rgba);
  // Light blur to ignore print, texture and noise.
  final List<double> lum = List<double>.filled(w * h, 0);
  final List<double> cr = List<double>.filled(w * h, 0), cg = List<double>.filled(w * h, 0), cb = List<double>.filled(w * h, 0);
  for (int i = 0; i < w * h; i++) {
    cr[i] = px[i * 4].toDouble();
    cg[i] = px[i * 4 + 1].toDouble();
    cb[i] = px[i * 4 + 2].toDouble();
  }
  List<double> blur(List<double> a) {
    final List<double> t = List<double>.filled(w * h, 0), r = List<double>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double s = 0;
        int n = 0;
        for (int k = math.max(0, x - 2); k <= math.min(w - 1, x + 2); k++) {
          s += a[y * w + k];
          n++;
        }
        t[y * w + x] = s / n;
      }
    }
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double s = 0;
        int n = 0;
        for (int k = math.max(0, y - 2); k <= math.min(h - 1, y + 2); k++) {
          s += t[k * w + x];
          n++;
        }
        r[y * w + x] = s / n;
      }
    }
    return r;
  }

  final List<double> r = blur(cr), g = blur(cg), b = blur(cb);
  for (int i = 0; i < w * h; i++) {
    lum[i] = 0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i];
  }
  // Background colour = the median of a strip around the picture's edge.
  final List<double> er = <double>[], eg = <double>[], eb = <double>[];
  const int strip = 4;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (x < strip || y < strip || x >= w - strip || y >= h - strip) {
        final int i = y * w + x;
        er.add(r[i]);
        eg.add(g[i]);
        eb.add(b[i]);
      }
    }
  }
  double median(List<double> v) {
    v.sort();
    return v[v.length ~/ 2];
  }

  final double br = median(er), bg = median(eg), bb = median(eb);
  final Uint8List mask = Uint8List(w * h);
  const double threshold = 38;
  for (int i = 0; i < w * h; i++) {
    final double dr = r[i] - br, dg = g[i] - bg, db = b[i] - bb;
    if (math.sqrt(dr * dr + dg * dg + db * db) > threshold) mask[i] = 1;
  }
  // The biggest connected area of "not background".
  final Int32List label = Int32List(w * h);
  int bestLabel = 0, bestSize = 0, next = 0;
  final Queue<int> q = Queue<int>();
  for (int start = 0; start < w * h; start++) {
    if (mask[start] == 0 || label[start] != 0) continue;
    next++;
    int size = 0;
    label[start] = next;
    q.add(start);
    while (q.isNotEmpty) {
      final int p = q.removeFirst();
      size++;
      final int x = p % w, y = p ~/ w;
      void push(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
        final int n = ny * w + nx;
        if (mask[n] == 1 && label[n] == 0) {
          label[n] = next;
          q.add(n);
        }
      }

      push(x + 1, y);
      push(x - 1, y);
      push(x, y + 1);
      push(x, y - 1);
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = next;
    }
  }
  final double share = bestSize / (w * h);
  if (bestLabel == 0 || share < 0.12 || share > 0.97) return null;
  // Extreme points of that area along the diagonals.
  double minSum = double.infinity, maxSum = -double.infinity, minDiff = double.infinity, maxDiff = -double.infinity;
  Offset tl = Offset.zero, br2 = Offset.zero, tr = Offset.zero, bl = Offset.zero;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (label[y * w + x] != bestLabel) continue;
      final double sum = (x + y).toDouble(), diff = (x - y).toDouble();
      if (sum < minSum) {
        minSum = sum;
        tl = Offset(x.toDouble(), y.toDouble());
      }
      if (sum > maxSum) {
        maxSum = sum;
        br2 = Offset(x.toDouble(), y.toDouble());
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        tr = Offset(x.toDouble(), y.toDouble());
      }
      if (diff < minDiff) {
        minDiff = diff;
        bl = Offset(x.toDouble(), y.toDouble());
      }
    }
  }
  final List<Offset> quad = <Offset>[tl, tr, br2, bl];
  if (!isUsableQuad(quad, minSide: 10)) return null;
  // The corners should enclose most of the area, or the shape is not a page.
  final double polyArea = _polygonArea(quad);
  if (polyArea < bestSize * 0.6) return null;
  final double sx = src.width / w, sy = src.height / h;
  return <Offset>[for (final Offset o in quad) Offset((o.dx + 0.5) * sx, (o.dy + 0.5) * sy)];
}

double _polygonArea(List<Offset> p) {
  double a = 0;
  for (int i = 0; i < p.length; i++) {
    final Offset c = p[i], n = p[(i + 1) % p.length];
    a += c.dx * n.dy - n.dx * c.dy;
  }
  return a.abs() / 2;
}
