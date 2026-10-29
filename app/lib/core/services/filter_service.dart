import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'export_service.dart' show FilterType;

/// The one place every page filter is computed: the filter sheet's preview, the
/// editor page, the export screen preview, PDF/JPG/PNG export, print and share all
/// call [applyToImage], so what is seen is what is saved.
///
/// All filters read and write raw bytes (no per-pixel objects) and none of them
/// depends on the picture's size: the paper-background estimate is made on a
/// fixed-size grid, so a small preview and the full-size export agree.
abstract final class FilterService {
  /// Longest side of the grid the paper background is estimated on.
  static const int _gridSide = 160;

  /// [intensity] 1.0 is the full filter, 0 leaves the picture as it was, values
  /// above 1 push further (up to the 2.0 the slider allows). The input is never
  /// changed; a new picture is returned.
  static img.Image applyToImage(img.Image source, FilterType filter, {double intensity = 1.0}) {
    if (filter == FilterType.none || source.width == 0 || source.height == 0) return source;
    final img.Image base = (source.format == img.Format.uint8 && source.numChannels == 4)
        ? source
        : source.convert(format: img.Format.uint8, numChannels: 4);
    final Uint8List src = base.getBytes(order: img.ChannelOrder.rgba);
    final Uint8List out = Uint8List(src.length);
    final int w = base.width;
    final int h = base.height;
    switch (filter) {
      case FilterType.none:
        break;
      case FilterType.grayscale:
        _grayscale(src, out);
      case FilterType.blackAndWhite:
        _blackAndWhite(src, out, w, h);
      case FilterType.colorEnhance:
        _colorEnhance(src, out);
      case FilterType.shadowRemoval:
        _shadowRemoval(src, out, w, h);
      case FilterType.magicColor:
        // Even out the lighting, then stretch the levels and lift the colour.
        final Uint8List flat = Uint8List(src.length);
        _shadowRemoval(src, flat, w, h);
        _colorEnhance(flat, out);
    }
    final double t = intensity.clamp(0.0, 2.0).toDouble();
    if (t != 1.0) {
      // Blend with the original (or push past the filter when above 1).
      for (int i = 0; i < src.length; i += 4) {
        for (int c = 0; c < 3; c++) {
          final double v = src[i + c] + (out[i + c] - src[i + c]) * t;
          out[i + c] = v < 0 ? 0 : (v > 255 ? 255 : v.round());
        }
        out[i + 3] = src[i + 3];
      }
    }
    return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 4);
  }

  /// Brightness and contrast, each -1..1 (0 = unchanged). Brightness shifts every
  /// level; contrast spreads the levels around mid-grey. Colour and transparency
  /// are kept. Returns [source] itself when both are 0.
  static img.Image adjust(img.Image source, {double brightness = 0, double contrast = 0}) {
    if ((brightness == 0 && contrast == 0) || source.width == 0 || source.height == 0) return source;
    final double b = brightness.clamp(-1.0, 1.0).toDouble() * 128;
    final double k = 1 + contrast.clamp(-1.0, 1.0).toDouble() * 0.9;
    final Uint8List lut = Uint8List(256);
    for (int v = 0; v < 256; v++) {
      lut[v] = _c((v - 128) * k + 128 + b);
    }
    final img.Image base = (source.format == img.Format.uint8 && source.numChannels == 4)
        ? source
        : source.convert(format: img.Format.uint8, numChannels: 4);
    final Uint8List src = base.getBytes(order: img.ChannelOrder.rgba);
    final Uint8List out = Uint8List(src.length);
    for (int i = 0; i < src.length; i += 4) {
      out[i] = lut[src[i]];
      out[i + 1] = lut[src[i + 1]];
      out[i + 2] = lut[src[i + 2]];
      out[i + 3] = src[i + 3];
    }
    return img.Image.fromBytes(width: base.width, height: base.height, bytes: out.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  }

  static int _lum(int r, int g, int b) => ((r * 299 + g * 587 + b * 114) / 1000).round();

  static void _grayscale(Uint8List src, Uint8List out) {
    for (int i = 0; i < src.length; i += 4) {
      final int l = _lum(src[i], src[i + 1], src[i + 2]);
      out[i] = l;
      out[i + 1] = l;
      out[i + 2] = l;
      out[i + 3] = src[i + 3];
    }
  }

  /// Estimates the paper colour under the page, one grid per colour channel.
  /// Writing and ink are thin and dark, so a maximum filter removes them and
  /// leaves the (possibly shadowed) paper; a blur then smooths the result.
  static _Grid _paper(Uint8List src, int w, int h) {
    final double scale = _gridSide / math.max(w, h);
    final int gw = math.max(2, (w * scale).round());
    final int gh = math.max(2, (h * scale).round());
    final List<Uint8List> planes = <Uint8List>[Uint8List(gw * gh), Uint8List(gw * gh), Uint8List(gw * gh)];
    // Box-average the page down to the grid.
    for (int gy = 0; gy < gh; gy++) {
      final int y0 = (gy * h / gh).floor();
      final int y1 = math.max(y0 + 1, ((gy + 1) * h / gh).floor());
      for (int gx = 0; gx < gw; gx++) {
        final int x0 = (gx * w / gw).floor();
        final int x1 = math.max(x0 + 1, ((gx + 1) * w / gw).floor());
        // Sample at most 6x6 points inside the cell: fast and good enough.
        final int stepY = math.max(1, (y1 - y0) ~/ 6);
        final int stepX = math.max(1, (x1 - x0) ~/ 6);
        int r = 0, g = 0, b = 0, n = 0;
        for (int y = y0; y < y1; y += stepY) {
          int p = (y * w + x0) * 4;
          for (int x = x0; x < x1; x += stepX) {
            r += src[p];
            g += src[p + 1];
            b += src[p + 2];
            n++;
            p += 4 * stepX;
          }
        }
        final int gi = gy * gw + gx;
        planes[0][gi] = r ~/ n;
        planes[1][gi] = g ~/ n;
        planes[2][gi] = b ~/ n;
      }
    }
    final int rad = math.max(2, (_gridSide * 0.05).round());
    for (int c = 0; c < 3; c++) {
      planes[c] = _boxBlur(_maxFilter(planes[c], gw, gh, rad), gw, gh, rad);
    }
    return _Grid(gw, gh, planes);
  }

  static Uint8List _maxFilter(Uint8List a, int w, int h, int r) {
    final Uint8List tmp = Uint8List(a.length);
    final Uint8List out = Uint8List(a.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int m = 0;
        for (int k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          final int v = a[y * w + k];
          if (v > m) m = v;
        }
        tmp[y * w + x] = m;
      }
    }
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int m = 0;
        for (int k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          final int v = tmp[k * w + x];
          if (v > m) m = v;
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }

  static Uint8List _boxBlur(Uint8List a, int w, int h, int r) {
    final Uint8List tmp = Uint8List(a.length);
    final Uint8List out = Uint8List(a.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int s = 0, n = 0;
        for (int k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          s += a[y * w + k];
          n++;
        }
        tmp[y * w + x] = s ~/ n;
      }
    }
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int s = 0, n = 0;
        for (int k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          s += tmp[k * w + x];
          n++;
        }
        out[y * w + x] = s ~/ n;
      }
    }
    return out;
  }

  /// Walks every pixel with its paper colour (bilinear from the grid).
  static void _forEachWithPaper(
    Uint8List src,
    int w,
    int h,
    _Grid grid,
    void Function(int i, int pr, int pg, int pb) visit,
  ) {
    final int gw = grid.w;
    final int gh = grid.h;
    final List<int> x0s = List<int>.filled(w, 0);
    final List<double> fxs = List<double>.filled(w, 0);
    for (int x = 0; x < w; x++) {
      final double gx = ((x + 0.5) * gw / w - 0.5).clamp(0.0, gw - 1.0).toDouble();
      final int x0 = math.min(gw - 2, gx.floor());
      x0s[x] = x0;
      fxs[x] = gx - x0;
    }
    final Uint8List pr = grid.planes[0], pg = grid.planes[1], pb = grid.planes[2];
    for (int y = 0; y < h; y++) {
      final double gy = ((y + 0.5) * gh / h - 0.5).clamp(0.0, gh - 1.0).toDouble();
      final int y0 = math.min(gh - 2, gy.floor());
      final double fy = gy - y0;
      final int r0 = y0 * gw, r1 = (y0 + 1) * gw;
      for (int x = 0; x < w; x++) {
        final int x0 = x0s[x];
        final double fx = fxs[x];
        double s(Uint8List p) {
          final double top = p[r0 + x0] * (1 - fx) + p[r0 + x0 + 1] * fx;
          final double bot = p[r1 + x0] * (1 - fx) + p[r1 + x0 + 1] * fx;
          return top * (1 - fy) + bot * fy;
        }

        visit((y * w + x) * 4, s(pr).round(), s(pg).round(), s(pb).round());
      }
    }
  }

  /// Divides out the paper colour, so a shadow or a tinted lamp stops showing
  /// and the paper becomes white while writing keeps its darkness.
  static void _shadowRemoval(Uint8List src, Uint8List out, int w, int h) {
    final _Grid grid = _paper(src, w, h);
    _forEachWithPaper(src, w, h, grid, (int i, int pr, int pg, int pb) {
      // A very dark "paper" means no paper was found there; do not blow it up.
      final int br = math.max(pr, 70), bg = math.max(pg, 70), bb = math.max(pb, 70);
      // 1.04: paper just below white goes fully white, as a scanner would.
      final int r = (src[i] * 265 / br).round();
      final int g = (src[i + 1] * 265 / bg).round();
      final int b = (src[i + 2] * 265 / bb).round();
      out[i] = r > 255 ? 255 : r;
      out[i + 1] = g > 255 ? 255 : g;
      out[i + 2] = b > 255 ? 255 : b;
      out[i + 3] = src[i + 3];
    });
  }

  /// Pure black and white decided against the paper beside each pixel, so a page
  /// that is darker on one side still turns white where there is no writing.
  static void _blackAndWhite(Uint8List src, Uint8List out, int w, int h) {
    final _Grid grid = _paper(src, w, h);
    _forEachWithPaper(src, w, h, grid, (int i, int pr, int pg, int pb) {
      final int l = _lum(src[i], src[i + 1], src[i + 2]);
      final int paper = math.max(_lum(pr, pg, pb), 60);
      // Black when clearly darker than the paper around it.
      final int v = l * 100 < paper * 80 ? 0 : 255;
      out[i] = v;
      out[i + 1] = v;
      out[i + 2] = v;
      out[i + 3] = src[i + 3];
    });
  }

  /// Stretches the levels so the darkest ink is black and the paper is white,
  /// then lifts colour a little. Same stretch on all channels keeps the hues.
  static void _colorEnhance(Uint8List src, Uint8List out) {
    final List<int> hist = List<int>.filled(256, 0);
    for (int i = 0; i < src.length; i += 4) {
      hist[_lum(src[i], src[i + 1], src[i + 2])]++;
    }
    final int total = src.length ~/ 4;
    int low = 0, high = 255, acc = 0;
    for (int v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= total * 0.01) {
        low = v;
        break;
      }
    }
    acc = 0;
    for (int v = 255; v >= 0; v--) {
      acc += hist[v];
      if (acc >= total * 0.01) {
        high = v;
        break;
      }
    }
    // Never stretch a nearly flat picture into noise.
    if (high - low < 40) {
      low = math.max(0, math.min(low, high - 40));
      high = low + 40;
    }
    final double k = 255 / (high - low);
    for (int i = 0; i < src.length; i += 4) {
      final double r = (src[i] - low) * k;
      final double g = (src[i + 1] - low) * k;
      final double b = (src[i + 2] - low) * k;
      final double l = 0.299 * r + 0.587 * g + 0.114 * b;
      const double sat = 1.2;
      out[i] = _c(l + (r - l) * sat);
      out[i + 1] = _c(l + (g - l) * sat);
      out[i + 2] = _c(l + (b - l) * sat);
      out[i + 3] = src[i + 3];
    }
  }

  static int _c(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());
}

class _Grid {
  const _Grid(this.w, this.h, this.planes);
  final int w;
  final int h;
  final List<Uint8List> planes;
}
