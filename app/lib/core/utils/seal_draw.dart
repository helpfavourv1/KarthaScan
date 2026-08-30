import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/scan_document.dart';

/// Draws a custom seal at size [s] (square). Shared by the tray preview
/// painter and the export renderer — guarantees preview == export parity.
void drawSeal(ui.Canvas canvas, double s, StampLayer layer) {
  final col = ui.Color(layer.color).withValues(alpha: layer.opacity);
  if (layer.sealShape == 'rectangle') {
    final border = ui.Paint()
      ..color = col
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = s * 0.03;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(s * 0.02, s * 0.2, s * 0.96, s * 0.6),
        ui.Radius.circular(s * 0.05),
      ),
      border,
    );
    _drawLabel(canvas, ui.Offset(s / 2, s * 0.44), layer.text, col, s * 0.15);
    if (layer.sealSubtext.isNotEmpty) {
      _drawLabel(canvas, ui.Offset(s / 2, s * 0.64), layer.sealSubtext, col, s * 0.075);
    }
    return;
  }
  // Round seal: outer ring + inner ring + arc texts + center
  canvas.drawCircle(
    ui.Offset(s / 2, s / 2),
    s * 0.47,
    ui.Paint()..color = col..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.03,
  );
  canvas.drawCircle(
    ui.Offset(s / 2, s / 2),
    s * 0.36,
    ui.Paint()..color = col..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.008,
  );
  final arcFont = layer.fontSize * s / 240;
  _drawArcText(canvas, ui.Offset(s / 2, s / 2), s * 0.41, layer.text, col, arcFont * 0.55, true);
  if (layer.sealSubtext.isNotEmpty) {
    _drawArcText(canvas, ui.Offset(s / 2, s / 2), s * 0.41, layer.sealSubtext, col, arcFont * 0.45, false);
  }
  if (layer.sealCenter == 'star') {
    _drawStar(canvas, ui.Offset(s / 2, s / 2), s * 0.12, col);
  } else if (layer.sealCenter.isNotEmpty) {
    _drawLabel(canvas, ui.Offset(s / 2, s / 2), layer.sealCenter, col, s * 0.08);
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

void _drawArcText(ui.Canvas canvas, ui.Offset center, double radius, String text, ui.Color col, double fs, bool top) {
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
  final spacing = fs * 0.15;
  final totalAngle = (total + spacing * (chars.length - 1)) / radius;
  double angle = top ? (-math.pi / 2 - totalAngle / 2) : (math.pi / 2 + totalAngle / 2);
  for (int i = 0; i < chars.length; i++) {
    final half = (pars[i].longestLine / 2) / radius;
    if (top) {
      angle += half;
      final pos = ui.Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle + math.pi / 2);
      canvas.drawParagraph(pars[i], ui.Offset(-pars[i].longestLine / 2, -pars[i].height / 2));
      canvas.restore();
      angle += half + spacing / radius;
    } else {
      angle -= half;
      final pos = ui.Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle - math.pi / 2);
      canvas.drawParagraph(pars[i], ui.Offset(-pars[i].longestLine / 2, -pars[i].height / 2));
      canvas.restore();
      angle -= half + spacing / radius;
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
