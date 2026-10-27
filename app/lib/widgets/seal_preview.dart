import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/models/seal_design.dart';
import '../core/utils/seal_draw.dart';

/// Draws a [SealDesign] with the same routine the page and the export use, so the
/// preview is exactly what will be placed.
class SealPreview extends StatefulWidget {
  const SealPreview({super.key, required this.design, this.size = 150});
  final SealDesign design;
  final double size;

  @override
  State<SealPreview> createState() => _SealPreviewState();
}

class _SealPreviewState extends State<SealPreview> {
  ui.Image? _logo;
  Uint8List? _decodedFrom;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(SealPreview old) {
    super.didUpdateWidget(old);
    _decode();
  }

  Future<void> _decode() async {
    final Uint8List? bytes = widget.design.logo;
    if (identical(bytes, _decodedFrom)) return;
    _decodedFrom = bytes;
    if (bytes == null) {
      _logo?.dispose();
      if (mounted) setState(() => _logo = null);
      return;
    }
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted || !identical(bytes, _decodedFrom)) return;
      final ui.Image? old = _logo;
      setState(() => _logo = frame.image);
      old?.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _logo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('sealPreview'),
      size: Size.square(widget.size),
      painter: _Painter(widget.design, _logo),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.design, this.logo);
  final SealDesign design;
  final ui.Image? logo;

  @override
  void paint(Canvas canvas, Size size) => drawSeal(canvas, size.width, design.toLayer(), centerImage: logo);

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
