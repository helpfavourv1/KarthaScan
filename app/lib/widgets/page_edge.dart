import 'package:flutter/material.dart';

/// The tone behind a page on screen. It is darker than the screen background in
/// light mode (and darker still in dark mode) so a white page stands out from it.
Color pageBackdropColor(bool isDark) => isDark ? const Color(0xFF0B0B0D) : const Color(0xFFD5D8DE);

/// Screen-only finish for the page area, shared by Scan detail, Full screen and
/// Export. It draws, above everything on the page:
///  - a fade over whatever hangs past the page edge (marks are cut off there when
///    the page is saved, printed or shared), and
///  - a thin edge line with a soft shadow, so a white page on a white-looking
///    screen still shows where it ends.
/// It never touches the page picture: print, export, share and email render the
/// page from the photo and its edits, not from these widgets.
class PageEdgeOverlay extends StatelessWidget {
  const PageEdgeOverlay({super.key, required this.pageSize, this.controller});

  /// Size of the page inside the host (the host centres it).
  final Size pageSize;

  /// Zoom/pan of the page, so the edge follows it.
  final TransformationController? controller;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color backdrop = pageBackdropColor(dark);
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: controller == null
              ? CustomPaint(key: const ValueKey<String>('pageEdge'), painter: PageEdgePainter(pageSize, null, backdrop, dark))
              : AnimatedBuilder(
                  animation: controller!,
                  builder: (BuildContext context, Widget? _) => CustomPaint(
                    key: const ValueKey<String>('pageEdge'),
                    painter: PageEdgePainter(pageSize, controller!.value.clone(), backdrop, dark),
                  ),
                ),
        ),
      ),
    );
  }
}

class PageEdgePainter extends CustomPainter {
  PageEdgePainter(this.pageSize, this.matrix, this.backdrop, this.dark);

  final Size pageSize;
  final Matrix4? matrix;
  final Color backdrop;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (matrix != null) canvas.transform(matrix!.storage);
    final Rect hole = Rect.fromCenter(center: size.center(Offset.zero), width: pageSize.width, height: pageSize.height);
    // Soft shadow just outside the page, drawn before the fade so it stays visible.
    canvas.drawRect(
      hole.inflate(0.5),
      Paint()
        ..color = Color(dark ? 0x99000000 : 0x40000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Fade over anything hanging past the edge (not over the shadow or the page).
    final Path outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(-4000, -4000, size.width + 8000, size.height + 8000)),
      Path()..addRect(hole.inflate(0.5)),
    );
    canvas.drawPath(outside, Paint()..color = backdrop.withValues(alpha: 0.6));
    // Thin edge line.
    canvas.drawRect(
      hole,
      Paint()
        ..color = Color(dark ? 0x66FFFFFF : 0x59000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PageEdgePainter old) => old.pageSize != pageSize || old.matrix != matrix || old.backdrop != backdrop || old.dark != dark;
}
