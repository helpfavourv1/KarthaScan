import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../core/utils/annotation_items.dart';

export '../core/utils/annotation_items.dart' show AnnotationMode;

/// The drawing surface of the annotate sheet.
///
/// Every mark is kept as its own item, so it can be selected, moved, recoloured,
/// resized or erased on its own. Undo and redo swap whole lists, so they cover
/// every kind of change the same way. Only the marks are exported (transparent
/// elsewhere); the page behind and the selection frame are drawn outside the
/// part that is exported.
class AnnotationOverlay extends StatefulWidget {
  const AnnotationOverlay({super.key, this.onChanged, this.paper = true, this.selectionColor = const Color(0xFF007AFF)});

  /// Called after anything the sheet shows changes (selection, undo state).
  final VoidCallback? onChanged;

  /// A white sheet behind the marks (no page to draw over).
  final bool paper;
  final Color selectionColor;

  @override
  State<AnnotationOverlay> createState() => AnnotationOverlayState();
}

class AnnotationOverlayState extends State<AnnotationOverlay> {
  final GlobalKey _boundaryKey = GlobalKey();
  List<AnnotationItem> _items = <AnnotationItem>[];
  final List<List<AnnotationItem>> _undo = <List<AnnotationItem>>[];
  final List<List<AnnotationItem>> _redo = <List<AnnotationItem>>[];
  AnnotationItem? _live;
  int? _selected;
  bool _gestureChanged = false;

  Color _currentColor = Colors.black;
  double _currentWidth = 4.0;
  AnnotationMode _mode = AnnotationMode.pen;

  AnnotationMode get mode => _mode;
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.length;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasSelection => _selected != null && _selected! < _items.length;
  AnnotationItem? get selectedItem => hasSelection ? _items[_selected!] : null;
  List<AnnotationItem> get items => List<AnnotationItem>.unmodifiable(_items);

  void _notify() => widget.onChanged?.call();

