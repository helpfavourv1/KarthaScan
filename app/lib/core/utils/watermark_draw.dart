import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/scan_document.dart';

/// Share of the page width one repeat takes at scale 1.
const double tileWidthFraction = 0.22;

/// The most repeats drawn on a page, so a tiny size cannot ask for thousands.
const int maxTiles = 600;

/// The watermark's text as a paragraph with no width limit, drawn at [fontSize].
ui.Paragraph watermarkParagraph(WatermarkLayer layer, double fontSize) {
  final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: ui.TextAlign.left,
    fontSize: fontSize,
    fontWeight: layer.bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
    fontStyle: layer.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
    fontFamily: layer.fontFamily,
  ))
    ..pushStyle(ui.TextStyle(
      color: ui.Color(layer.color).withValues(alpha: layer.opacity),
      decoration: layer.underline ? ui.TextDecoration.underline : ui.TextDecoration.none,
      shadows: layer.shadowColor != null
          ? <ui.Shadow>[ui.Shadow(offset: ui.Offset(layer.shadowOffsetX, layer.shadowOffsetY), color: ui.Color(layer.shadowColor!), blurRadius: 2)]
          : null,
    ))
    ..addText(layer.text);
  return b.build()..layout(const ui.ParagraphConstraints(width: 100000));
}

/// Where each repeat is centred, in page pixels, before the grid is turned.
/// Rows are offset by half a step so the pattern is staggered, like a real
/// security watermark. Pure, so it is tested without drawing.
List<ui.Offset> tileCentres(ui.Size page, double tileW, double tileH) {
  final double pitchX = tileW * 1.5;
  final double pitchY = math.max(tileH * 2.6, tileW * 0.35);
  final double reach = math.sqrt(page.width * page.width + page.height * page.height) / 2 + tileW;
  final List<ui.Offset> out = <ui.Offset>[];
  int row = 0;
  for (double y = -reach; y <= reach; y += pitchY, row++) {
    final double shift = row.isEven ? 0 : pitchX / 2;
    for (double x = -reach + shift; x <= reach; x += pitchX) {
      out.add(ui.Offset(x, y));
      if (out.length >= maxTiles * 4) return out;
    }
  }
  return out;
}

/// Draws [layer] repeated across a page of [page] size. [logo] is used instead of
/// the text when the layer has an image. The same code draws the live preview and
/// the exported page, so what is seen is what is printed.
void paintWatermarkTiles(ui.Canvas canvas, ui.Size page, WatermarkLayer layer, {ui.Image? logo}) {
  final double tileW = page.width * tileWidthFraction * layer.placement.scale;
  if (tileW < 4) return;
  ui.Paragraph? para;
  double tileH;
  double k = 1;
  if (layer.isImage) {
    if (logo == null || logo.width == 0) return;
    tileH = tileW * logo.height / logo.width;
  } else {
    if (layer.text.trim().isEmpty) return;
    para = watermarkParagraph(layer, 100);
    final double w = para.longestLine;
    if (w <= 0) return;
    k = tileW / w;
    tileH = para.height * k;
  }
  final List<ui.Offset> centres = tileCentres(page, tileW, tileH);
  canvas.save();
  canvas.clipRect(ui.Offset.zero & page);
  canvas.translate(page.width / 2, page.height / 2);
  canvas.rotate(layer.placement.rotationDegrees * math.pi / 180);
  int drawn = 0;
  final ui.Paint imagePaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..color = ui.Color.fromRGBO(255, 255, 255, layer.opacity);
  for (final ui.Offset c in centres) {
    if (drawn >= maxTiles) break;
    drawn++;
    if (layer.isImage) {
      canvas.drawImageRect(
        logo!,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        ui.Rect.fromCenter(center: c, width: tileW, height: tileH),
        imagePaint,
      );
    } else {
      canvas.save();
      canvas.translate(c.dx - tileW / 2, c.dy - tileH / 2);
      canvas.scale(k);
      canvas.drawParagraph(para!, ui.Offset.zero);
      canvas.restore();
    }
  }
  canvas.restore();
}
