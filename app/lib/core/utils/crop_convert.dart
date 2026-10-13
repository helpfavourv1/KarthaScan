// lib/core/utils/crop_convert.dart
//
// Layers (signatures, stamps, watermarks, annotations) store their position
// as a fraction of the page as it is shown, which is the cropped area. When
// the crop changes, those fractions would point at a different spot on the
// photo. This converts them so every layer stays over the same part of the
// page, at the same physical size.
import 'dart:ui' show Rect;

import '../models/scan_document.dart';
import '../models/signature_placement.dart';

/// [from] and [to] are the old and new visible areas in photo pixels (the
/// whole photo when there is no crop).
SignaturePlacement convertPlacementForCrop(SignaturePlacement p, Rect from, Rect to) {
  if (from == to || from.width <= 0 || from.height <= 0 || to.width <= 0 || to.height <= 0) return p;
  final double photoX = from.left + p.pctX * from.width;
  final double photoY = from.top + p.pctY * from.height;
  return SignaturePlacement(
    pctX: (photoX - to.left) / to.width,
    pctY: (photoY - to.top) / to.height,
    rotationDegrees: p.rotationDegrees,
    // Layer width is a fraction of the page width, so keep the same width on
    // the photo by scaling with the ratio of the two crop widths.
    scale: p.scale * from.width / to.width,
  );
}

/// Returns [doc] with every layer on [pageIndex] converted from the [from]
/// area to the [to] area.
ScanDocument convertLayersForCrop(ScanDocument doc, int pageIndex, Rect from, Rect to) {
  if (from == to) return doc;
  SignaturePlacement conv(SignaturePlacement p) => convertPlacementForCrop(p, from, to);
  return doc.copyWith(
    signatureLayers: <SignatureLayer>[
      for (final SignatureLayer l in doc.signatureLayers)
        l.pageIndex == pageIndex ? l.copyWith(placement: conv(l.placement)) : l,
    ],
    annotateLayers: <AnnotateLayer>[
      for (final AnnotateLayer l in doc.annotateLayers)
        l.pageIndex == pageIndex ? l.copyWith(placement: conv(l.placement)) : l,
    ],
    watermarkLayers: <WatermarkLayer>[
      for (final WatermarkLayer l in doc.watermarkLayers)
        l.pageIndex == pageIndex ? l.copyWith(placement: conv(l.placement)) : l,
    ],
    stampLayers: <StampLayer>[
      for (final StampLayer l in doc.stampLayers)
        l.pageIndex == pageIndex ? l.copyWith(placement: conv(l.placement)) : l,
    ],
  );
}
