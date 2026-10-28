import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../core/utils/constants.dart';
import '../core/utils/ink_stroke.dart';
import '../core/utils/typed_signature.dart' show trimToInk;
import '../l10n/app_localizations.dart';

class SignatureCanvas extends StatefulWidget {
  const SignatureCanvas({
    super.key,
    this.strokeColor = Colors.black,
    this.strokeWidth = 3,
  });

  final Color strokeColor;
  final double strokeWidth;

  @override
  State<SignatureCanvas> createState() => SignatureCanvasState();
}

class SignatureCanvasState extends State<SignatureCanvas> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<_Stroke> _strokes = <_Stroke>[];
  final Stopwatch _clock = Stopwatch()..start();
  late Color _strokeColor = widget.strokeColor;
  late double _strokeWidth = widget.strokeWidth;
  bool _pressure = true;

  /// Pen-like width that follows drawing speed (on by default).
  void setPressure(bool on) => setState(() => _pressure = on);

  void setColor(Color color) => setState(() => _strokeColor = color);
  void setWidth(double width) => setState(() => _strokeWidth = width);

  bool get isEmpty => _strokes.isEmpty;

  void clear() {
    setState(_strokes.clear);
  }

  void undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _strokes.add(_Stroke()..add(InkPoint(details.localPosition, _clock.elapsedMilliseconds)));
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.last.add(InkPoint(details.localPosition, _clock.elapsedMilliseconds));
    });
  }

  Future<Uint8List?> exportPng({double pixelRatio = 3}) async {
    if (isEmpty) return null;
    final RenderRepaintBoundary? boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    // Cut to the ink so the signature is sized by what is written, not by the pad.
    return trimToInk(byteData.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;
    final Color surface = AppColors.bgSecondaryLight; // Always paper-white for visibility
    final hint = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        border: Border.all(color: border, width: AppShape.cardBorderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Use Positioned.fill to ensure the GestureDetector fills the available space
          Positioned.fill(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Start the line where the finger touched down, not about 18 px later.
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                child: CustomPaint(
                  painter: _SignaturePainter(
                    strokes: _strokes,
                    color: _strokeColor,
                    strokeWidth: _strokeWidth,
                    pressure: _pressure,
                  ),
                  // The painter will get its size from the parent's constraints
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          if (isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    l10n.signatureCanvasHint,
                    style: TextStyle(color: hint, fontSize: AppTypography.bodySize),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One drawn line: raw points plus the smoothed pieces, rebuilt only when
/// the line changes.
class _Stroke {
  final List<InkPoint> points = <InkPoint>[];
  List<InkSegment>? _cache;
  double _cacheWidth = -1;
  bool _cachePressure = true;

  void add(InkPoint p) {
    points.add(p);
    _cache = null;
  }

  List<InkSegment> segments(double width, bool pressure) {
    if (_cache == null || _cacheWidth != width || _cachePressure != pressure) {
      _cache = buildInkSegments(points, width, pressure: pressure);
      _cacheWidth = width;
      _cachePressure = pressure;
    }
    return _cache!;
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
    required this.pressure,
  });

  final List<_Stroke> strokes;
  final Color color;
  final double strokeWidth;
  final bool pressure;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final _Stroke stroke in strokes) {
      for (final InkSegment seg in stroke.segments(strokeWidth, pressure)) {
        paint.strokeWidth = seg.width;
        if (seg.a == seg.b) {
          canvas.drawCircle(seg.a, seg.width / 2, paint..style = PaintingStyle.fill);
          paint.style = PaintingStyle.stroke;
        } else {
          canvas.drawLine(seg.a, seg.b, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
