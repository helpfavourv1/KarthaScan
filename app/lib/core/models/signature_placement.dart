import 'package:flutter/foundation.dart' show immutable;

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
