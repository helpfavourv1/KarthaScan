// lib/widgets/manual_crop_overlay.dart
//
// Quadrilateral drag handles on imported photo. User pinches/drags 4
// corners to simulate perspective correction (Section 16 file #74).
//
// This widget only captures the 4 corner points via drag handles — pure
// Flutter UI, no image processing. manual_crop_screen.dart (file #75)
// reads ManualCropOverlayState.corners and does the actual warp.
import 'package:flutter/material.dart';

import '../core/utils/constants.dart';

class ManualCropOverlay extends StatefulWidget {
  const ManualCropOverlay({
    super.key,
    required this.imageWidget,
    required this.imageSize,
  });

  /// The image being cropped, already laid out at [imageSize].
  final Widget imageWidget;

  /// The logical size the image is rendered at, so initial corner
  /// positions and drag bounds are computed correctly.
  final Size imageSize;

  @override
  State<ManualCropOverlay> createState() => ManualCropOverlayState();
}

class ManualCropOverlayState extends State<ManualCropOverlay> {
  late List<Offset> _corners;

  @override
  void initState() {
    super.initState();
    _resetCorners();
  }

  @override
  void didUpdateWidget(covariant ManualCropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageSize != widget.imageSize) {
      _resetCorners();
    }
  }

  void _resetCorners() {
    // Default to a 10%-inset rectangle rather than the full image bounds
    // — gives the user visible, grabbable handles immediately instead of
    // starting exactly on the image edge.
    final double w = widget.imageSize.width;
    final double h = widget.imageSize.height;
    final double insetX = w * 0.1;
    final double insetY = h * 0.1;
    _corners = <Offset>[
      Offset(insetX, insetY), // top-left
      Offset(w - insetX, insetY), // top-right
      Offset(w - insetX, h - insetY), // bottom-right
      Offset(insetX, h - insetY), // bottom-left
    ];
  }

  /// The 4 corner points, in image-local logical pixels, ordered
  /// top-left, top-right, bottom-right, bottom-left. Read by
  /// manual_crop_screen.dart after the user confirms the crop.
  List<Offset> get corners => List<Offset>.unmodifiable(_corners);

  void _dragCorner(int index, DragUpdateDetails details) {
    setState(() {
      final Offset updated = _corners[index] + details.delta;
      _corners[index] = Offset(
        updated.dx.clamp(0, widget.imageSize.width),
        updated.dy.clamp(0, widget.imageSize.height),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SizedBox(
      width: widget.imageSize.width,
      height: widget.imageSize.height,
      child: Stack(
        children: <Widget>[
          widget.imageWidget,
          CustomPaint(
            size: widget.imageSize,
            painter: _QuadPainter(corners: _corners, color: accent),
          ),
          for (int i = 0; i < _corners.length; i++)
            Positioned(
              left: _corners[i].dx - 16,
              top: _corners[i].dy - 16,
              child: GestureDetector(
                onPanUpdate: (DragUpdateDetails details) => _dragCorner(i, details),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({required this.corners, required this.color});

  final List<Offset> corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final Paint fillPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final Path path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) {
    return oldDelegate.corners != corners || oldDelegate.color != color;
  }
}
