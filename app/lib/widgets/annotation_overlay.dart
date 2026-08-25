import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

enum AnnotationMode { pen, highlighter }

class AnnotationOverlay extends StatefulWidget {
  const AnnotationOverlay({super.key});

  @override
  State<AnnotationOverlay> createState() => AnnotationOverlayState();
}

class AnnotationOverlayState extends State<AnnotationOverlay> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = <List<Offset>>[];
  final List<Color> _colors = <Color>[];
  final List<double> _widths = <double>[];
  final List<bool> _isHighlighter = <bool>[];

  Color _currentColor = Colors.black;
  double _currentWidth = 4.0;
  AnnotationMode _mode = AnnotationMode.pen;

  bool get isEmpty => _strokes.isEmpty;

  void clear() {
    setState(() {
      _strokes.clear();
      _colors.clear();
      _widths.clear();
      _isHighlighter.clear();
    });
  }

  void setMode(AnnotationMode mode) {
    setState(() {
      _mode = mode;
      if (mode == AnnotationMode.highlighter) {
        _currentColor = Colors.yellow;
        _currentWidth = 20.0;
      } else {
        _currentColor = Colors.black;
        _currentWidth = 4.0;
      }
    });
  }

  void setColor(Color color) => setState(() => _currentColor = color);
  void setWidth(double width) => setState(() => _currentWidth = width);

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _strokes.add(<Offset>[details.localPosition]);
      _colors.add(_currentColor);
      _widths.add(_currentWidth);
      _isHighlighter.add(_mode == AnnotationMode.highlighter);
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
    return RepaintBoundary(
      key: _boundaryKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        child: CustomPaint(
          painter: _AnnotationPainter(
            strokes: _strokes,
            colors: _colors,
            widths: _widths,
            isHighlighter: _isHighlighter,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({
    required this.strokes,
    required this.colors,
    required this.widths,
    required this.isHighlighter,
  });

  final List<List<Offset>> strokes;
  final List<Color> colors;
  final List<double> widths;
  final List<bool> isHighlighter;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < strokes.length; i++) {
      final List<Offset> stroke = strokes[i];
      final Paint paint = Paint()
        ..color = isHighlighter[i] ? colors[i].withValues(alpha: 0.3) : colors[i]
        ..strokeWidth = widths[i]
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int j = 0; j < stroke.length - 1; j++) {
        canvas.drawLine(stroke[j], stroke[j + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
