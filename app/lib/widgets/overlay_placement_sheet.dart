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
  });

  final List<String> pagePaths;
  final Uint8List overlayBytes;
  final String title;

  @override
  State<OverlayPlacementSheet> createState() => OverlayPlacementSheetState();
}

class OverlayPlacementSheetState extends State<OverlayPlacementSheet> {
  int _currentPageIndex = 0;
  Offset _offset = Offset.zero;
  double _rotationDegrees = 0;
  double _scale = 1.0;
  final GlobalKey _stackKey = GlobalKey();
  bool _initialized = false;
  double _overlayAspect = 2.0;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodePng(widget.overlayBytes);
    if (decoded != null && decoded.height > 0) {
      _overlayAspect = (decoded.width / decoded.height).clamp(0.1, 10.0).toDouble();
    }
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
                        onPressed: _currentPageIndex > 0 ? () => setState(() => _currentPageIndex--) : null,
                      ),
                      Text('Page ${_currentPageIndex + 1} / ${widget.pagePaths.length}', style: TextStyle(fontSize: 14, color: textPrimary)),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _currentPageIndex < widget.pagePaths.length - 1 ? () => setState(() => _currentPageIndex++) : null,
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
                    if (!_initialized) {
                      _initialized = true;
                      _offset = Offset(constraints.maxWidth * 0.5 - 50, constraints.maxHeight * 0.6);
                    }
                    return Stack(
                      key: _stackKey,
                      children: [
                        Positioned.fill(child: Image.file(File(currentPagePath), fit: BoxFit.contain)),
                        Positioned(
                          left: _offset.dx,
                          top: _offset.dy,
                          child: GestureDetector(
                            onPanUpdate: (details) => setState(() {
                              _offset += details.delta;
                              _offset = Offset(
                                _offset.dx.clamp(0.0, constraints.maxWidth - 80).toDouble(),
                                _offset.dy.clamp(0.0, constraints.maxHeight - 40).toDouble(),
                              );
                            }),
                            child: Transform.rotate(
                              angle: _rotationDegrees * 3.14159 / 180,
                              child: Transform.scale(
                                scale: _scale,
                                child: Opacity(
                                  opacity: 0.85,
                                  child: Image.memory(widget.overlayBytes, width: 120, height: 120 / _overlayAspect, fit: BoxFit.contain),
                                ),
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
                      final RenderBox? box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
                      final Size size = box?.size ?? const Size(1, 1);
                      final double pctX = (_offset.dx / size.width).clamp(0.0, 1.0).toDouble();
                      final double pctY = (_offset.dy / size.height).clamp(0.0, 1.0).toDouble();
                      Navigator.pop(context, (_currentPageIndex, pctX, pctY, _rotationDegrees, _scale));
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
