// lib/core/utils/page_remap.dart
//
// Per-page edits (transforms, OCR blocks, signature/annotation/watermark/
// stamp layers) are keyed by page index. When pages are reordered, deleted
// or inserted, those indexes must follow the pages, not stay behind.
import '../models/ocr_block.dart';
import '../models/page_transform.dart';
import '../models/scan_document.dart';

/// For each page in [newPaths], the index it had in [oldPaths], or null when
/// the page is new. The same old page is only matched once, so a duplicate
/// (a new copy at a new path) never shares the original's edits.
List<int?> matchPagesByPath(List<String> oldPaths, List<String> newPaths) {
  final Map<String, List<int>> available = <String, List<int>>{};
  for (int i = 0; i < oldPaths.length; i++) {
    available.putIfAbsent(oldPaths[i], () => <int>[]).add(i);
  }
  return <int?>[
    for (final String path in newPaths)
      (available[path]?.isNotEmpty ?? false) ? available[path]!.removeAt(0) : null,
  ];
}

/// Returns [doc] with every per-page edit moved to follow its page.
/// [sourceIndices] maps each new page index to its old index (null = new).
ScanDocument remapPageEdits(ScanDocument doc, List<int?> sourceIndices) {
  final Map<int, List<int>> newIndexesFor = <int, List<int>>{};
  for (int j = 0; j < sourceIndices.length; j++) {
    final int? old = sourceIndices[j];
    if (old != null) newIndexesFor.putIfAbsent(old, () => <int>[]).add(j);
  }

  List<T> moveLayers<T>(List<T> layers, int Function(T) pageOf, T Function(T, int) withPage) {
    final List<T> out = <T>[];
    for (final T layer in layers) {
      for (final int j in newIndexesFor[pageOf(layer)] ?? const <int>[]) {
        out.add(withPage(layer, j));
      }
    }
    return out;
  }

  return doc.copyWith(
    pageTransforms: <int, PageTransform>{
      for (int j = 0; j < sourceIndices.length; j++)
        if (sourceIndices[j] != null && doc.pageTransforms[sourceIndices[j]] != null)
          j: doc.pageTransforms[sourceIndices[j]]!,
    },
    pageOcrBlocks: <int, List<OcrBlock>>{
      for (int j = 0; j < sourceIndices.length; j++)
        if (sourceIndices[j] != null && doc.pageOcrBlocks[sourceIndices[j]] != null)
          j: doc.pageOcrBlocks[sourceIndices[j]]!,
    },
    signatureLayers: moveLayers<SignatureLayer>(
        doc.signatureLayers, (l) => l.pageIndex, (l, j) => l.copyWith(pageIndex: j)),
    annotateLayers: moveLayers<AnnotateLayer>(
        doc.annotateLayers, (l) => l.pageIndex, (l, j) => l.copyWith(pageIndex: j)),
    watermarkLayers: moveLayers<WatermarkLayer>(
        doc.watermarkLayers, (l) => l.pageIndex, (l, j) => l.copyWith(pageIndex: j)),
    stampLayers: moveLayers<StampLayer>(
        doc.stampLayers, (l) => l.pageIndex, (l, j) => l.copyWith(pageIndex: j)),
  );
}
