import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/utils/perspective.dart';
import '../l10n/app_localizations.dart';

/// What the crop screen returns: four corners in photo pixels and an optional
/// width / height the straightened page must have.
class CropResult {
  const CropResult(this.quad, this.aspect);
  final List<Offset> quad;
  final double? aspect;
}

List<Offset>? _detectJob(Uint8List bytes) {
  final img.Image? im = img.decodeImage(bytes);
  return im == null ? null : detectDocumentQuad(im);
}

/// Crop with four draggable corners (so a page photographed at an angle is
/// straightened), a magnifier while dragging, auto-detect and shape presets.
class PerspectiveCropSheet extends StatefulWidget {
  const PerspectiveCropSheet({super.key, required this.imagePath, this.initialQuad, this.initialAspect});
  final String imagePath;
  final List<Offset>? initialQuad;
  final double? initialAspect;

  @override
  State<PerspectiveCropSheet> createState() => _PerspectiveCropSheetState();
}

class _PerspectiveCropSheetState extends State<PerspectiveCropSheet> {
  ui.Image? _image; // shown picture (downsized)
  Uint8List? _bytes;
  double _photoW = 0, _photoH = 0; // real photo size in pixels
  List<Offset> _quad = const <Offset>[]; // photo pixels
  double? _aspect;
  bool _loading = true, _busy = false, _touched = false, _notFound = false;
  int _active = -1;
  Offset _grabOffset = Offset.zero;
  Offset? _finger; // local position of the finger for the magnifier

  static const double _hit = 48;

