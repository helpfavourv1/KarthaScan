import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class StampResult {
  const StampResult({required this.bytes, required this.label, required this.widthFraction, required this.aspect});
  final Uint8List bytes;
  final String label;
  final double widthFraction;
  final double aspect;
}

class TextStampSheet extends StatefulWidget {
  const TextStampSheet({super.key, required this.kind});
  final String kind;
  @override
  State<TextStampSheet> createState() => _TextStampSheetState();
}

class _TextStampSheetState extends State<TextStampSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _checked = true;
  bool _busy = false;

  String get _title => widget.kind == 'text' ? 'Add Text' : widget.kind == 'note' ? 'Add Note' : widget.kind == 'date' ? 'Add Date' : 'Add Checkbox';

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<StampResult?> _generate() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (widget.kind == 'checkbox') {
      const double size = 240;
      final box = Paint()..color = const Color(0xFF111111)..style = PaintingStyle.stroke..strokeWidth = 16;
      canvas.drawRRect(ui.RRect.fromRectAndRadius(const Rect.fromLTWH(8, 8, size - 16, size - 16), const Radius.circular(24)), box);
      if (_checked) {
        final check = Paint()..color = const Color(0xFF007AFF)..style = PaintingStyle.stroke..strokeWidth = 24..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
        final path = Path()..moveTo(60, 130)..lineTo(105, 175)..lineTo(185, 75);
        canvas.drawPath(path, check);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(240, 240);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return StampResult(bytes: data.buffer.asUint8List(), label: 'Checkbox', widthFraction: 0.15, aspect: 1.0);
    }

    String text; Color bg; Color fg;
    if (widget.kind == 'date') {
      final d = DateTime.now();
      text = '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
      bg = const Color(0x00000000); fg = const Color(0xFF007AFF);
    } else if (widget.kind == 'note') {
      text = _controller.text.isEmpty ? 'Note' : _controller.text;
      bg = const Color(0xFFFFEB84); fg = const Color(0xFF3A3A3C);
    } else {
      text = _controller.text.isEmpty ? 'Text' : _controller.text;
      bg = const Color(0x00000000); fg = const Color(0xFF111111);
    }

    const double fontSize = 72;
    final paragraph = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.left, fontSize: fontSize, fontWeight: FontWeight.w700))
      ..pushStyle(ui.TextStyle(color: fg))..addText(text);
    final built = paragraph.build()..layout(const ui.ParagraphConstraints(width: 900));
    final double pad = widget.kind == 'note' ? 40 : 8;
    final int w = (built.longestLine + pad * 2).ceil();
    final int h = (built.height + pad * 2).ceil();
    if (bg.a > 0) {
      canvas.drawRRect(ui.RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), const Radius.circular(16)), Paint()..color = bg);
    }
    canvas.drawParagraph(built, Offset(pad, pad));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return StampResult(bytes: data.buffer.asUint8List(), label: widget.kind == 'note' ? 'Note' : widget.kind == 'date' ? 'Date' : 'Text', widthFraction: widget.kind == 'note' ? 0.45 : 0.5, aspect: h / w);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (widget.kind == 'text' || widget.kind == 'note')
              TextField(controller: _controller, maxLines: widget.kind == 'note' ? 3 : 1, decoration: InputDecoration(labelText: widget.kind == 'note' ? 'Note text' : 'Text', border: const OutlineInputBorder())),
            if (widget.kind == 'checkbox')
              CheckboxListTile(value: _checked, title: const Text('Ticked'), onChanged: (v) => setState(() => _checked = v ?? true)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _busy ? null : () async { setState(() => _busy = true); final r = await _generate(); if (context.mounted) Navigator.pop(context, r); },
                child: const Text('Create'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
