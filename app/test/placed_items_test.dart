@Timeout(Duration(seconds: 60))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/widgets/document_canvas.dart' show visibleCentreFraction;
import 'package:katharscan/widgets/ink_board.dart' show PlacedItemGesture;

void main() {
  test('rotation snaps to upright and quarter turns only when close', () {
    expect(PlacedItemGesture.snapDegrees(2), 0);
    expect(PlacedItemGesture.snapDegrees(88), 90);
    expect(PlacedItemGesture.snapDegrees(-178), -180);
    expect(PlacedItemGesture.snapDegrees(20), 20);
    expect(PlacedItemGesture.snapDegrees(370), 10);
  });

  test('visible centre follows the zoom, stays inside the page', () {
    const Size view = Size(400, 800), page = Size(400, 600);
    final Offset whole = visibleCentreFraction(Matrix4.identity(), view, page);
    expect(whole.dx, closeTo(0.5, 1e-9));
    expect(whole.dy, closeTo(0.5, 1e-9));
    // Zoom 2x anchored at the top-left of the viewport: the view middle is the 1/4,1/4 of the viewport.
    final Matrix4 zoomed = Matrix4.identity()..scaleByDouble(2.0, 2.0, 2.0, 1.0);
    final Offset c = visibleCentreFraction(zoomed, view, page);
    expect(c.dx, closeTo(0.25, 1e-9));
    expect(c.dy, closeTo((800 / 4 - 100) / 600, 1e-9));
    // Far panned: clamped to stay on the page.
    final Matrix4 far = Matrix4.identity()..translateByDouble(-5000.0, -5000.0, 0.0, 1.0)..scaleByDouble(2.0, 2.0, 2.0, 1.0);
    final Offset f = visibleCentreFraction(far, view, page);
    expect(f.dx, lessThanOrEqualTo(0.9));
  });

  testWidgets('one finger drags from touch-down; two fingers pinch and twist', (tester) async {
    SignaturePlacement p = const SignaturePlacement(pctX: 0.5, pctY: 0.5);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: PlacedItemGesture(
                placement: p,
                iw: 400,
                ih: 400,
                onChanged: (np) => set(() => p = np),
                child: Container(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    ));
    final Offset c = tester.getCenter(find.byType(PlacedItemGesture));
    final TestGesture g = await tester.startGesture(c);
    await g.moveTo(c + const Offset(2, 0));
    await g.moveTo(c + const Offset(40, 0));
    await g.up();
    await tester.pump();
    expect(p.pctX, closeTo(0.6, 0.011), reason: 'the whole 40 px counts, none is lost to touch slop');

    final TestGesture a = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
    final TestGesture b = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    await a.moveTo(c - const Offset(80, 0));
    await b.moveTo(c + const Offset(80, 0));
    await tester.pump();
    expect(p.scale, greaterThan(1.5), reason: 'fingers moved twice as far apart');
    await a.up();
    await b.up();
  });
}
