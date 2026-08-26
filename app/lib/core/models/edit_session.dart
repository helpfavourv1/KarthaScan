import 'dart:typed_data';
import 'package:image/image.dart' as img;

class EditLayer {
  EditLayer({
    required this.pngBytes, required this.label,
    required this.widthFraction, required this.aspect,
    this.pctX = 0.5, this.pctY = 0.5,
    this.rotationDegrees = 0, this.scale = 1.0, this.opacity = 1.0,
  });
  final Uint8List pngBytes;
  final String label;
  final double widthFraction;
  final double aspect;
  double pctX, pctY, rotationDegrees, scale, opacity;
}

Uint8List bakeSessionIsolate(Map<String, dynamic> args) {
  final original = img.decodeImage(args['original'] as Uint8List);
  if (original == null) return args['original'] as Uint8List;
  img.Image canvas = original;
  final layers = args['layers'] as List<dynamic>;
  for (final spec in layers) {
    final m = spec as Map<dynamic, dynamic>;
    var overlay = img.decodePng(m['bytes'] as Uint8List);
    if (overlay == null) continue;
    final widthFraction = (m['widthFraction'] as num).toDouble();
    final scale = (m['scale'] as num).toDouble();
    final opacity = (m['opacity'] as num).toDouble();
    final rotation = (m['rotation'] as num).toDouble();
    final pctX = (m['pctX'] as num).toDouble();
    final pctY = (m['pctY'] as num).toDouble();

    double tw = original.width * widthFraction * scale;
    if (tw < 8) tw = 8;
    final targetW = tw.round();
    final targetH = (targetW * (overlay.height / overlay.width)).round();
    overlay = img.copyResize(overlay, width: targetW, height: targetH);

    if (opacity < 1.0) {
      for (final p in overlay) { p.a = (p.a * opacity).round(); }
    }
    if (rotation != 0) overlay = img.copyRotate(overlay, angle: rotation);

    final dstX = (pctX * original.width).round() - (overlay.width ~/ 2);
    final dstY = (pctY * original.height).round() - (overlay.height ~/ 2);
    canvas = img.compositeImage(canvas, overlay, dstX: dstX, dstY: dstY);
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 95));
}
