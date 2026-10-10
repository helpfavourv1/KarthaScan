// test/page_remap_test.dart
//
// Regression: reordering, deleting or inserting pages must carry each page's
// edits (transform, layers, OCR blocks) with it.
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/utils/page_remap.dart';

ScanDocument _doc(List<String> paths) {
  final DateTime now = DateTime(2026, 1, 1);
  return ScanDocument(
    id: 'd',
    title: 'T',
    pageCount: paths.length,
    pagePaths: paths,
    createdAt: now,
    updatedAt: now,
    ocrText: '',
    thumbnailPath: paths.first,
    pageTransforms: <int, PageTransform>{
      for (int i = 0; i < paths.length; i++) i: PageTransform(rotationTurns: i + 1),
    },
    stampLayers: <StampLayer>[
      StampLayer(
        id: 'stamp-on-1',
        pageIndex: 1,
        kind: 'text',
        placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5),
      ),
    ],
  );
}

void main() {
  test('matchPagesByPath follows files, new files are null', () {
    expect(matchPagesByPath(<String>['a', 'b', 'c'], <String>['c', 'a', 'x', 'b']),
        <int?>[2, 0, null, 1]);
  });

  test('a duplicated path only matches the original once', () {
    expect(matchPagesByPath(<String>['a', 'b'], <String>['a', 'a', 'b']),
        <int?>[0, null, 1]);
  });

  test('moving page 2 to the front moves its stamp and transform with it', () {
    final ScanDocument doc = _doc(<String>['a', 'b', 'c']);
    final List<String> next = <String>['b', 'a', 'c'];
    final ScanDocument out = remapPageEdits(doc, matchPagesByPath(doc.pagePaths, next));
    expect(out.stampLayers.single.pageIndex, 0);
    expect(out.pageTransforms[0]!.rotationTurns, 2); // page b's
    expect(out.pageTransforms[1]!.rotationTurns, 1); // page a's
    expect(out.pageTransforms[2]!.rotationTurns, 3);
  });

  test('deleting a page drops its edits and shifts the rest', () {
    final ScanDocument doc = _doc(<String>['a', 'b', 'c']);
    final ScanDocument out =
        remapPageEdits(doc, matchPagesByPath(doc.pagePaths, <String>['a', 'c']));
    expect(out.stampLayers, isEmpty); // the stamp was on deleted page b
    expect(out.pageTransforms.length, 2);
    expect(out.pageTransforms[1]!.rotationTurns, 3);
  });
}
