import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class _Stroke {
  _Stroke(this.points, this.colorInt, this.width);
  final List<Offset> points;
  final int colorInt;
  final double width;
}

class EraserSheet extends StatefulWidget {
  const EraserSheet({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<EraserSheet> createState() => _EraserSheetState();
}

class _EraserSheetState extends State<EraserSheet> {
  final List<_Stroke> _strokes = [];
  _Stroke? _active;
  int _colorInt = 0xFFFFFFFF;
  double _width = 40;
  bool _sampleMode = false;
  bool _loading = true;
  img.Image? _sampleImage;
  double _displayW = 0;
  double _displayH = 0;

  static const List<int> _swatches = [0xFFFFFFFF, 0xFFF2F2F7, 0xFFE8E8ED, 0xFF111111];

  @override
  void initState() {
    super.initState();
    _loadSample();
  }

  Future<void> _loadSample() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        _sampleImage = decoded.width > 800 ? img.copyResize(decoded, width: 800) : decoded;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  static Color toColor(int v) =>
      Color.fromARGB((v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);

  void _sampleAt(Offset local) {
    final s = _sampleImage;
    if (s == null || _displayW == 0 || _displayH == 0) return;
    final sx = (local.dx / _displayW * s.width).round().clamp(0, s.width - 1);
    final sy = (local.dy / _displayH * s.height).round().clamp(0, s.height - 1);
    final p = s.getPixel(sx, sy);
    final a = 255;
    final r = p.r.toInt().clamp(0, 255);
    final g = p.g.toInt().clamp(0, 255);
    final b = p.b.toInt().clamp(0, 255);
    setState(() {
      _colorInt = (a << 24) | (r << 16) | (g << 8) | b;
      _sampleMode = false;
    });
  }

  List<Map<String, dynamic>> _export() {
    return _strokes
        .map((s) => {
              'points': s.points.map((o) => [o.dx / _displayW, o.dy / _displayH]).toList(),
              'color': s.colorInt,
              'width': s.width / _displayW,
            })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Eraser', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final file = File(widget.imagePath);
                          final imgW = _sampleImage?.width ?? 1;
                          final imgH = _sampleImage?.height ?? 1;
                          final aspect = imgW / imgH;
                          double displayW = constraints.maxWidth;
                          double displayH = displayW / aspect;
                          if (displayH > constraints.maxHeight) {
                            displayH = constraints.maxHeight;
                            displayW = displayH * aspect;
                          }
                          _displayW = displayW;
                          _displayH = displayH;
                          return Center(
                            child: SizedBox(
                              width: displayW,
                              height: displayH,
                              child: GestureDetector(
                                onTapDown: (d) {
                                  if (_sampleMode) _sampleAt(d.localPosition);
                                },
                                onPanStart: (d) {
                                  if (_sampleMode) return;
                                  setState(() => _active = _Stroke([d.localPosition], _colorInt, _width));
                                },
                                onPanUpdate: (d) {
                                  if (_sampleMode || _active == null) return;
                                  setState(() => _active!.points.add(d.localPosition));
                                },
                                onPanEnd: (d) {
                                  if (_active == null) return;
                                  setState(() {
                                    _strokes.add(_active!);
                                    _active = null;
                                  });
                                },
                                child: Stack(
                                  children: [
                                    Image.file(file, fit: BoxFit.fill),
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _EraserPainter(strokes: _strokes, active: _active),
                                      ),
                                    ),
                                    if (_sampleMode)
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.blue.withValues(alpha: 0.08),
                                          child: const Center(
                                            child: Text('Tap a spot to sample its color',
                                                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w700)),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Size', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(value: _width, min: 10, max: 120, onChanged: (v) => setState(() => _width = v)),
                  ),
                  Text(_width.round().toString(), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.colorize, color: _sampleMode ? accent : textPrimary),
                    tooltip: 'Sample color from page',
                    onPressed: () => setState(() => _sampleMode = !_sampleMode),
                  ),
                  for (final sw in _swatches)
                    GestureDetector(
                      onTap: () => setState(() => _colorInt = sw),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: toColor(sw),
                          shape: BoxShape.circle,
                          border: Border.all(color: _colorInt == sw ? accent : Colors.grey, width: _colorInt == sw ? 3 : 1),
                        ),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.removeLast()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.clear()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _strokes.isEmpty ? null : () => Navigator.pop(context, _export()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EraserPainter extends CustomPainter {
  _EraserPainter({required this.strokes, required this.active});
  final List<_Stroke> strokes;
  final _Stroke? active;

  @override
  void paint(Canvas canvas, Size size) {
    void draw(_Stroke? s) { if (s == null) return;
      final paint = Paint()
        ..color = _EraserSheetState.toColor(s.colorInt)
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
      } else {
        for (int i = 0; i < s.points.length - 1; i++) {
          canvas.drawLine(s.points[i], s.points[i + 1], paint);
        }
      }
    }

    for (final s in strokes) { draw(s); }
    if (active != null) draw(active);
  }

  @override
  bool shouldRepaint(covariant _EraserPainter oldDelegate) => true;
}
