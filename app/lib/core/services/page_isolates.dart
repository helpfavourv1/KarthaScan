// lib/core/services/page_isolates.dart
//
// Top-level isolate entry points for compute(). Lifted verbatim from
// scan_detail_screen.dart so every host shares one implementation.
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import 'export_service.dart' show FilterType;
import 'filter_service.dart';

Uint8List rotateIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final turns = args['turns'] as int;
  final rotated = img.copyRotate(original, angle: turns * 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
}

Uint8List resizeIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final width = args['width'] as int;
  final height = args['height'] as int;
  final resized = img.copyResize(original, width: width, height: height);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 95));
}

Uint8List filterBakeIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final filtered = FilterService.applyToImage(original, FilterType.values[args['filter'] as int]);
  return Uint8List.fromList(img.encodeJpg(filtered, quality: 95));
}

Uint8List cropIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final rect = args['rect'] as Rect;
  final x = rect.left.toInt().clamp(0, original.width);
  final y = rect.top.toInt().clamp(0, original.height);
  final w = rect.width.toInt().clamp(0, original.width - x);
  final h = rect.height.toInt().clamp(0, original.height - y);
  if (w <= 0 || h <= 0) return args['original'] as Uint8List;
  final cropped = img.copyCrop(original, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}

Uint8List eraseIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  final strokes = args['strokes'] as List<dynamic>;
  for (final s in strokes) {
    final m = s as Map<dynamic, dynamic>;
    final pts = (m['points'] as List<dynamic>)
        .map((e) => (e as List<dynamic>).map((v) => (v as num).toDouble()).toList())
        .toList();
    final colorInt = m['color'] as int;
    final color = img.ColorRgba8((colorInt >> 16) & 0xFF, (colorInt >> 8) & 0xFF, colorInt & 0xFF, (colorInt >> 24) & 0xFF);
    final wf = (m['width'] as num).toDouble();
    final thickness = (wf * original.width).clamp(1.0, original.width / 2).round();
    for (int i = 0; i < pts.length - 1; i++) {
      final x1 = (pts[i][0] * original.width).round();
      final y1 = (pts[i][1] * original.height).round();
      final x2 = (pts[i + 1][0] * original.width).round();
      final y2 = (pts[i + 1][1] * original.height).round();
      img.drawLine(original, x1: x1, y1: y1, x2: x2, y2: y2, color: color, thickness: thickness, antialias: true);
    }
  }
  return Uint8List.fromList(img.encodeJpg(original, quality: 95));
}