  /// Remembers the list as it is now, before a change, and forgets any redo.
  void _remember() {
    _undo.add(_items);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void clear() {
    if (_items.isEmpty) return;
    setState(() {
      _remember();
      _items = <AnnotationItem>[];
      _selected = null;
    });
    _notify();
  }

  void undo() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_items);
      _items = _undo.removeLast();
      _selected = null;
    });
    _notify();
  }

  void redo() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_items);
      _items = _redo.removeLast();
      _selected = null;
    });
    _notify();
  }

  void setMode(AnnotationMode mode) {
    setState(() {
      _mode = mode;
      _live = null;
      if (mode != AnnotationMode.select) _selected = null;
      if (mode == AnnotationMode.highlighter) {
        _currentColor = Colors.yellow;
        _currentWidth = 20.0;
      } else if (_mode == AnnotationMode.pen) {
        _currentColor = Colors.black;
        _currentWidth = 4.0;
      }
    });
    _notify();
  }

  /// With a mark selected the colour is applied to it (one undo step); otherwise
  /// it is the colour of the next marks.
  void setColor(Color color) {
    if (hasSelection) {
      final int i = _selected!;
      if (_items[i].color == color.toARGB32()) return;
      setState(() {
        _remember();
        _items = <AnnotationItem>[..._items]..[i] = _items[i].copyWith(color: color.toARGB32());
      });
    } else {
      setState(() => _currentColor = color);
    }
    _notify();
  }

  void setWidth(double width) {
    if (hasSelection) {
      final int i = _selected!;
      if (_items[i].width == width) return;
      setState(() {
        // A slider fires many times: one undo step for the whole drag.
        if (!_widthAdjusting) {
          _remember();
          _widthAdjusting = true;
        }
        _items = <AnnotationItem>[..._items]..[i] = _items[i].copyWith(width: width);
      });
    } else {
      setState(() => _currentWidth = width);
    }
    _notify();
  }

  bool _widthAdjusting = false;

  /// Call when the width slider is let go, so the next drag is a new undo step.
  void endWidthAdjust() => _widthAdjusting = false;

  void deleteSelected() {
    if (!hasSelection) return;
    setState(() {
      _remember();
      _items = <AnnotationItem>[..._items]..removeAt(_selected!);
      _selected = null;
    });
    _notify();
  }

  bool get _isShape =>
      _mode == AnnotationMode.rect || _mode == AnnotationMode.arrow || _mode == AnnotationMode.ellipse;
  bool get _isDrawing => _isShape || _mode == AnnotationMode.pen || _mode == AnnotationMode.highlighter;

  static const double _hitTolerance = 14;

  int? _hit(Offset p) {
    for (int i = _items.length - 1; i >= 0; i--) {
      if (annotationHit(_items[i], p, _hitTolerance)) return i;
    }
    return null;
  }

  void _eraseAt(Offset p) {
    final int? i = _hit(p);
    if (i == null) return;
    setState(() {
      if (!_gestureChanged) {
        _remember();
        _gestureChanged = true;
      }
      _items = <AnnotationItem>[..._items]..removeAt(i);
      _selected = null;
    });
    _notify();
  }

  void _onPanStart(DragStartDetails d) {
    final Offset p = d.localPosition;
    _gestureChanged = false;
    if (_isDrawing) {
      setState(() {
        _live = AnnotationItem(
          mode: _mode,
          color: _currentColor.toARGB32(),
          width: _currentWidth,
          points: <Offset>[p, if (_isShape) p],
        );
      });
    } else if (_mode == AnnotationMode.select) {
      final int? i = _hit(p);
      setState(() => _selected = i);
      _notify();
    } else if (_mode == AnnotationMode.eraser) {
      _eraseAt(p);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final Offset p = d.localPosition;
    if (_live != null) {
      setState(() {
        final List<Offset> pts = _live!.points;
        if (_isShape) {
          _live = _live!.copyWith(points: <Offset>[pts.first, p]);
        } else {
          _live = _live!.copyWith(points: <Offset>[...pts, p]);
        }
      });
    } else if (_mode == AnnotationMode.select && hasSelection) {
      setState(() {
        if (!_gestureChanged) {
          _remember();
          _gestureChanged = true;
        }
        final int i = _selected!;
        _items = <AnnotationItem>[..._items]..[i] = _items[i].moved(d.delta);
      });
    } else if (_mode == AnnotationMode.eraser) {
      _eraseAt(p);
    }
  }

  void _onPanEnd([DragEndDetails? _]) {
    if (_live != null) {
      final AnnotationItem done = _live!;
      setState(() {
        // A shape that was only tapped has no size: drop it.
        final bool empty = _isShape && (done.points.first - done.points.last).distance < 2;
        _live = null;
        if (!empty) {
          _remember();
          _items = <AnnotationItem>[..._items, done];
        }
      });
      _notify();
    }
    _gestureChanged = false;
  }

  void _onTapUp(TapUpDetails d) {
    final Offset p = d.localPosition;
    if (_mode == AnnotationMode.select) {
      setState(() => _selected = _hit(p));
      _notify();
    } else if (_mode == AnnotationMode.eraser) {
      _gestureChanged = false;
      _eraseAt(p);
      _gestureChanged = false;
    } else if (_mode == AnnotationMode.pen || _mode == AnnotationMode.highlighter) {
      // A tap leaves a dot.
      setState(() {
        _remember();
        _items = <AnnotationItem>[
          ..._items,
          AnnotationItem(mode: _mode, color: _currentColor.toARGB32(), width: _currentWidth, points: <Offset>[p]),
        ];
      });
      _notify();
    }
  }

  Future<Uint8List?> exportPng({double pixelRatio = 3}) async {
    if (isEmpty) return null;
    final RenderRepaintBoundary? boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final Widget stack = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        RepaintBoundary(
          key: _boundaryKey,
          child: CustomPaint(
            painter: _MarksPainter(_items, _live),
            size: Size.infinite,
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _SelectionPainter(selectedItem, widget.selectionColor),
            size: Size.infinite,
          ),
        ),
      ],
    );
    return Container(
      color: widget.paper ? Colors.white : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A line starts where the finger touched down, not where the drag was
        // recognised (about 18 px later), so the first part of a stroke is not lost.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanEnd,
        onTapUp: _onTapUp,
        child: stack,
      ),
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter(this.items, this.live);
  final List<AnnotationItem> items;
  final AnnotationItem? live;

  @override
  void paint(Canvas canvas, Size size) {
    for (final AnnotationItem i in items) {
      paintAnnotation(canvas, i);
    }
    if (live != null) paintAnnotation(canvas, live!);
  }

  @override
  bool shouldRepaint(covariant _MarksPainter old) => true;
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.item, this.color);
  final AnnotationItem? item;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (item == null) return;
    final Rect r = annotationBounds(item!).inflate(4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) => true;
}
