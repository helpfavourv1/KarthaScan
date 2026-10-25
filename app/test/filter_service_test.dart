// test/filter_service_test.dart
//
// The page filters, checked on pixels: a synthetic document with a shadow across
// it, then what each filter does to the paper and to the writing, and that the
// exported file carries the same pixels as the filter itself.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/export_job.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/filter_service.dart';

/// A page: warm white paper (240,235,225), a shadow that darkens it from 100% at
/// the left edge to 50% at the right edge, and rows of dark writing (20% of the
/// paper's brightness) — so writing is always darker than any paper.
img.Image shadowedPage(int w, int h) {
  final img.Image im = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final double shade = 1.0 - 0.5 * x / (w - 1);
      final bool ink = _isInk(x / w, y / h);
      final double k = shade * (ink ? 0.2 : 1.0);
      im.setPixelRgba(x, y, (240 * k).round(), (235 * k).round(), (225 * k).round(), 255);
    }
  }
  return im;
}

/// Writing: 8 text rows between 15% and 85% of the page height, from 10% to 90%
/// across, each row 1.2% tall.
bool _isInk(double fx, double fy) {
  if (fx < 0.1 || fx > 0.9) return false;
  for (int r = 0; r < 8; r++) {
    final double top = 0.15 + r * 0.09;
    if (fy >= top && fy < top + 0.012) return true;
  }
  return false;
}

/// Sample points that are certainly paper / certainly writing.
List<(int, int)> paperPoints(int w, int h) => <(int, int)>[
      for (final double fx in <double>[0.05, 0.3, 0.5, 0.7, 0.95])
        for (final double fy in <double>[0.05, 0.11, 0.5, 0.95]) ((fx * w).round(), (fy * h).round()),
    ].where((p) => !_isInk(p.$1 / w, p.$2 / h)).toList();

List<(int, int)> inkPoints(int w, int h) => <(int, int)>[
      for (final double fx in <double>[0.2, 0.5, 0.8])
        for (int r = 0; r < 8; r++) ((fx * w).round(), ((0.15 + r * 0.09 + 0.006) * h).round()),
    ];

