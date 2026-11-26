import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The page's signatures, drawings, watermarks and stamps, drawn (not clickable)
/// over the picture an edit sheet shows, so the user can see that they are kept.
///
/// [box] is where the page sits inside the host, as fractions (0..1) of the host's
/// width and height. Null means the layers cover the whole host.
class PageLayersGhost extends StatelessWidget {
  const PageLayersGhost({super.key, required this.png, this.box, this.opacity = 0.9});

  final Uint8List? png;
  final Rect? box;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = png;
    if (bytes == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Rect b = box ?? const Rect.fromLTWH(0, 0, 1, 1);
            return Stack(children: <Widget>[
              Positioned(
                key: const ValueKey<String>('pageLayersGhost'),
                left: b.left * c.maxWidth,
                top: b.top * c.maxHeight,
                width: b.width * c.maxWidth,
                height: b.height * c.maxHeight,
                child: Opacity(opacity: opacity, child: Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true)),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Layers picture plus where the page sits on the uncropped photo.
class PageGhost {
  const PageGhost(this.png, this.box);
  final Uint8List? png;

  /// The cropped area as fractions of the photo, or null when there is no crop.
  final Rect? box;
}
