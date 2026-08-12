// lib/widgets/signature_canvas.dart
//
// Draw or import signature, place on document, flatten — Pro-gated
// (Section 16 file #32).
//
// This widget handles the DRAWING capture step: recording pen strokes and
// rendering them to a transparent-background PNG via
// RenderRepaintBoundary. "Place on document, flatten" — positioning the
// captured signature onto a specific page and baking it into the final
// export bytes — is an export_screen.dart / export_service.dart
// orchestration concern (Phase 5/2), not something this drawing widget
// does itself. The "import" half (picking an existing signature image
// instead of drawing) is a plain gallery-pick action the calling screen
// handles by supplying an alternate signature image path — nothing about
// importing needs to live in this file. Pro-gating itself (whether this
// widget is reachable at all) is enforced by the calling screen, the same
// pattern as filter_bottom_sheet.dart.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../core/utils/constants.dart';

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

/// Public state so a parent screen can hold a
/// `GlobalKey<SignatureCanvasState>` and call [clear] / [isEmpty] /
/// [exportPng] directly — the standard Flutter pattern for exposing
/// imperative actions on a stateful child without threading a callback
/// through every stroke event.
class SignatureCanvasState extends State<SignatureCanvas> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = <List<Offset>>[];

  bool get isEmpty => _strokes.isEmpty;

  void clear() {
    setState(_strokes.clear);
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _strokes.add(<Offset>[details.localPosition]);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.last.add(details.localPosition);
    });
  }

  /// Renders the current strokes to a transparent-background PNG. Returns
  /// null if nothing has been drawn yet.
  Future<Uint8List?> exportPng({double pixelRatio = 3}) async {
    if (isEmpty) return null;
    final RenderRepaintBoundary? boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color hint = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        border: Border.all(color: border, width: AppShape.cardBorderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          RepaintBoundary(
            key: _boundaryKey,
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              child: CustomPaint(
                painter: _SignaturePainter(
                  strokes: _strokes,
                  color: widget.strokeColor,
                  strokeWidth: widget.strokeWidth,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          if (isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    'Sign here',
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

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final List<Offset> stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
