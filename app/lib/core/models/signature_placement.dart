import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show immutable, listEquals;

@immutable
class SignatureInk {
  const SignatureInk({
    required this.id,
    required this.bytes,
    this.label = '',
    this.aspect = 2.0,
  });

  final String id;
  final Uint8List bytes;
  final String label;
  final double aspect;

  Map<String, dynamic> toJson() => {
    'id': id,
    'bytes': base64Encode(bytes),
    'label': label,
    'aspect': aspect,
  };

  factory SignatureInk.fromJson(Map<String, dynamic> json) {
    return SignatureInk(
      id: json['id'] as String,
      bytes: base64Decode(json['bytes'] as String),
      label: json['label'] as String? ?? '',
      aspect: (json['aspect'] as num?)?.toDouble() ?? 2.0,
    );
  }

  SignatureInk copyWith({String? id, Uint8List? bytes, String? label, double? aspect}) {
    return SignatureInk(
      id: id ?? this.id,
      bytes: bytes ?? this.bytes,
      label: label ?? this.label,
      aspect: aspect ?? this.aspect,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SignatureInk &&
        other.id == id &&
        listEquals(other.bytes, bytes) &&
        other.label == label &&
        other.aspect == aspect;
  }

  @override
  int get hashCode => Object.hash(id, Object.hashAll(bytes), label, aspect);
}

@immutable
class SignaturePlacement {
  const SignaturePlacement({
    required this.pctX,
    required this.pctY,
    this.rotationDegrees = 0,
    this.scale = 1.0,
  });

  /// Center X as a fraction of page width (0..1).
  final double pctX;

  /// Center Y as a fraction of page height (0..1).
  final double pctY;
  final double rotationDegrees;
  final double scale;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SignaturePlacement &&
        other.pctX == pctX &&
        other.pctY == pctY &&
        other.rotationDegrees == rotationDegrees &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(pctX, pctY, rotationDegrees, scale);

  @override
  String toString() => 'SignaturePlacement(pctX: $pctX, pctY: $pctY, rot: $rotationDegrees, scale: $scale)';
}
