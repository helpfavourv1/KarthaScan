// test/page_ghost_test.dart
//
// The layers picture shown faintly in Crop / Rotate / Eraser: transparent, the
// shape of the cropped page, with the signature where the page has it.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/widgets/page_layers_ghost.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ghost'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List inkPng() {
    final img.Image ink = img.Image(width: 120, height: 60, numChannels: 4);
    img.fill(ink, color: img.ColorRgba8(0, 0, 0, 255));
    return img.encodePng(ink);
  }

  ScanDocument doc({Map<int, PageTransform> transforms = const <int, PageTransform>{}, bool withInk = true}) {
    final img.Image page = img.Image(width: 600, height: 800);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final File f = File('${dir.path}/p.png')..writeAsBytesSync(img.encodePng(page));
    final DateTime now = DateTime(2026, 1, 1);
    return ScanDocument(
      id: 'd', title: 'T', pageCount: 1, pagePaths: <String>[f.path],
      createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
      pageTransforms: transforms,
      signatureInks: withInk ? <SignatureInk>[SignatureInk(id: 'ink', bytes: inkPng(), label: 'Me')] : const <SignatureInk>[],
      signatureLayers: withInk ? const <SignatureLayer>[SignatureLayer(pageIndex: 0, inkId: 'ink', placement: SignaturePlacement(pctX: 0.5, pctY: 0.5))] : const <SignatureLayer>[],
    );
  }

  test('page without layers gives no ghost', () async {
    final (Uint8List? png, Rect? box) = await ExportService().renderGhost(doc(withInk: false), 0);
    expect(png, isNull);
    expect(box, isNull);
  });

  test('uncropped page: transparent picture in the photo shape, signature in the middle', () async {
    final (Uint8List? png, Rect? box) = await ExportService().renderGhost(doc(), 0);
    expect(box, isNull);
    final img.Image g = img.decodePng(png!)!;
    expect(g.width, 900);
    expect(g.height, 1200);
    expect(g.getPixel(2, 2).a, 0, reason: 'corners stay transparent');
    int opaque = 0;
    for (final img.Pixel px in g) {
      if (px.a > 0) opaque++;
    }
    expect(opaque, greaterThan(500), reason: 'the signature is drawn');
  });

  test('cropped page: picture takes the crop shape and the box sits on the photo', () async {
    final ScanDocument d = doc(transforms: <int, PageTransform>{0: const PageTransform(cropRect: Rect.fromLTWH(100, 200, 300, 400))});
    final (Uint8List? png, Rect? box) = await ExportService().renderGhost(d, 0);
    final img.Image g = img.decodePng(png!)!;
    expect(g.width / g.height, closeTo(300 / 400, 0.01));
    expect(box!.left, closeTo(100 / 600, 1e-6));
    expect(box.top, closeTo(200 / 800, 1e-6));
    expect(box.width, closeTo(0.5, 1e-6));
    expect(box.height, closeTo(0.5, 1e-6));
  });

  testWidgets('ghost widget sits inside its box and ignores touches', (WidgetTester tester) async {
    final Uint8List png = (await ExportService().renderGhost(doc(), 0)).$1!;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 400,
          child: Stack(children: <Widget>[PageLayersGhost(png: png, box: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5))]),
        ),
      ),
    ));
    final Rect r = tester.getRect(find.byKey(const ValueKey<String>('pageLayersGhost')));
    expect(r.width, closeTo(100, 0.5));
    expect(r.height, closeTo(200, 0.5));
    final Rect host = tester.getRect(find.byType(SizedBox).first);
    expect(r.left - host.left, closeTo(50, 0.5));
    expect(r.top - host.top, closeTo(100, 0.5));
  });
}
