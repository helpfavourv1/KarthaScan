import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/utils/crop_convert.dart';

void main() {
  const Rect whole = Rect.fromLTWH(0, 0, 1000, 2000);
  const Rect crop = Rect.fromLTWH(200, 400, 500, 1000);

  test('a layer stays over the same spot on the photo after a crop', () {
    // centre of the page, on the whole photo = photo point (500, 1000)
    const SignaturePlacement before = SignaturePlacement(pctX: 0.5, pctY: 0.5, scale: 1.0);
    final SignaturePlacement after = convertPlacementForCrop(before, whole, crop);
    // photo (500,1000) inside crop (200..700, 400..1400) = (0.6, 0.6)
    expect(after.pctX, closeTo(0.6, 1e-9));
    expect(after.pctY, closeTo(0.6, 1e-9));
    // crop is half as wide, so the layer must be twice the scale to keep its size
    expect(after.scale, closeTo(2.0, 1e-9));
  });

  test('crop then revert returns the layer to exactly where it was', () {
    const SignaturePlacement start = SignaturePlacement(pctX: 0.3, pctY: 0.8, rotationDegrees: 20, scale: 1.4);
    final SignaturePlacement cropped = convertPlacementForCrop(start, whole, crop);
    final SignaturePlacement back = convertPlacementForCrop(cropped, crop, whole);
    expect(back.pctX, closeTo(start.pctX, 1e-9));
    expect(back.pctY, closeTo(start.pctY, 1e-9));
    expect(back.scale, closeTo(start.scale, 1e-9));
    expect(back.rotationDegrees, 20);
  });

  test('re-cropping from one crop to another keeps the spot', () {
    const Rect second = Rect.fromLTWH(300, 500, 300, 600);
    const SignaturePlacement start = SignaturePlacement(pctX: 0.5, pctY: 0.5);
    final SignaturePlacement a = convertPlacementForCrop(start, crop, second);
    // photo point = (200+250, 400+500) = (450, 900); in second = (150/300, 400/600)
    expect(a.pctX, closeTo(0.5, 1e-9));
    expect(a.pctY, closeTo(400 / 600, 1e-9));
  });

  test('only layers on the changed page are converted', () {
    final DateTime now = DateTime(2026, 1, 1);
    const SignaturePlacement p0 = SignaturePlacement(pctX: 0.5, pctY: 0.5);
    final ScanDocument doc = ScanDocument(
      id: 'd', title: 't', pageCount: 2, pagePaths: const <String>['a', 'b'],
      createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: 'a',
      watermarkLayers: const <WatermarkLayer>[
        WatermarkLayer(pageIndex: 0, text: 'X', placement: p0),
        WatermarkLayer(pageIndex: 1, text: 'X', placement: p0),
      ],
      stampLayers: const <StampLayer>[
        StampLayer(id: 's', pageIndex: 0, kind: 'text', placement: p0),
      ],
    );
    final ScanDocument out = convertLayersForCrop(doc, 0, whole, crop);
    expect(out.watermarkLayers[0].placement.pctX, closeTo(0.6, 1e-9));
    expect(out.watermarkLayers[1].placement, p0);
    expect(out.stampLayers[0].placement.pctX, closeTo(0.6, 1e-9));
  });
}
