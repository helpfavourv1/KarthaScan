import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/scan_document.dart';

/// Draws a custom seal at size [s] (square canvas).
/// [centerImage] is a pre-decoded ui.Image for the center logo (optional).
/// Shared by the editor preview, the page overlay and the export renderer, so
/// what is seen while editing is what is exported.
///
/// Shapes: 'oval' (landscape), 'round' (circle) and 'rectangle'. Lettering is
/// fitted automatically: it is never wider than its arc or band, and the size
/// setting ([StampLayer.sealTextScale]) only scales down from the largest fit.
void drawSeal(ui.Canvas canvas, double s, StampLayer layer, {ui.Image? centerImage}) {
  final ui.Color ringCol = ui.Color(layer.color).withValues(alpha: layer.opacity);
  final ui.Color textCol = layer.sealTextColor == null ? ringCol : ui.Color(layer.sealTextColor!).withValues(alpha: layer.opacity);
  final String? family = layer.sealFont == 'serif' ? 'serif' : null;
  final double scale = layer.sealTextScale.clamp(0.5, 1.0);

  if (layer.sealInk) canvas.saveLayer(ui.Rect.fromLTWH(0, 0, s, s), ui.Paint());

  if (layer.sealShape == 'rectangle') {
    _drawRectangleSeal(canvas, s, layer, ringCol, textCol, family, scale);
  } else {
    final bool round = layer.sealShape == 'round';
    final double h = round ? s * 0.94 : s * 0.72;
    final ui.Rect ovalRect = ui.Rect.fromCenter(center: ui.Offset(s / 2, s / 2), width: s * 0.94, height: h);

    canvas.drawOval(ovalRect, ui.Paint()..color = ringCol..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.035);
    canvas.drawOval(ovalRect.deflate(s * 0.09), ui.Paint()..color = ringCol..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.010);

    // Lettering sits centred in the band between the two rings.
    final double rx = s * 0.425;
    final double ry = round ? s * 0.425 : s * 0.315;
    final double topMax = s * 0.075 * scale;
    final double bottomMax = s * 0.0667 * scale;
    final bool hasSub = layer.sealSubtext.isNotEmpty;
    final double limit = (hasSub ? 190 : 250) * math.pi / 180;
    if (_needsStraightText(layer.text) || (hasSub && _needsStraightText(layer.sealSubtext))) {
      // Joined and right-to-left scripts cannot be spaced letter by letter around
      // a curve without breaking them, so they are set straight and fitted.
      final double b = ry - s * 0.09;
      final double d = b * 0.75;
      final double a = rx - s * 0.09 + s * 0.045;
      final double halfChord = a * math.sqrt(math.max(0.0, 1 - (d / b) * (d / b)));
      final double w = halfChord * 2 * 0.9;
      _drawFitLabel(canvas, ui.Offset(s / 2, s / 2 - d), layer.text, textCol, topMax, w, family);
      if (hasSub) _drawFitLabel(canvas, ui.Offset(s / 2, s / 2 + d), layer.sealSubtext, textCol, bottomMax, w, family);
    } else {
      _drawArcFitted(canvas, ui.Offset(s / 2, s / 2), rx, ry, layer.text, textCol, topMax, true, limit, family);
      if (hasSub) _drawArcFitted(canvas, ui.Offset(s / 2, s / 2), rx, ry, layer.sealSubtext, textCol, bottomMax, false, limit, family);
    }
  }

  // Centre element (both shapes), inside the inner space.
  if (layer.sealCenter == 'star') {
    _drawStar(canvas, ui.Offset(s / 2, s / 2), s * 0.13, ringCol);
  } else if (layer.sealCenter == 'image' && centerImage != null) {
    _drawCenterImage(canvas, ui.Offset(s / 2, s / 2), s * 0.15, centerImage);
  } else if (layer.sealCenter.isNotEmpty && layer.sealCenter != 'image' && layer.sealCenter != 'star') {
    _drawFitLabel(canvas, ui.Offset(s / 2, s / 2), layer.sealCenter, textCol, s * 0.09, s * 0.46, family);
  }

  if (layer.sealInk) {
    _applyInk(canvas, s, _seedOf(layer.id));
    canvas.restore();
  }
}

