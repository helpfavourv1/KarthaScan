import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../core/utils/constants.dart';
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
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                child: CustomPaint(
                  painter: _SignaturePainter(
                    strokes: _strokes,
                    color: widget.strokeColor,
                    strokeWidth: widget.strokeWidth,
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
    return true;
  }
}
