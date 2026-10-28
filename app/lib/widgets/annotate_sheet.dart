import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/models/page_transform.dart';
import '../core/utils/annotation_items.dart';
import '../l10n/app_localizations.dart';
import 'annotation_overlay.dart';
import 'color_picker_dialog.dart';

/// The page as it is shown, ready to draw behind the marks.
class _Backdrop {
  const _Backdrop(this.image, this.src, this.aspect, this.exportWidth);
  final ui.Image image;
  final Rect src;
  final double aspect;

  /// Width in pixels the finished drawing should have (the page's own width, capped).
  final double exportWidth;
}

/// Draw on the real page. Marks are made over the page itself, so what is seen is
/// what is placed, and the result carries the placement that puts the ink exactly
/// where it was drawn. With no [pagePath] it draws on a blank sheet.
class AnnotateSheet extends StatefulWidget {
  const AnnotateSheet({super.key, this.pagePath, this.pageTransform});

  final String? pagePath;
  final PageTransform? pageTransform;

  @override
  State<AnnotateSheet> createState() => _AnnotateSheetState();
}

class _AnnotateSheetState extends State<AnnotateSheet> {
  final GlobalKey<AnnotationOverlayState> _overlayKey = GlobalKey();
  AnnotationMode _mode = AnnotationMode.pen;
  Color _color = Colors.black;
  double _width = 4.0;
  _Backdrop? _backdrop;
  bool _loading = true;
  bool _busy = false;
  double _frameWidth = 360;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? path = widget.pagePath;
    _Backdrop? result;
    if (path != null) {
      try {
        final Uint8List bytes = await File(path).readAsBytes();
        final img.DecodeInfo? info = img.findDecoderForData(bytes)?.startDecode(bytes);
        if (info != null && info.width > 0 && info.height > 0) {
          final int w = info.width, h = info.height;
          final ui.Codec codec = await ui.instantiateImageCodec(
            bytes,
            targetWidth: w >= h ? math.min(w, 1600) : null,
            targetHeight: h > w ? math.min(h, 1600) : null,
          );
          final ui.Image image = (await codec.getNextFrame()).image;
          final double f = image.width / w;
          final PageTransform? t = widget.pageTransform;
          final Rect? crop = t?.cropRect;
          final Rect src = (crop != null && crop.width > 0 && crop.height > 0)
              ? Rect.fromLTRB(crop.left * f, crop.top * f, crop.right * f, crop.bottom * f)
              : Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
          double aspect = src.width / src.height;
          double exportW = (crop != null && crop.width > 0 ? crop.width : w.toDouble());
          final int? rw = t?.resizeWidth, rh = t?.resizeHeight;
          if (rw != null && rh != null && rw > 0 && rh > 0) {
            aspect = rw / rh;
            exportW = rw.toDouble();
          }
          result = _Backdrop(image, src, aspect.clamp(0.1, 10.0).toDouble(), math.min(exportW, 2400));
        }
      } catch (_) {
        result = null; // fall back to a blank sheet
      }
    }
    if (!mounted) return;
    setState(() {
      _backdrop = result;
      _loading = false;
    });
  }

  void _apply() {
    _overlayKey.currentState?.setColor(_color);
    _overlayKey.currentState?.setWidth(_width);
  }

  Future<void> _confirm() async {
    final AnnotationOverlayState? overlay = _overlayKey.currentState;
    if (overlay == null || _busy) return;
    setState(() => _busy = true);
    final double target = _backdrop?.exportWidth ?? 1200;
    final Uint8List? raw = await overlay.exportPng(pixelRatio: target / _frameWidth);
    if (raw == null || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final AnnotateResult? result = await compute(trimAnnotation, raw);
    if (!mounted) return;
    if (result == null) {
      setState(() => _busy = false);
      return;
    }
    Navigator.pop(context, result);
  }

  String _modeLabel(AppLocalizations l, AnnotationMode m) {
    switch (m) {
      case AnnotationMode.pen:
        return l.annotationModePen;
      case AnnotationMode.highlighter:
        return l.annotationModeHighlighter;
      case AnnotationMode.rect:
        return l.annotationModeRect;
      case AnnotationMode.arrow:
        return l.annotationModeArrow;
      case AnnotationMode.ellipse:
        return l.annotationModeEllipse;
      case AnnotationMode.select:
        return l.annotationModeSelect;
      case AnnotationMode.eraser:
        return l.annotationModeEraser;
    }
  }

  IconData _modeIcon(AnnotationMode m) {
    switch (m) {
      case AnnotationMode.pen:
        return Icons.edit;
      case AnnotationMode.highlighter:
        return Icons.highlight;
      case AnnotationMode.rect:
        return Icons.crop_square;
      case AnnotationMode.arrow:
        return Icons.arrow_forward;
      case AnnotationMode.ellipse:
        return Icons.circle_outlined;
      case AnnotationMode.select:
        return Icons.open_with;
      case AnnotationMode.eraser:
        return Icons.auto_fix_normal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    final AnnotationOverlayState? ov = _overlayKey.currentState;
    final bool selected = ov?.hasSelection ?? false;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.94,
          decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.annotateTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: AspectRatio(
                            aspectRatio: _backdrop?.aspect ?? 0.707,
                            child: LayoutBuilder(builder: (BuildContext c, BoxConstraints box) {
                              _frameWidth = box.maxWidth;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_backdrop != null)
                                    CustomPaint(painter: _BackdropPainter(_backdrop!))
                                  else
                                    const ColoredBox(color: Colors.white),
                                  ClipRect(
                                    child: AnnotationOverlay(
                                      key: _overlayKey,
                                      paper: false,
                                      selectionColor: accent,
                                      onChanged: () {
                                        if (mounted) setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final AnnotationMode m in AnnotationMode.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey<String>('annMode:${m.name}'),
                            avatar: Icon(_modeIcon(m), size: 16),
                            label: Text(_modeLabel(l10n, m)),
                            selected: _mode == m,
                            onSelected: (_) {
                              // Only the highlighter has its own colour and width; moving
                              // between the other tools keeps what the person chose.
                              final bool wasHighlighter = _mode == AnnotationMode.highlighter;
                              setState(() {
                                _mode = m;
                                if (m == AnnotationMode.highlighter) {
                                  _color = Colors.yellow;
                                  _width = 20.0;
                                } else if (wasHighlighter && m != AnnotationMode.select && m != AnnotationMode.eraser) {
                                  _color = Colors.black;
                                  _width = 4.0;
                                }
                              });
                              _overlayKey.currentState?.setMode(m);
                              if (m != AnnotationMode.select && m != AnnotationMode.eraser) _apply();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final c in [Colors.black, Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.white])
                            GestureDetector(
                              key: ValueKey<String>('annColor:${c.toARGB32()}'),
                              onTap: () {
                                setState(() => _color = c);
                                _overlayKey.currentState?.setColor(c);
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                    color: c, shape: BoxShape.circle, border: Border.all(color: _color == c ? accent : Colors.grey, width: _color == c ? 3 : 1)),
                              ),
                            ),
                          TextButton(
                            onPressed: () async {
                              final c = await showDialog<Color>(context: context, builder: (ctx) => ColorPickerDialog(initial: _color));
                              if (c != null) {
                                setState(() => _color = c);
                                _overlayKey.currentState?.setColor(c);
                              }
                            },
                            child: Text(l10n.commonCustom),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Text(l10n.widthLabel, style: const TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            key: const ValueKey<String>('annWidth'),
                            value: _width,
                            min: 2,
                            max: 40,
                            divisions: 38,
                            label: _width.round().toString(),
                            onChanged: (v) {
                              setState(() => _width = v);
                              _overlayKey.currentState?.setWidth(v);
                            },
                            onChangeEnd: (_) => _overlayKey.currentState?.endWidthAdjust(),
                          ),
                        ),
                        Text(_width.round().toString(), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(key: const ValueKey<String>('annUndo'), icon: const Icon(Icons.undo), onPressed: (ov?.canUndo ?? false) ? () => ov!.undo() : null),
                    IconButton(key: const ValueKey<String>('annRedo'), icon: const Icon(Icons.redo), onPressed: (ov?.canRedo ?? false) ? () => ov!.redo() : null),
                    IconButton(key: const ValueKey<String>('annClear'), icon: const Icon(Icons.delete_outline), onPressed: (ov != null && !ov.isEmpty) ? () => ov.clear() : null),
                    if (selected)
                      TextButton(key: const ValueKey<String>('annDeleteSelected'), onPressed: () => ov!.deleteSelected(), child: Text(l10n.commonDelete)),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      key: const ValueKey<String>('annConfirm'),
                      onPressed: _busy ? null : _confirm,
                      style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text(l10n.commonConfirm),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.b);
  final _Backdrop b;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(b.image, b.src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => old.b != b;
}