double meanAbsDiff(img.Image a, img.Image b) {
  double s = 0;
  int n = 0;
  for (int y = 0; y < a.height; y++) {
    for (int x = 0; x < a.width; x++) {
      final img.Pixel p = a.getPixel(x, y), q = b.getPixel(x, y);
      s += (p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs();
      n += 3;
    }
  }
  return s / n;
}

void main() {
  const int w = 600, h = 800;
  late img.Image page;
  setUpAll(() => page = shadowedPage(w, h));

  group('shadow removal', () {
    test('paper becomes even and white; writing stays dark', () {
      final img.Image out = FilterService.applyToImage(page, FilterType.shadowRemoval);
      final List<int> paper = <int>[for (final (int, int) p in paperPoints(w, h)) out.getPixel(p.$1, p.$2).g.toInt()];
      final int minP = paper.reduce((a, b) => a < b ? a : b);
      expect(minP, greaterThan(225), reason: 'paper still shows the shadow: $paper');
      // Before the filter the same points differ by more than 100 levels.
      final List<int> before = <int>[for (final (int, int) p in paperPoints(w, h)) page.getPixel(p.$1, p.$2).g.toInt()];
      expect(before.reduce((a, b) => a > b ? a : b) - before.reduce((a, b) => a < b ? a : b), greaterThan(80));
      for (final (int, int) p in inkPoints(w, h)) {
        expect(out.getPixel(p.$1, p.$2).g, lessThan(110), reason: 'writing lost at $p');
      }
    });

    test('a dark page edge is not blown up into noise', () {
      final img.Image im = img.Image(width: 200, height: 200);
      img.fill(im, color: img.ColorRgb8(10, 10, 10));
      final img.Image out = FilterService.applyToImage(im, FilterType.shadowRemoval);
      expect(out.getPixel(100, 100).g, lessThan(60));
    });
  });

  group('black and white', () {
    test('only pure black or pure white comes out, paper white and writing black', () {
      final img.Image out = FilterService.applyToImage(page, FilterType.blackAndWhite);
      for (int y = 0; y < h; y += 3) {
        for (int x = 0; x < w; x += 3) {
          final img.Pixel p = out.getPixel(x, y);
          expect(p.r == 0 || p.r == 255, isTrue, reason: 'grey at $x,$y: ${p.r}');
          expect(p.r == p.g && p.g == p.b, isTrue);
        }
      }
      for (final (int, int) p in paperPoints(w, h)) {
        expect(out.getPixel(p.$1, p.$2).r, 255, reason: 'paper not white at $p (shadow side)');
      }
      for (final (int, int) p in inkPoints(w, h)) {
        expect(out.getPixel(p.$1, p.$2).r, 0, reason: 'writing not black at $p');
      }
    });
  });

  group('grayscale', () {
    test('every pixel has equal channels and uses luminance weights', () {
      final img.Image src = img.Image(width: 3, height: 1);
      src.setPixelRgba(0, 0, 255, 0, 0, 255);
      src.setPixelRgba(1, 0, 0, 255, 0, 255);
      src.setPixelRgba(2, 0, 0, 0, 255, 255);
      final img.Image out = FilterService.applyToImage(src, FilterType.grayscale);
      expect(out.getPixel(0, 0).r, closeTo(76, 1));
      expect(out.getPixel(1, 0).r, closeTo(150, 1));
      expect(out.getPixel(2, 0).r, closeTo(29, 1));
      for (int x = 0; x < 3; x++) {
        final img.Pixel p = out.getPixel(x, 0);
        expect(p.r == p.g && p.g == p.b, isTrue);
      }
    });
  });

  group('colour enhance', () {
    test('a dull low-contrast page gets white paper and dark writing', () {
      final img.Image im = img.Image(width: 300, height: 300);
      img.fill(im, color: img.ColorRgb8(200, 200, 200));
      for (int y = 100; y < 160; y++) {
        for (int x = 40; x < 260; x++) {
          im.setPixelRgba(x, y, 100, 100, 100, 255);
        }
      }
      final img.Image out = FilterService.applyToImage(im, FilterType.colorEnhance);
      expect(out.getPixel(5, 5).g, greaterThan(245));
      expect(out.getPixel(150, 130).g, lessThan(20));
    });
  });

  group('all filters', () {
    test('never change the input and keep size and transparency', () {
      for (final FilterType f in FilterType.values) {
        final img.Image src = shadowedPage(120, 160)..setPixelRgba(0, 0, 10, 20, 30, 77);
        final Uint8List before = Uint8List.fromList(src.getBytes());
        final img.Image out = FilterService.applyToImage(src, f);
        expect(src.getBytes(), before, reason: '$f changed its input');
        expect((out.width, out.height), (120, 160));
        if (f != FilterType.none) expect(out.getPixel(0, 0).a, 77, reason: '$f lost transparency');
      }
    });

    test('strength: more strength means further from the original, none means identical', () {
      for (final FilterType f in <FilterType>[FilterType.grayscale, FilterType.blackAndWhite, FilterType.colorEnhance, FilterType.shadowRemoval]) {
        final img.Image src = shadowedPage(150, 200);
        double prev = -1;
        for (final double t in <double>[0.0, 0.25, 0.5, 1.0]) {
          final double d = meanAbsDiff(src, FilterService.applyToImage(src, f, intensity: t));
          if (t == 0.0) expect(d, 0, reason: '$f at 0 must equal the original');
          expect(d, greaterThanOrEqualTo(prev), reason: '$f not monotonic at $t');
          prev = d;
        }
        expect(prev, greaterThan(5), reason: '$f at full strength barely changes anything');
      }
    });

    test('a small preview and the full-size page agree', () {
      final img.Image big = shadowedPage(600, 800);
      final img.Image small = img.copyResize(big, width: 150, height: 200, interpolation: img.Interpolation.average);
      for (final FilterType f in <FilterType>[FilterType.shadowRemoval, FilterType.colorEnhance, FilterType.grayscale]) {
        final img.Image a = img.copyResize(FilterService.applyToImage(big, f), width: 150, height: 200, interpolation: img.Interpolation.average);
        final img.Image b = FilterService.applyToImage(small, f);
        expect(meanAbsDiff(a, b), lessThan(8), reason: '$f preview differs from export');
      }
    });
  });

  group('export carries the filter', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('filter_export');
      path = '${dir.path}/page.png';
      File(path).writeAsBytesSync(img.encodePng(page));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    ScanDocument docWith(PageTransform? t) {
      final DateTime now = DateTime(2026, 1, 1);
      return ScanDocument(
        id: 'd', title: 'T', pageCount: 1, pagePaths: <String>[path],
        createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: path,
        pageTransforms: t == null ? const <int, PageTransform>{} : <int, PageTransform>{0: t},
      );
    }

    test('exported pixels equal the filter output (page filter)', () async {
      for (final FilterType f in <FilterType>[FilterType.blackAndWhite, FilterType.shadowRemoval, FilterType.grayscale, FilterType.colorEnhance]) {
        final Uint8List bytes = await ExportService().renderPageForOutput(docWith(PageTransform(filter: f)), 0);
        final img.Image exported = img.decodePng(bytes)!;
        final img.Image direct = FilterService.applyToImage(page, f);
        expect(meanAbsDiff(exported, direct), 0, reason: '$f: export differs from the filter');
      }
    });

    test('exported pixels equal the filter output (export-screen filter)', () async {
      final Uint8List bytes = await ExportService().renderPageForOutput(docWith(null), 0, filter: FilterType.blackAndWhite);
      final img.Image exported = img.decodePng(bytes)!;
      expect(meanAbsDiff(exported, FilterService.applyToImage(page, FilterType.blackAndWhite)), 0);
    });

    test('a page filter at half strength exports half way', () async {
      final Uint8List bytes = await ExportService().renderPageForOutput(
        docWith(const PageTransform(filter: FilterType.blackAndWhite, filterIntensity: 0.5)), 0,
      );
      final img.Image exported = img.decodePng(bytes)!;
      expect(meanAbsDiff(exported, FilterService.applyToImage(page, FilterType.blackAndWhite, intensity: 0.5)), 0);
    });

    test('a real exported JPG and PDF of a filtered page decode with the filter in them', () async {
      final ScanDocument doc = docWith(const PageTransform(filter: FilterType.blackAndWhite));
      final Directory out = Directory('${dir.path}/o')..createSync();
      final List<String> jpg = await ExportService().export(document: doc, format: ExportFormat.jpg, outputDirectoryPath: out.path);
      final img.Image im = img.decodeJpg(File(jpg.first).readAsBytesSync())!;
      int extreme = 0, total = 0;
      for (int y = 0; y < im.height; y += 4) {
        for (int x = 0; x < im.width; x += 4) {
          final int v = im.getPixel(x, y).r.toInt();
          total++;
          if (v < 40 || v > 215) extreme++;
        }
      }
      expect(extreme / total, greaterThan(0.97), reason: 'B&W page exported with grey areas');
      final List<String> pdf = await ExportService().export(document: doc, format: ExportFormat.pdf, outputDirectoryPath: out.path);
      expect(File(pdf.first).lengthSync(), greaterThan(500));
    });
  });
}