/// True for scripts that must be shaped as whole words: Hebrew, Arabic, Syriac,
/// Thaana and their presentation forms.
bool _needsStraightText(String text) {
  for (final int c in text.runes) {
    if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF)) return true;
  }
  return false;
}

bool _isMark(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    (c >= 0x0900 && c <= 0x0903) ||
    (c >= 0x093A && c <= 0x094F && c != 0x0949 && c != 0x094A) ||
    (c >= 0x0951 && c <= 0x0957) ||
    (c >= 0x0962 && c <= 0x0963) ||
    (c >= 0x0981 && c <= 0x0983) ||
    (c >= 0x09BC && c <= 0x09CD) ||
    c == 0x0E31 || (c >= 0x0E34 && c <= 0x0E3A) || (c >= 0x0E47 && c <= 0x0E4E) ||
    (c >= 0x1AB0 && c <= 0x1AFF) ||
    (c >= 0x20D0 && c <= 0x20FF) ||
    (c >= 0xFE00 && c <= 0xFE0F) ||
    c == 0x200D || c == 0x3099 || c == 0x309A;

/// Splits text into letters a person would count: a base letter stays together
/// with its combining marks, and a joiner or virama keeps the next letter attached.
List<String> splitClusters(String text) {
  final List<String> out = <String>[];
  final StringBuffer cur = StringBuffer();
  bool joinNext = false;
  for (final int c in text.runes) {
    final bool mark = _isMark(c);
    if (cur.isEmpty || mark || joinNext) {
      cur.writeCharCode(c);
    } else {
      out.add(cur.toString());
      cur.clear();
      cur.writeCharCode(c);
    }
    joinNext = c == 0x200D || c == 0x094D || c == 0x09CD;
  }
  if (cur.isNotEmpty) out.add(cur.toString());
  return out;
}

ui.Paragraph _paragraph(String text, double fs, ui.Color col, String? family) {
  return (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fs, fontWeight: ui.FontWeight.w700, fontFamily: family))
        ..pushStyle(ui.TextStyle(color: col, fontFamily: family))
        ..addText(text))
      .build()
    ..layout(const ui.ParagraphConstraints(width: 100000));
}

void _drawRectangleSeal(ui.Canvas canvas, double s, StampLayer layer, ui.Color ringCol, ui.Color textCol, String? family, double scale) {
  final outerRect = ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(s * 0.03, s * 0.20, s * 0.94, s * 0.60), ui.Radius.circular(s * 0.04));
  canvas.drawRRect(outerRect, ui.Paint()..color = ringCol..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.035);
  final innerRect = ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(s * 0.10, s * 0.32, s * 0.80, s * 0.36), ui.Radius.circular(s * 0.02));
  canvas.drawRRect(innerRect, ui.Paint()..color = ringCol..style = ui.PaintingStyle.stroke..strokeWidth = s * 0.010);
  final double topFont = s * 0.075 * scale;
  final double bottomFont = s * 0.0667 * scale;
  _drawFitLabel(canvas, ui.Offset(s / 2, s * 0.26), layer.text, textCol, topFont, s * 0.80, family);
  if (layer.sealSubtext.isNotEmpty) {
    _drawFitLabel(canvas, ui.Offset(s / 2, s * 0.74), layer.sealSubtext, textCol, bottomFont, s * 0.80, family);
  }
}

/// A line of text centred on [at], at most [maxFont] high and never wider than [maxWidth].
void _drawFitLabel(ui.Canvas canvas, ui.Offset at, String text, ui.Color col, double maxFont, double maxWidth, String? family) {
  if (text.isEmpty || maxFont <= 0) return;
  ui.Paragraph par = _paragraph(text, maxFont, col, family);
  double fs = maxFont;
  if (par.longestLine > maxWidth && par.longestLine > 0) {
    fs = maxFont * maxWidth / par.longestLine;
    par = _paragraph(text, fs, col, family);
  }
  canvas.drawParagraph(par, ui.Offset(at.dx - par.longestLine / 2, at.dy - par.height / 2));
}

