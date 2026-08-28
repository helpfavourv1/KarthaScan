import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../core/utils/constants.dart';

class OverlayPlacementSheet extends StatefulWidget {
  const OverlayPlacementSheet({
    super.key,
    required this.pagePaths,
    required this.overlayBytes,
    this.title = 'Place Overlay',
    this.initialWidthFraction = 0.3,
  });

  final List<String> pagePaths;
  final Uint8List overlayBytes;
  final String title;
  final double initialWidthFraction;

  @override
  State<OverlayPlacementSheet> createState() => OverlayPlacementSheetState();
}

class OverlayPlacementSheetState extends State<OverlayPlacementSheet> {
  int _currentPageIndex = 0;
  double _centerX = 0.5;
  double _centerY = 0.5;
  double _rotationDegrees = 0;
  double _scale = 1.0;
  late double _widthFraction;
  double _overlayAspect = 2.0;
  double _pageAspect = 0.75;

  @override
  void initState() {
    super.initState();
    _widthFraction = widget.initialWidthFraction;
    final decoded = img.decodePng(widget.overlayBytes);
    if (decoded != null && decoded.height > 0) {
      _overlayAspect = (decoded.width / decoded.height).clamp(0.1, 10.0).toDouble();
    }
    _loadPageAspect(_currentPageIndex);
  }

  Future<void> _loadPageAspect(int index) async {
    try {
      final bytes = await File(widget.pagePaths[index]).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.height > 0 && mounted) {
        setState(() => _pageAspect = decoded.width / decoded.height);
      }
    } catch (_) {}
  }

  Rect _imageRect(Size stack) {
    double imgW = stack.width;
    double imgH = imgW / _pageAspect;
    if (imgH > stack.height) {
      imgH = stack.height;
      imgW = imgH * _pageAspect;
    }
    return Rect.fromLTWH((stack.width - imgW) / 2, (stack.height - imgH) / 2, imgW, imgH);
  }

  @override
  Widget build(BuildContext context) {
    final currentPagePath = widget.pagePaths[_currentPageIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _currentPageIndex > 0
                            ? () => setState(() { _currentPageIndex--; _loadPageAspect(_currentPageIndex); })
                            : null,
                      ),
                      Text('Page ${_currentPageIndex + 1} / ${widget.pagePaths.length}', style: TextStyle(fontSize: 14, color: textPrimary)),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _currentPageIndex < widget.pagePaths.length - 1
                            ? () => setState(() { _currentPageIndex++; _loadPageAspect(_currentPageIndex); })
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stack = Size(constraints.maxWidth, constraints.maxHeight);
                    final imgRect = _imageRect(stack);
                    final dispW = imgRect.width * _widthFraction * _scale;
                    final dispH = dispW / _overlayAspect;
                    final cx = imgRect.left + _centerX * imgRect.width;
                    final cy = imgRect.top + _centerY * imgRect.height;
                    return Stack(
                      children: [
                        Positioned.fill(child: Image.file(File(currentPagePath), fit: BoxFit.contain)),
                        Positioned(
                          left: cx - dispW / 2,
                          top: cy - dispH / 2,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) => setState(() {
                              _centerX = (_centerX + details.delta.dx / imgRect.width).clamp(0.0, 1.0).toDouble();
                              _centerY = (_centerY + details.delta.dy / imgRect.height).clamp(0.0, 1.0).toDouble();
                            }),
                            child: Transform.rotate(
                              angle: _rotationDegrees * 3.14159 / 180,
                              child: Opacity(
                                opacity: 0.85,
                                child: Image.memory(widget.overlayBytes, width: dispW, height: dispH, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Rotate', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _rotationDegrees,
                      min: -180,
                      max: 180,
                      activeColor: accent,
                      onChanged: (value) => setState(() => _rotationDegrees = value),
                    ),
                  ),
                  Text('${_rotationDegrees.round()}°', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Scale', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _scale,
                      min: 0.3,
                      max: 2.5,
                      activeColor: accent,
                      onChanged: (value) => setState(() => _scale = value),
                    ),
                  ),
                  Text('${_scale.toStringAsFixed(2)}x', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
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
                    onPressed: () {
                      Navigator.pop(context, (_currentPageIndex, _centerX, _centerY, _rotationDegrees, _scale, _widthFraction));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirm'),
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
