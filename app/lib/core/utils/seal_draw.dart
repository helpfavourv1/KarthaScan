import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/scan_document.dart';

/// Draws a custom seal at size [s] (square canvas).
/// [centerImage] is a pre-decoded ui.Image for the center logo (optional).
/// Shared by the tray preview painter and the export renderer.
void drawSeal(ui.Canvas canvas, double s, StampLayer layer, {ui.Image? centerImage}) {
  final col = ui.Color(layer.color).withValues(alpha: layer.opacity);

  if (layer.sealShape == 'rectangle') {
    _drawRectangleSeal(canvas, s, layer, col);
    return;
  }

  // === OVAL SEAL (landscape, wider than tall) ===
  final ovalRect = ui.Rect.fromCenter(
    center: ui.Offset(s / 2, s / 2),
    width: s * 0.94,
    height: s * 0.72,
  );

  // Outer ring (thick)
  canvas.drawOval(
    ovalRect,
    ui.Paint()..color = col..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.035,
  );
  // Inner ring (thin)
  canvas.drawOval(
    ovalRect.deflate(s * 0.09),
    ui.Paint()..color = col..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.010,
  );

  // Arc texts
  final arcFont = layer.fontSize * s / 240;
  final rx = ovalRect.width * 0.42;
  final ry = ovalRect.height * 0.42;
  _drawArcTextOval(canvas, ui.Offset(s / 2, s / 2), rx, ry, layer.text, col, arcFont * 0.50, true);
  if (layer.sealSubtext.isNotEmpty) {
    _drawArcTextOval(canvas, ui.Offset(s / 2, s / 2), rx, ry, layer.sealSubtext, col, arcFont * 0.40, false);
  }

  // Center element
  if (layer.sealCenter == 'star') {
    _drawStar(canvas, ui.Offset(s / 2, s / 2), s * 0.13, col);
  } else if (layer.sealCenter == 'image' && centerImage != null) {
    _drawCenterImage(canvas, ui.Offset(s / 2, s / 2), s * 0.18, centerImage);
  } else if (layer.sealCenter.isNotEmpty && layer.sealCenter != 'image' && layer.sealCenter != 'star') {
    _drawLabel(canvas, ui.Offset(s / 2, s / 2), layer.sealCenter, col, s * 0.09);
  }
}

void _drawRectangleSeal(ui.Canvas canvas, double s, StampLayer layer, ui.Color col) {
  // Outer border (thick)
  final outerRect = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(s * 0.03, s * 0.22, s * 0.94, s * 0.56),
    ui.Radius.circular(s * 0.04),
  );
  canvas.drawRRect(
    outerRect,
    ui.Paint()..color = col..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.035,
  );
  // Inner border (thin)
  final innerRect = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(s * 0.09, s * 0.28, s * 0.82, s * 0.44),
    ui.Radius.circular(s * 0.02),
  );
  canvas.drawRRect(
    innerRect,
    ui.Paint()..color = col..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.010,
  );
  // Main text
  _drawLabel(canvas, ui.Offset(s / 2, s * 0.46), layer.text, col, s * 0.14);
  // Subtext
  if (layer.sealSubtext.isNotEmpty) {
    _drawLabel(canvas, ui.Offset(s / 2, s * 0.62), layer.sealSubtext, col, s * 0.07);
  }
}

void _drawLabel(ui.Canvas canvas, ui.Offset at, String text, ui.Color col, double fs) {
  if (text.isEmpty || fs <= 0) return;
  final par = (ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: ui.TextAlign.center,
    fontSize: fs,
    fontWeight: ui.FontWeight.w700,
  ))
    ..pushStyle(ui.TextStyle(color: col))
    ..addText(text))
      .build()
    ..layout(const ui.ParagraphConstraints(width: 10000));
  canvas.drawParagraph(par, ui.Offset(at.dx - par.longestLine / 2, at.dy - par.height / 2));
}

void _drawArcTextOval(ui.Canvas canvas, ui.Offset center, double rx, double ry, String text, ui.Color col, double fs, bool top) {
  if (text.isEmpty || fs <= 2) return;
  final chars = text.split('');
  final pars = <ui.Paragraph>[];
  double total = 0;
  for (final ch in chars) {
    final par = (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fs, fontWeight: ui.FontWeight.w700))
      ..pushStyle(ui.TextStyle(color: col))
      ..addText(ch))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 10000));
    pars.add(par);
    total += par.longestLine;
  }
  final spacing = fs * 0.2;
  final avgR = (rx + ry) / 2;
  final totalAngle = (total + spacing * (chars.length - 1)) / avgR;
  double angle = top ? (-math.pi / 2 - totalAngle / 2) : (math.pi / 2 + totalAngle / 2);
  for (int i = 0; i < chars.length; i++) {
    final half = (pars[i].longestLine / 2) / avgR;
    if (top) {
      angle += half;
      final x = center.dx + rx * math.cos(angle);
      final y = center.dy + ry * math.sin(angle);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle + math.pi / 2);
      canvas.drawParagraph(pars[i], ui.Offset(-pars[i].longestLine / 2, -pars[i].height / 2));
      canvas.restore();
      angle += half + spacing / avgR;
    } else {
      angle -= half;
      final x = center.dx + rx * math.cos(angle);
      final y = center.dy + ry * math.sin(angle);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle - math.pi / 2);
      canvas.drawParagraph(pars[i], ui.Offset(-pars[i].longestLine / 2, -pars[i].height / 2));
      canvas.restore();
      angle -= half + spacing / avgR;
    }
  }
}

void _drawStar(ui.Canvas canvas, ui.Offset center, double r, ui.Color col) {
  final path = ui.Path();
  for (int i = 0; i < 5; i++) {
    final outerA = -math.pi / 2 + i * 2 * math.pi / 5;
    final innerA = outerA + math.pi / 5;
    final o = ui.Offset(center.dx + r * math.cos(outerA), center.dy + r * math.sin(outerA));
    final inn = ui.Offset(center.dx + r * 0.45 * math.cos(innerA), center.dy + r * 0.45 * math.sin(innerA));
    if (i == 0) {
      path.moveTo(o.dx, o.dy);
    } else {
      path.lineTo(o.dx, o.dy);
    }
    path.lineTo(inn.dx, inn.dy);
  }
  path.close();
  canvas.drawPath(path, ui.Paint()..color = col..style = ui.PaintingStyle.fill);
}

/// Draws a pre-decoded ui.Image clipped to a circle at the center.
void _drawCenterImage(ui.Canvas canvas, ui.Offset center, double radius, ui.Image image) {
  canvas.save();
  final clipPath = ui.Path()..addOval(ui.Rect.fromCircle(center: center, radius: radius));
  canvas.clipPath(clipPath);
  final src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final dst = ui.Rect.fromCircle(center: center, radius: radius);
  canvas.drawImageRect(image, src, dst, ui.Paint()..filterQuality = ui.FilterQuality.high);
  canvas.restore();
  // Draw a thin ring around the image
  canvas.drawCircle(
    center,
    radius,
    ui.Paint()..style = ui.PaintingStyle.stroke..strokeWidth = radius * 0.06..color = const ui.Color(0xFF000000).withValues(alpha: 0.3),
  );
}