/// Text along the top or bottom of the ring, as large as fits in [limitAngle].
void _drawArcFitted(ui.Canvas canvas, ui.Offset center, double rx, double ry, String text, ui.Color col, double maxFont, bool top, double limitAngle, String? family) {
  if (text.isEmpty || maxFont <= 2) return;
  final List<String> chars = splitClusters(text);
  final double avgR = (rx + ry) / 2;
  // Width grows in step with the font size, so measure once and scale.
  const double ref = 100;
  double refTotal = 0;
  for (final String ch in chars) {
    refTotal += _paragraph(ch, ref, col, family).longestLine;
  }
  final double k = refTotal / ref + 0.2 * (chars.length - 1);
  double fs = maxFont;
  if (k > 0 && fs * k / avgR > limitAngle) fs = limitAngle * avgR / k;
  if (fs <= 1) return;

  final List<ui.Paragraph> pars = <ui.Paragraph>[for (final String ch in chars) _paragraph(ch, fs, col, family)];
  double total = 0;
  for (final ui.Paragraph p in pars) {
    total += p.longestLine;
  }
  final double spacing = fs * 0.2;
  final double totalAngle = (total + spacing * (chars.length - 1)) / avgR;
  double angle = top ? (-math.pi / 2 - totalAngle / 2) : (math.pi / 2 + totalAngle / 2);
  for (int i = 0; i < pars.length; i++) {
    final double half = (pars[i].longestLine / 2) / avgR;
    angle += top ? half : -half;
    final double x = center.dx + rx * math.cos(angle);
    final double y = center.dy + ry * math.sin(angle);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(top ? angle + math.pi / 2 : angle - math.pi / 2);
    canvas.drawParagraph(pars[i], ui.Offset(-pars[i].longestLine / 2, -pars[i].height / 2));
    canvas.restore();
    angle += top ? (half + spacing / avgR) : -(half + spacing / avgR);
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
  canvas.clipPath(ui.Path()..addOval(ui.Rect.fromCircle(center: center, radius: radius)));
  final src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  canvas.drawImageRect(image, src, ui.Rect.fromCircle(center: center, radius: radius), ui.Paint()..filterQuality = ui.FilterQuality.high);
  canvas.restore();
  canvas.drawCircle(
    center,
    radius,
    ui.Paint()..style = ui.PaintingStyle.stroke..strokeWidth = radius * 0.06..color = const ui.Color(0xFF000000).withValues(alpha: 0.3),
  );
}

/// FNV-1a, so a seal gets the same worn marks every run, on every device.
int _seedOf(String id) {
  int h = 0x811C9DC5;
  for (final int c in id.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Worn rubber-stamp look: speckles and a few scratches knocked out of the ink.
void _applyInk(ui.Canvas canvas, double s, int seed) {
  final math.Random r = math.Random(seed);
  final ui.Paint knock = ui.Paint()..blendMode = ui.BlendMode.dstOut;
  for (int i = 0; i < 260; i++) {
    knock.color = ui.Color.fromRGBO(0, 0, 0, 0.35 + 0.65 * r.nextDouble());
    canvas.drawCircle(ui.Offset(r.nextDouble() * s, r.nextDouble() * s), s * (0.002 + 0.006 * r.nextDouble()), knock);
  }
  final ui.Paint scratch = ui.Paint()..blendMode = ui.BlendMode.dstOut..strokeWidth = s * 0.0015..color = const ui.Color(0xCC000000);
  for (int i = 0; i < 18; i++) {
    final double x = r.nextDouble() * s, y = r.nextDouble() * s;
    final double a = r.nextDouble() * math.pi;
    final double len = s * (0.04 + 0.1 * r.nextDouble());
    canvas.drawLine(ui.Offset(x, y), ui.Offset(x + len * math.cos(a), y + len * math.sin(a)), scratch);
  }
}
