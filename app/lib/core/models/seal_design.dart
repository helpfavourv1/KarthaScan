import 'dart:convert';
import 'dart:typed_data';

import 'scan_document.dart';
import 'signature_placement.dart';

/// Everything that makes up a seal's look, apart from where it sits on a page.
/// Saved in the seal library and used to draw the editor preview.
class SealDesign {
  const SealDesign({
    required this.text,
    this.subtext = '',
    this.shape = 'oval',
    this.center = 'star',
    this.logo,
    this.color = 0xFFDD2222,
    this.textColor,
    this.textScale = 1.0,
    this.font = 'sans',
    this.ink = false,
  });

  final String text;
  final String subtext;
  final String shape;
  final String center;
  final Uint8List? logo;
  final int color;
  final int? textColor;
  final double textScale;
  final String font;
  final bool ink;

  /// A layer used only to draw this design (preview, thumbnails).
  StampLayer toLayer({String id = 'preview'}) => StampLayer(
        id: id,
        pageIndex: 0,
        kind: 'seal',
        placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5),
        text: text,
        color: color,
        sealShape: shape,
        sealSubtext: subtext,
        sealCenter: center,
        sealImageBytes: logo,
        sealTextColor: textColor,
        sealTextScale: textScale,
        sealFont: font,
        sealInk: ink,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'subtext': subtext,
        'shape': shape,
        'center': center,
        if (logo != null) 'logo': base64Encode(logo!),
        'color': color,
        if (textColor != null) 'textColor': textColor,
        'textScale': textScale,
        'font': font,
        'ink': ink,
      };

  factory SealDesign.fromJson(Map<String, dynamic> j) => SealDesign(
        text: j['text'] as String? ?? '',
        subtext: j['subtext'] as String? ?? '',
        shape: j['shape'] as String? ?? 'oval',
        center: j['center'] as String? ?? 'star',
        logo: j['logo'] is String ? base64Decode(j['logo'] as String) : null,
        color: j['color'] as int? ?? 0xFFDD2222,
        textColor: j['textColor'] as int?,
        textScale: (j['textScale'] as num?)?.toDouble() ?? 1.0,
        font: j['font'] as String? ?? 'sans',
        ink: j['ink'] as bool? ?? false,
      );

  /// Same visible design (the logo compared by content).
  bool sameLookAs(SealDesign o) =>
      text == o.text && subtext == o.subtext && shape == o.shape && center == o.center && color == o.color &&
      textColor == o.textColor && textScale == o.textScale && font == o.font && ink == o.ink &&
      _sameBytes(logo, o.logo);

  static bool _sameBytes(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
