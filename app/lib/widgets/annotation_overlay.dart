import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

enum AnnotationMode { pen, highlighter, rect, arrow, ellipse }

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
  final List<AnnotationMode> _modes = <AnnotationMode>[];
  final List<List<Offset>> _redoStrokes = <List<Offset>>[];
  final List<Color> _redoColors = <Color>[];
  final List<double> _redoWidths = <double>[];
  final List<bool> _redoHighlighter = <bool>[];
  final List<AnnotationMode> _redoModes = <AnnotationMode>[];

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
      _modes.clear();
      _redoStrokes.clear();
      _redoColors.clear();
      _redoWidths.clear();
      _redoHighlighter.clear();
      _redoModes.clear();
    });
  }

  void undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redoStrokes.add(_strokes.removeLast());
      _redoColors.add(_colors.removeLast());
      _redoWidths.add(_widths.removeLast());
      _redoHighlighter.add(_isHighlighter.removeLast());
      _redoModes.add(_modes.removeLast());
    });
  }

  void redo() {
    if (_redoStrokes.isEmpty) return;
    setState(() {
      _strokes.add(_redoStrokes.removeLast());
      _colors.add(_redoColors.removeLast());
      _widths.add(_redoWidths.removeLast());
      _isHighlighter.add(_redoHighlighter.removeLast());
      _modes.add(_redoModes.removeLast());
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

  bool get _isShape => _mode == AnnotationMode.rect || _mode == AnnotationMode.arrow || _mode == AnnotationMode.ellipse;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _strokes.add(<Offset>[details.localPosition, if (_isShape) details.localPosition]);
      _colors.add(_currentColor);
      _widths.add(_currentWidth);
      _isHighlighter.add(_mode == AnnotationMode.highlighter);
      _modes.add(_mode);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_strokes.isEmpty) return;
    setState(() {
      if (_isShape) {
        if (_strokes.last.length >= 2) {
          _strokes.last[1] = details.localPosition;
        } else {
          _strokes.last.add(details.localPosition);
        }
      } else {
        _strokes.last.add(details.localPosition);
      }
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
            modes: _modes,
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
    required this.modes,
  });

  final List<List<Offset>> strokes;
  final List<Color> colors;
  final List<double> widths;
  final List<bool> isHighlighter;
  final List<AnnotationMode> modes;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < strokes.length; i++) {
      final List<Offset> stroke = strokes[i];
      final Paint paint = Paint()
        ..color = isHighlighter[i] ? colors[i].withValues(alpha: 0.3) : colors[i]
        ..strokeWidth = widths[i]
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final AnnotationMode m = i < modes.length ? modes[i] : AnnotationMode.pen;
      if ((m == AnnotationMode.rect || m == AnnotationMode.ellipse || m == AnnotationMode.arrow) && stroke.length >= 2) {
        final Rect rect = Rect.fromPoints(stroke.first, stroke.last);
        if (m == AnnotationMode.rect) {
          canvas.drawRect(rect, paint);
        } else if (m == AnnotationMode.ellipse) {
          canvas.drawOval(rect, paint);
        } else {
          final Offset a = stroke.first;
          final Offset b = stroke.last;
          canvas.drawLine(a, b, paint);
          final double angle = (b - a).direction;
          final double headLen = 12.0 + widths[i] * 2;
          final Offset p1 = b - Offset.fromDirection(angle - 0.5, headLen);
          final Offset p2 = b - Offset.fromDirection(angle + 0.5, headLen);
          final Path head = Path()..moveTo(b.dx, b.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close();
          canvas.drawPath(head, paint..style = PaintingStyle.fill);
        }
      } else {
        for (int j = 0; j < stroke.length - 1; j++) {
          canvas.drawLine(stroke[j], stroke[j + 1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
