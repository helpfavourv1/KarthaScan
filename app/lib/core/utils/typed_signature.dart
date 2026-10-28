import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// The script fonts offered for a typed signature (bundled with the app).
const List<String> typedSignatureFonts = <String>['DancingScript', 'Caveat'];

/// Draws [text] in a signature style and returns a PNG with a transparent
/// background, cut to the ink. Returns null for empty text.
Future<Uint8List?> renderTypedSignature(
  String text, {
  required String fontFamily,
  required int color,
  double fontSize = 160,
}) async {
  final String t = text.trim();
  if (t.isEmpty) return null;
  final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: ui.TextAlign.left,
    fontSize: fontSize,
    fontFamily: fontFamily,
    fontWeight: ui.FontWeight.w500,
  ))
    ..pushStyle(ui.TextStyle(color: ui.Color(color)))
    ..addText(t);
  final ui.Paragraph paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 20000));
  final int pad = (fontSize * 0.15).round();
  final int w = (paragraph.longestLine.ceil() + pad * 2).clamp(1, 12000);
  final int h = (paragraph.height.ceil() + pad * 2).clamp(1, 12000);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawParagraph(paragraph, ui.Offset(pad.toDouble(), pad.toDouble()));
  final ui.Image image = await recorder.endRecording().toImage(w, h);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;
  return trimToInk(data.buffer.asUint8List());
}

/// Cuts the empty border off a PNG so the picture is just the ink and a signature
/// is sized by what is written, not by the pad it was drawn on.
Uint8List trimToInk(Uint8List png, {int margin = 6}) {
  try {
    final img.Image? decoded = img.decodePng(png);
    if (decoded == null) return png;
    final img.Image trimmed = img.trim(decoded, mode: img.TrimMode.transparent);
    if (trimmed.width < 1 || trimmed.height < 1) return png;
    final img.Image padded = img.Image(
      width: trimmed.width + margin * 2,
      height: trimmed.height + margin * 2,
      numChannels: 4,
    );
    img.compositeImage(padded, trimmed, dstX: margin, dstY: margin);
    return Uint8List.fromList(img.encodePng(padded));
  } catch (_) {
    return png;
  }
}
