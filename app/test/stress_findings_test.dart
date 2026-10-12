// test/stress_findings_test.dart
//
// Probes for suspected bugs found while reading the code. A test that FAILS
// here confirms the bug (the failing message says what was seen).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/filter_service.dart';

img.Image _colored() {
  final img.Image im = img.Image(width: 4, height: 4);
  img.fill(im, color: img.ColorRgb8(200, 100, 50));
  return im;
}

const String _pending = 'Confirmed bug, fix pending (see docs/OUTSTANDING.md)';

void main() {
  group('filter probes', () {
  test('filter: the source picture is not changed by applying a filter', () {
    for (final FilterType f in <FilterType>[
      FilterType.grayscale,
      FilterType.blackAndWhite,
      FilterType.colorEnhance,
      FilterType.shadowRemoval,
    ]) {
      final img.Image src = _colored();
      FilterService.applyToImage(src, f, intensity: 0.5);
      final p = src.getPixel(0, 0);
      expect((p.r.toInt(), p.g.toInt(), p.b.toInt()), (200, 100, 50),
          reason: '$f at 50% modified the caller\'s picture in place');
    }
  });

  test('filter: 50% grayscale lands between the original and full grayscale', () {
    final img.Image half = FilterService.applyToImage(_colored(), FilterType.grayscale, intensity: 0.5);
    final img.Image full = FilterService.applyToImage(_colored(), FilterType.grayscale, intensity: 1.0);
    final int rHalf = half.getPixel(0, 0).r.toInt();
    final int rFull = full.getPixel(0, 0).r.toInt();
    expect(rHalf, greaterThan(rFull + 10),
        reason: '50% grayscale red=$rHalf equals full grayscale red=$rFull, so the strength slider does nothing');
    expect(rHalf, lessThan(200));
  });

  test('filter: 0% strength leaves the picture unchanged', () {
    final img.Image out = FilterService.applyToImage(_colored(), FilterType.colorEnhance, intensity: 0.0);
    final p = out.getPixel(0, 0);
    expect((p.r.toInt(), p.g.toInt(), p.b.toInt()), (200, 100, 50));
  });
  }, skip: _pending);

  group('export drops ALL edits when one step fails', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('stress_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('resize to 0 returns the untouched original (erased area comes back)', () async {
      final img.Image page = img.Image(width: 40, height: 20);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));
      final File file = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
      final DateTime now = DateTime(2026, 1, 1);
      final ScanDocument doc = ScanDocument(
        id: 'd',
        title: 'T',
        pageCount: 1,
        pagePaths: <String>[file.path],
        createdAt: now,
        updatedAt: now,
        ocrText: '',
        thumbnailPath: file.path,
        pageTransforms: <int, PageTransform>{
          0: PageTransform(
            resizeWidth: 0,
            resizeHeight: 0,
            eraserStrokes: <Map<String, dynamic>>[
              <String, dynamic>{
                'points': <List<double>>[<double>[0, 0], <double>[0.5, 0.5]],
                'color': 0xFF000000,
                'width': 0.05,
                'rect': true,
              },
            ],
          ),
        },
      );
      final bytes = await ExportService().renderPageForOutput(doc, 0);
      final img.Image out = img.decodePng(bytes)!;
      expect(out.getPixel(3, 3).r.toInt() < 128, isTrue,
          reason: 'a failed resize made the export fall back to the unedited original; the erased (redacted) area is visible again');
    });
  }, skip: _pending);
}
