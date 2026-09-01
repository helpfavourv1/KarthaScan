// lib/widgets/region_select_sheet.dart
//
// Public region-select sheet + overlay painter, lifted verbatim from
// scan_detail_screen.dart so every host shares one implementation.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../l10n/app_localizations.dart';

class RegionSelectSheet extends StatefulWidget {
  const RegionSelectSheet({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<RegionSelectSheet> createState() => _RegionSelectSheetState();
}

class _RegionSelectSheetState extends State<RegionSelectSheet> {
  Rect? _displayRect;
  img.Image? _originalImage;
  bool _loading = true;
  double _displayW = 0;
  double _displayH = 0;

  String _activeHandle = 'none';
  Offset? _dragStart;

  static const double _hitSlop = 24.0;
  static const double _snapThreshold = 12.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      _originalImage = img.decodeImage(bytes);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_displayRect == null) return;
    final pos = details.localPosition;
    final r = _displayRect!;

    final distTL = (pos - Offset(r.left, r.top)).distance;
    final distTR = (pos - Offset(r.right, r.top)).distance;
    final distBL = (pos - Offset(r.left, r.bottom)).distance;
    final distBR = (pos - Offset(r.right, r.bottom)).distance;

    double minDist = distTL;
    String handle = 'tl';
    if (distTR < minDist) { minDist = distTR; handle = 'tr'; }
    if (distBL < minDist) { minDist = distBL; handle = 'bl'; }
    if (distBR < minDist) { minDist = distBR; handle = 'br'; }

    if (minDist < _hitSlop) {
      _activeHandle = handle;
    } else if (r.contains(pos)) {
      _activeHandle = 'body';
      _dragStart = pos;
    } else {
      _activeHandle = 'none';
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_displayRect == null || _activeHandle == 'none') return;
    final pos = details.localPosition;
    final r = _displayRect!;

    double newLeft = r.left;
    double newTop = r.top;
    double newRight = r.right;
    double newBottom = r.bottom;

    if (_activeHandle == 'tl') { newLeft = pos.dx; newTop = pos.dy; }
    else if (_activeHandle == 'tr') { newRight = pos.dx; newTop = pos.dy; }
    else if (_activeHandle == 'bl') { newLeft = pos.dx; newBottom = pos.dy; }
    else if (_activeHandle == 'br') { newRight = pos.dx; newBottom = pos.dy; }
    else if (_activeHandle == 'body' && _dragStart != null) {
      final delta = pos - _dragStart!;
      newLeft += delta.dx; newTop += delta.dy;
      newRight += delta.dx; newBottom += delta.dy;
      _dragStart = pos;
    }

    newLeft = newLeft.clamp(0.0, _displayW);
    newTop = newTop.clamp(0.0, _displayH);
    newRight = newRight.clamp(0.0, _displayW);
    newBottom = newBottom.clamp(0.0, _displayH);

    if (newRight - newLeft < 20) {
      if (_activeHandle == 'tl' || _activeHandle == 'bl') {
        newLeft = newRight - 20;
      } else {
        newRight = newLeft + 20;
      }
    }
    if (newBottom - newTop < 20) {
      if (_activeHandle == 'tl' || _activeHandle == 'tr') {
        newTop = newBottom - 20;
      } else {
        newBottom = newTop + 20;
      }
    }

    if (newLeft < _snapThreshold) newLeft = 0;
    if (newTop < _snapThreshold) newTop = 0;
    if (newRight > _displayW - _snapThreshold) newRight = _displayW;
    if (newBottom > _displayH - _snapThreshold) newBottom = _displayH;

    setState(() {
      _displayRect = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _activeHandle = 'none';
    _dragStart = null;
  }

  void _initRect() {
    if (_displayRect == null && _displayW > 0 && _displayH > 0) {
      _displayRect = Rect.fromCenter(
        center: Offset(_displayW / 2, _displayH / 2),
        width: _displayW * 0.5,
        height: _displayH * 0.5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(AppLocalizations.of(context).selectRegionTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: _loading || _originalImage == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final imgW = _originalImage!.width;
                        final imgH = _originalImage!.height;
                        final aspect = imgW / imgH;

                        double displayW = constraints.maxWidth;
                        double displayH = displayW / aspect;

                        if (displayH > constraints.maxHeight) {
                          displayH = constraints.maxHeight;
                          displayW = displayH * aspect;
                        }

                        _displayW = displayW;
                        _displayH = displayH;
                        _initRect();

                        return Center(
                          child: SizedBox(
                            width: displayW,
                            height: displayH,
                            child: GestureDetector(
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: Stack(
                                children: [
                                  Image.file(File(widget.imagePath), fit: BoxFit.fill),
                                  CustomPaint(
                                    size: Size(displayW, displayH),
                                    painter: RegionOverlayPainter(rect: _displayRect),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _displayRect == null || _displayW == 0 || _displayH == 0
                        ? null
                        : () {
                            final scaleX = _originalImage!.width / _displayW;
                            final scaleY = _originalImage!.height / _displayH;
                            final originalRect = Rect.fromLTRB(
                              _displayRect!.left * scaleX,
                              _displayRect!.top * scaleY,
                              _displayRect!.right * scaleX,
                              _displayRect!.bottom * scaleY,
                            );
                            Navigator.pop(context, originalRect);
                          },
                    child: Text(AppLocalizations.of(context).commonExtract),
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

class RegionOverlayPainter extends CustomPainter {
  final Rect? rect;
  RegionOverlayPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    if (rect == null) return;
    final r = rect!;

    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(r, borderPaint);

    final handlePaint = Paint()..color = Colors.white;
    final handleBorder = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const radius = 10.0;
    final corners = [
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.left, r.bottom),
      Offset(r.right, r.bottom),
    ];

    for (final corner in corners) {
      canvas.drawCircle(corner, radius, handlePaint);
      canvas.drawCircle(corner, radius, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant RegionOverlayPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}
