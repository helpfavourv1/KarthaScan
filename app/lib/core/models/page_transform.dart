import 'package:flutter/foundation.dart' show immutable;
import 'dart:ui' show Rect;
import '../services/export_service.dart' show FilterType;

@immutable
class PageTransform {
  const PageTransform({
    this.cropRect,
    this.rotationTurns = 0,
    this.filter = FilterType.none,
    this.resizeWidth,
    this.resizeHeight,
    this.eraserStrokes = const [],
  });

  final Rect? cropRect;
  final int rotationTurns;
  final FilterType filter;
  final int? resizeWidth;
  final int? resizeHeight;
  final List<Map<String, dynamic>> eraserStrokes;

  bool get isEmpty =>
      cropRect == null &&
      rotationTurns == 0 &&
      filter == FilterType.none &&
      resizeWidth == null &&
      resizeHeight == null &&
      eraserStrokes.isEmpty;

  PageTransform copyWith({
    Rect? cropRect,
    int? rotationTurns,
    FilterType? filter,
    int? resizeWidth,
    int? resizeHeight,
    List<Map<String, dynamic>>? eraserStrokes,
    bool clearCrop = false,
    bool clearResize = false,
    bool clearEraser = false,
  }) {
    return PageTransform(
      cropRect: clearCrop ? null : (cropRect ?? this.cropRect),
      rotationTurns: rotationTurns ?? this.rotationTurns,
      filter: filter ?? this.filter,
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
      'rotationTurns': rotationTurns,
      'filter': filter.index,
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
    return PageTransform(
      cropRect: crop,
      rotationTurns: (json['rotationTurns'] as num?)?.toInt() ?? 0,
      filter: FilterType.values[(json['filter'] as num?)?.toInt() ?? 0],
      resizeWidth: (json['resizeWidth'] as num?)?.toInt(),
      resizeHeight: (json['resizeHeight'] as num?)?.toInt(),
      eraserStrokes: (json['eraserStrokes'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const [],
    );
  }
}
