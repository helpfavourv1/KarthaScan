import 'package:flutter/foundation.dart' show immutable;
import 'dart:ui' show Offset, Rect, Size;
import '../utils/perspective.dart';
import '../services/export_service.dart' show FilterType;

@immutable
class PageTransform {
  const PageTransform({
    this.cropRect,
    this.rotationTurns = 0,
    this.filter = FilterType.none,
    this.filterIntensity = 1.0,
    this.resizeWidth,
    this.resizeHeight,
    this.eraserStrokes = const [],
    this.cropQuad,
    this.cropAspect,
    this.straightenDegrees = 0,
    this.brightness = 0,
    this.contrast = 0,
  });

  /// The visible area in photo pixels. With a [cropQuad] this is the upright box
  /// around it (used to keep layers over the same part of the page).
  final Rect? cropRect;

  /// Four corners in photo pixels (top-left, top-right, bottom-right, bottom-left)
  /// of a page that is straightened when shown or exported; null for a plain crop.
  final List<Offset>? cropQuad;

  /// Width / height the straightened page is forced to (A4, ID card...), or null.
  final double? cropAspect;

  /// The size of the page after cropping (straightened if needed), or null when
  /// there is no crop.
  Size? get croppedSize {
    final List<Offset>? quad = cropQuad;
    if (quad != null && quad.length == 4) return quadOutputSize(quad, aspect: cropAspect);
    return cropRect?.size;
  }
  /// Fine tilt correction in degrees (clockwise, -45..45), done before the
  /// layers are placed; the page keeps its size and the edges are trimmed.
  final double straightenDegrees;
  final int rotationTurns;
  final FilterType filter;
  final double filterIntensity;

  /// Levels adjustments, each -1..1, applied after the filter.
  final double brightness;
  final double contrast;
  final int? resizeWidth;
  final int? resizeHeight;
  final List<Map<String, dynamic>> eraserStrokes;

  bool get isEmpty =>
      cropRect == null &&
      rotationTurns == 0 &&
      straightenDegrees == 0 &&
      brightness == 0 &&
      contrast == 0 &&
      filter == FilterType.none &&
      resizeWidth == null &&
      resizeHeight == null &&
      eraserStrokes.isEmpty;

  PageTransform copyWith({
    Rect? cropRect,
    int? rotationTurns,
    FilterType? filter,
    double? filterIntensity,
    int? resizeWidth,
    int? resizeHeight,
    List<Map<String, dynamic>>? eraserStrokes,
    List<Offset>? cropQuad,
    double? cropAspect,
    double? straightenDegrees,
    double? brightness,
    double? contrast,
    bool clearCrop = false,
    bool clearCropQuad = false,
    bool clearResize = false,
    bool clearEraser = false,
  }) {
    return PageTransform(
      cropRect: clearCrop ? null : (cropRect ?? this.cropRect),
      cropQuad: (clearCrop || clearCropQuad) ? null : (cropQuad ?? this.cropQuad),
      cropAspect: (clearCrop || clearCropQuad) ? null : (cropAspect ?? this.cropAspect),
      straightenDegrees: straightenDegrees ?? this.straightenDegrees,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      rotationTurns: rotationTurns ?? this.rotationTurns,
      filter: filter ?? this.filter,
      filterIntensity: filterIntensity ?? this.filterIntensity,
      resizeWidth: clearResize ? null : (resizeWidth ?? this.resizeWidth),
      resizeHeight: clearResize ? null : (resizeHeight ?? this.resizeHeight),
      eraserStrokes: clearEraser ? const [] : (eraserStrokes ?? this.eraserStrokes),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cropRect != null) 'cropRect': {
        'left': cropRect!.left,
        'top': cropRect!.top,
        'width': cropRect!.width,
        'height': cropRect!.height,
      },
      if (cropQuad != null) 'cropQuad': <double>[for (final Offset o in cropQuad!) ...<double>[o.dx, o.dy]],
      if (cropAspect != null) 'cropAspect': cropAspect,
      if (straightenDegrees != 0) 'straightenDegrees': straightenDegrees,
      if (brightness != 0) 'brightness': brightness,
      if (contrast != 0) 'contrast': contrast,
      'rotationTurns': rotationTurns,
      'filter': filter.index,
      if (filterIntensity != 1.0) 'filterIntensity': filterIntensity,
      if (resizeWidth != null) 'resizeWidth': resizeWidth,
      if (resizeHeight != null) 'resizeHeight': resizeHeight,
      'eraserStrokes': eraserStrokes,
    };
  }

  factory PageTransform.fromJson(Map<String, dynamic> json) {
    Rect? crop;
    if (json['cropRect'] != null) {
      final r = json['cropRect'] as Map<String, dynamic>;
      crop = Rect.fromLTWH(
        (r['left'] as num).toDouble(),
        (r['top'] as num).toDouble(),
        (r['width'] as num).toDouble(),
        (r['height'] as num).toDouble(),
      );
    }
    List<Offset>? quad;
    final List<dynamic>? rawQuad = json['cropQuad'] as List<dynamic>?;
    if (rawQuad != null && rawQuad.length == 8) {
      final List<double> v = <double>[for (final dynamic n in rawQuad) (n as num).toDouble()];
      quad = <Offset>[for (int i = 0; i < 8; i += 2) Offset(v[i], v[i + 1])];
      if (!isUsableQuad(quad, minSide: 1)) quad = null;
    }
    return PageTransform(
      cropRect: crop,
      cropQuad: quad,
      cropAspect: quad == null ? null : (json['cropAspect'] as num?)?.toDouble(),
      straightenDegrees: ((json['straightenDegrees'] as num?)?.toDouble() ?? 0).clamp(-45.0, 45.0).toDouble(),
      brightness: ((json['brightness'] as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0).toDouble(),
      contrast: ((json['contrast'] as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0).toDouble(),
      rotationTurns: (json['rotationTurns'] as num?)?.toInt() ?? 0,
      filter: () {
        final int index = (json['filter'] as num?)?.toInt() ?? 0;
        return index >= 0 && index < FilterType.values.length
            ? FilterType.values[index]
            : FilterType.none;
      }(),
      filterIntensity: ((json['filterIntensity'] as num?)?.toDouble() ?? 1.0).clamp(0.2, 2.0).toDouble(),
      resizeWidth: (json['resizeWidth'] as num?)?.toInt(),
      resizeHeight: (json['resizeHeight'] as num?)?.toInt(),
      eraserStrokes: (json['eraserStrokes'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const [],
    );
  }
}
