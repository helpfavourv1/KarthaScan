// lib/core/models/ocr_block.dart
//
// Immutable model per Section 16 (file #9): text, boundingBox, confidence,
// language. [OcrBoundingBox] is defined here as a small plain-Dart value
// type rather than using dart:ui's Rect — this keeps ocr_service.dart's
// output (Section 16 file #14) trivially unit-testable with plain `dart
// test`, with no Flutter binding required at all, not just no
// device/emulator.
import 'package:flutter/foundation.dart' show immutable;

@immutable
class OcrBoundingBox {
  const OcrBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  OcrBoundingBox copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return OcrBoundingBox(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    };
  }

  factory OcrBoundingBox.fromJson(Map<String, dynamic> json) {
    return OcrBoundingBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OcrBoundingBox &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'OcrBoundingBox(left: $left, top: $top, width: $width, height: $height)';
}

@immutable
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.boundingBox,
    required this.confidence,
    required this.language,
  });

  final String text;
  final OcrBoundingBox boundingBox;

  /// Recognition confidence in the range [0.0, 1.0]. ML Kit only reports
  /// per-element confidence on Android — on iOS this may be a best-effort
  /// estimate rather than a native VisionKit value; see
  /// ocr_service.dart's platform notes.
  final double confidence;

  /// BCP-47-ish language/script identifier, e.g. 'en', 'zh', 'ar', or
  /// 'und' when ML Kit could not determine one.
  final String language;

  OcrBlock copyWith({
    String? text,
    OcrBoundingBox? boundingBox,
    double? confidence,
    String? language,
  }) {
    return OcrBlock(
      text: text ?? this.text,
      boundingBox: boundingBox ?? this.boundingBox,
      confidence: confidence ?? this.confidence,
      language: language ?? this.language,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'boundingBox': boundingBox.toJson(),
      'confidence': confidence,
      'language': language,
    };
  }

  factory OcrBlock.fromJson(Map<String, dynamic> json) {
    return OcrBlock(
      text: json['text'] as String,
      boundingBox: OcrBoundingBox.fromJson(
        json['boundingBox'] as Map<String, dynamic>,
      ),
      confidence: (json['confidence'] as num).toDouble(),
      language: json['language'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OcrBlock &&
        other.text == text &&
        other.boundingBox == boundingBox &&
        other.confidence == confidence &&
        other.language == language;
  }

  @override
  int get hashCode => Object.hash(text, boundingBox, confidence, language);

  @override
  String toString() =>
      'OcrBlock(text: ${text.length > 20 ? '${text.substring(0, 20)}…' : text}, '
      'confidence: $confidence, language: $language)';
}