  @override
  void initState() {
    super.initState();
    _aspect = widget.initialAspect;
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List bytes = await File(widget.imagePath).readAsBytes();
      // Only the header is read to learn the real size.
      final img.DecodeInfo? info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0) throw StateError('size');
      _photoW = info.width.toDouble();
      _photoH = info.height.toDouble();
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _photoW >= _photoH ? math.min(info.width, 1400) : null,
        targetHeight: _photoH > _photoW ? math.min(info.height, 1400) : null,
      );
      _image = (await codec.getNextFrame()).image;
      _bytes = bytes;
      _quad = widget.initialQuad ?? _inset();
      if (!mounted) return;
      setState(() => _loading = false);
      if (widget.initialQuad == null) _autoDetect(silent: true);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  List<Offset> _inset() {
    final double mx = _photoW * 0.08, my = _photoH * 0.08;
    return <Offset>[Offset(mx, my), Offset(_photoW - mx, my), Offset(_photoW - mx, _photoH - my), Offset(mx, _photoH - my)];
  }

  Future<void> _autoDetect({bool silent = false}) async {
    final Uint8List? bytes = _bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    List<Offset>? found;
    try {
      found = await compute(_detectJob, bytes);
    } catch (_) {
      found = null;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (found != null && !(silent && _touched)) {
        _quad = found;
        _notFound = false;
      } else if (found == null && !silent) {
        _notFound = true;
      }
    });
  }

  void _reset() => setState(() {
        _quad = _inset();
        _aspect = null;
        _notFound = false;
        _touched = true;
      });

  // photo pixels <-> screen
  Rect _fit(Size box) {
    final double s = math.min(box.width / _photoW, box.height / _photoH);
    final double w = _photoW * s, h = _photoH * s;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Offset _toScreen(Offset p, Rect fit) => Offset(fit.left + p.dx / _photoW * fit.width, fit.top + p.dy / _photoH * fit.height);
  Offset _toPhoto(Offset s, Rect fit) => Offset(((s.dx - fit.left) / fit.width * _photoW).clamp(0.0, _photoW).toDouble(), ((s.dy - fit.top) / fit.height * _photoH).clamp(0.0, _photoH).toDouble());

  void _down(DragStartDetails d, Rect fit) {
    int best = -1;
    double bestD = _hit;
    for (int i = 0; i < 4; i++) {
      final double dist = (_toScreen(_quad[i], fit) - d.localPosition).distance;
      if (dist < bestD) {
        bestD = dist;
        best = i;
      }
    }
    if (best >= 0) {
      _active = best;
      _grabOffset = _toScreen(_quad[best], fit) - d.localPosition;
      setState(() {
        _finger = d.localPosition;
        _touched = true;
      });
    }
  }

  void _move(DragUpdateDetails d, Rect fit) {
    if (_active < 0) return;
    final List<Offset> next = List<Offset>.of(_quad);
    next[_active] = _toPhoto(d.localPosition + _grabOffset, fit);
    setState(() {
      _quad = next;
      _finger = d.localPosition;
    });
  }

  void _end() => setState(() {
        _active = -1;
        _finger = null;
      });

  double? get _presetAspect => _aspect;

  /// An output shape matched to the page's own orientation.
  double _shape(double portrait) {
    final Size s = quadOutputSize(_quad);
    return s.width > s.height ? 1 / portrait : portrait;
  }

  bool get _valid => _quad.length == 4 && isUsableQuad(_quad, minSide: 16);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double height = MediaQuery.of(context).size.height * 0.92;
    final chips = <MapEntry<String, double?>>[
      MapEntry<String, double?>('free', null),
      MapEntry<String, double?>('a4', 1 / math.sqrt2),
      MapEntry<String, double?>('letter', 8.5 / 11),
      MapEntry<String, double?>('id', 85.6 / 54),
      MapEntry<String, double?>('square', 1.0),
    ];
    String label(String k) => switch (k) {
          'free' => l10n.cropAspectFree,
          'a4' => 'A4',
          'letter' => 'Letter',
          'id' => l10n.cropAspectId,
          _ => l10n.cropAspectSquare,
        };
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: <Widget>[
              Expanded(child: Text(l10n.cropLabel, style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                key: const Key('cropAuto'),
                onPressed: _busy || _loading ? null : () => _autoDetect(),
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high, size: 18),
                label: Text(l10n.cropAuto),
              ),
              TextButton(key: const Key('cropReset'), onPressed: _loading ? null : _reset, child: Text(l10n.commonReset)),
            ]),
          ),
          if (_notFound) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l10n.cropNoPageFound, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final Rect fit = _fit(Size(c.maxWidth, c.maxHeight));
                    return GestureDetector(
                      key: const Key('cropArea'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: (d) => _down(d, fit),
                      onPanUpdate: (d) => _move(d, fit),
                      onPanEnd: (_) => _end(),
                      onPanCancel: _end,
                      child: CustomPaint(
                        size: Size(c.maxWidth, c.maxHeight),
                        painter: _CropPainter(_image!, fit, <Offset>[for (final Offset o in _quad) _toScreen(o, fit)], _active, _valid, Theme.of(context).colorScheme.primary, _finger, _photoW),
                      ),
                    );
                  }),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                for (final MapEntry<String, double?> e in chips)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: ChoiceChip(
                      key: Key('cropAspect:${e.key}'),
                      label: Text(label(e.key)),
                      selected: e.value == null ? _aspect == null : (_aspect != null && (_aspect! - _shape(e.value!)).abs() < 1e-6),
                      onSelected: (_) => setState(() => _aspect = e.value == null ? null : _shape(e.value!)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: <Widget>[
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('cropConfirm'),
                  onPressed: _loading || !_valid ? null : () => Navigator.pop(context, CropResult(_quad, _presetAspect)),
                  child: Text(l10n.cropLabel),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.fit, this.pts, this.active, this.valid, this.color, this.finger, this.photoW);
  final ui.Image image;
  final Rect fit;
  final List<Offset> pts;
  final int active;
  final bool valid;
  final Color color;
  final Offset? finger;
  final double photoW;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect srcAll = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, srcAll, fit, Paint()..filterQuality = FilterQuality.medium);
    final Path poly = Path()..addPolygon(pts, true);
    final Path dim = Path.combine(PathOperation.difference, Path()..addRect(fit), poly);
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));
    canvas.drawPath(poly, Paint()..color = valid ? color : const Color(0xFFE53935)..style = PaintingStyle.stroke..strokeWidth = 2.5);
    for (int i = 0; i < 4; i++) {
      canvas.drawCircle(pts[i], i == active ? 16 : 13, Paint()..color = Colors.white);
      canvas.drawCircle(pts[i], i == active ? 16 : 13, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);
    }
    if (finger != null && active >= 0) {
      // Magnifier above the finger (below it when near the top edge).
      const double r = 52, zoom = 3;
      final Offset focus = pts[active];
      Offset c = Offset(focus.dx, focus.dy - 110);
      if (c.dy < r + 4) c = Offset(focus.dx, focus.dy + 110);
      c = Offset(c.dx.clamp(r + 4, size.width - r - 4).toDouble(), c.dy.clamp(r + 4, size.height - r - 4).toDouble());
      final double scale = fit.width / image.width * zoom;
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawRect(Rect.fromCircle(center: c, radius: r), Paint()..color = Colors.black);
      final double imgX = (focus.dx - fit.left) / fit.width * image.width;
      final double imgY = (focus.dy - fit.top) / fit.height * image.height;
      final Rect dst = Rect.fromLTWH(c.dx - imgX * scale, c.dy - imgY * scale, image.width * scale, image.height * scale);
      canvas.drawImageRect(image, srcAll, dst, Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
      canvas.drawCircle(c, r, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
      final Paint cross = Paint()..color = color..strokeWidth = 1.5;
      canvas.drawLine(c - const Offset(10, 0), c + const Offset(10, 0), cross);
      canvas.drawLine(c - const Offset(0, 10), c + const Offset(0, 10), cross);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}
