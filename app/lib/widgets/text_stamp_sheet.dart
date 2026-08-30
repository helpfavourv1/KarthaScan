import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'color_picker_dialog.dart';
import '../core/models/scan_document.dart';

class StampResult {
  const StampResult({required this.bytes, required this.label, required this.widthFraction, required this.aspect, this.text = '', this.fontSize = 72, this.color = 0xFF111111, this.fontFamily = 'sans-serif', this.fontWeightValue = 700, this.alignName = 'left', this.halo = false, this.noteBgColorValue = 0xFFFFEB84, this.dateFormatValue = 'DD-MM-YYYY', this.customDateMillisValue = 0, this.checkedValue = true, this.checkShapeValue = 'rounded', this.boxColorValue = 0xFF111111, this.tickColorValue = 0xFF007AFF});
  final Uint8List bytes;
  final String label;
  final double widthFraction;
  final double aspect;
  final String text;
  final double fontSize;
  final int color;
  final String fontFamily;
  final int fontWeightValue;
  final String alignName;
  final bool halo;
  final int noteBgColorValue;
  final String dateFormatValue;
  final int customDateMillisValue;
  final bool checkedValue;
  final String checkShapeValue;
  final int boxColorValue;
  final int tickColorValue;
}

class TextStampSheet extends StatefulWidget {
  const TextStampSheet({super.key, required this.kind, this.initial});
  final String kind;
  final StampLayer? initial;
  @override
  State<TextStampSheet> createState() => _TextStampSheetState();
}

class _TextStampSheetState extends State<TextStampSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _checked = true;
  bool _busy = false;
  Color _textColor = const Color(0xFF111111);
  Color _noteBg = const Color(0xFFFFEB84);
  Color _boxColor = const Color(0xFF111111);
  Color _tickColor = const Color(0xFF007AFF);
  String _fontFamily = 'sans-serif';
  FontWeight _fontWeight = FontWeight.w700;
  TextAlign _align = TextAlign.left;
  bool _halo = false;
  DateTime _customDate = DateTime.now();
  String _dateFormat = 'DD-MM-YYYY';
  String _checkShape = 'rounded';

  String get _title => widget.kind == 'text' ? 'Add Text' : widget.kind == 'note' ? 'Add Note' : widget.kind == 'date' ? 'Add Date' : 'Add Checkbox';

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _controller.text = i.text;
      _textColor = Color(i.color);
      _fontFamily = i.fontFamily;
      _fontWeight = FontWeight.values.firstWhere((w) => w.value == i.fontWeight, orElse: () => FontWeight.w700);
      _align = i.align == 'left' ? TextAlign.left : (i.align == 'right' ? TextAlign.right : TextAlign.center);
      _halo = i.halo;
      _noteBg = Color(i.noteBgColor ?? 0xFFFFEB84);
      _dateFormat = i.dateFormat ?? 'DD-MM-YYYY';
      if (i.customDateMillis != null && i.customDateMillis! > 0) {
        _customDate = DateTime.fromMillisecondsSinceEpoch(i.customDateMillis!);
      }
      _checked = i.checked ?? true;
      _checkShape = i.checkShape ?? 'rounded';
      _boxColor = Color(i.boxColor ?? 0xFF111111);
      _tickColor = Color(i.tickColor ?? 0xFF007AFF);
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<Color?> _pick(Color initial) async => showDialog<Color>(context: context, builder: (ctx) => ColorPickerDialog(initial: initial));

  Future<StampResult?> _generate() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (widget.kind == 'checkbox') {
      const double size = 240;
      final box = Paint()..color = _boxColor..style = PaintingStyle.stroke..strokeWidth = 16;
      if (_checkShape == 'circle') {
        canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 16, box);
      } else {
        final radius = _checkShape == 'rounded' ? const Radius.circular(24) : Radius.zero;
        canvas.drawRRect(ui.RRect.fromRectAndRadius(const Rect.fromLTWH(8, 8, size - 16, size - 16), radius), box);
      }
      if (_checked) {
        final check = Paint()..color = _tickColor..style = PaintingStyle.stroke..strokeWidth = 24..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
        final path = Path()..moveTo(60, 130)..lineTo(105, 175)..lineTo(185, 75);
        canvas.drawPath(path, check);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(240, 240);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return StampResult(bytes: data.buffer.asUint8List(), label: 'Checkbox', widthFraction: 0.15, aspect: 1.0);
    }

    String text; Color bg;
    if (widget.kind == 'date') {
      final d = _customDate;
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      text = _dateFormat == 'DD-MM-YYYY' ? '$dd-$mm-${d.year}' : _dateFormat == 'MM-DD-YYYY' ? '$mm-$dd-${d.year}' : _dateFormat == 'YYYY-MM-DD' ? '${d.year}-$mm-$dd' : '${d.year}/$mm/$dd';
      bg = const Color(0x00000000);
    } else if (widget.kind == 'note') {
      text = _controller.text.isEmpty ? 'Note' : _controller.text;
      bg = _noteBg;
    } else {
      text = _controller.text.isEmpty ? 'Text' : _controller.text;
      bg = const Color(0x00000000);
    }

    const double fontSize = 72;
    ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: _align, fontSize: fontSize, fontWeight: _fontWeight, fontFamily: _fontFamily));
    if (_halo) {
      final haloPaint = Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
      builder.pushStyle(ui.TextStyle(foreground: haloPaint, fontSize: fontSize, fontWeight: _fontWeight, fontFamily: _fontFamily));
    } else {
      builder.pushStyle(ui.TextStyle(color: _textColor, fontSize: fontSize, fontWeight: _fontWeight, fontFamily: _fontFamily));
    }
    builder.addText(text);
    final built = builder.build()..layout(const ui.ParagraphConstraints(width: 900));
    final double pad = widget.kind == 'note' ? 40 : 8;
    final int w = (built.longestLine + pad * 2).ceil();
    final int h = (built.height + pad * 2).ceil();
    if (bg.a > 0) {
      canvas.drawRRect(ui.RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), const Radius.circular(16)), Paint()..color = bg);
    }
    if (_halo) {
      canvas.drawParagraph(built, Offset(pad, pad));
      final fillBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: _align, fontSize: fontSize, fontWeight: _fontWeight, fontFamily: _fontFamily))
        ..pushStyle(ui.TextStyle(color: _textColor, fontSize: fontSize, fontWeight: _fontWeight, fontFamily: _fontFamily))
        ..addText(text);
      final fillBuilt = fillBuilder.build()..layout(const ui.ParagraphConstraints(width: 900));
      canvas.drawParagraph(fillBuilt, Offset(pad, pad));
    } else {
      canvas.drawParagraph(built, Offset(pad, pad));
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return StampResult(bytes: data.buffer.asUint8List(), label: widget.kind == 'note' ? 'Note' : widget.kind == 'date' ? 'Date' : 'Text', widthFraction: widget.kind == 'note' ? 0.45 : 0.5, aspect: h / w, text: text, fontSize: fontSize, color: _textColor.toARGB32(), fontFamily: _fontFamily, fontWeightValue: _fontWeight.value, alignName: _align == TextAlign.left ? 'left' : (_align == TextAlign.right ? 'right' : 'center'), halo: _halo, noteBgColorValue: _noteBg.toARGB32(), dateFormatValue: _dateFormat, customDateMillisValue: _customDate.millisecondsSinceEpoch, checkedValue: _checked, checkShapeValue: _checkShape, boxColorValue: _boxColor.toARGB32(), tickColorValue: _tickColor.toARGB32());
  }

  Widget _swatch(Color c, Color current, ValueChanged<Color> on) => GestureDetector(
    onTap: () => on(c),
    child: Container(width: 28, height: 28, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: current == c ? const Color(0xFF007AFF) : Colors.grey, width: current == c ? 3 : 1))),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (widget.kind == 'text' || widget.kind == 'note')
                TextField(controller: _controller, maxLines: widget.kind == 'note' ? 3 : 1, decoration: InputDecoration(labelText: widget.kind == 'note' ? 'Note text' : 'Text', border: const OutlineInputBorder())),
              if (widget.kind == 'checkbox') ...[
                CheckboxListTile(value: _checked, title: const Text('Ticked'), onChanged: (v) => setState(() => _checked = v ?? true)),
                Wrap(spacing: 8, children: ['rounded', 'square', 'circle'].map((s) => ChoiceChip(label: Text(s), selected: _checkShape == s, onSelected: (_) => setState(() => _checkShape = s))).toList()),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Box', style: TextStyle(fontSize: 12)), const SizedBox(width: 8),
                  _swatch(const Color(0xFF111111), _boxColor, (c) => setState(() => _boxColor = c)),
                  _swatch(Colors.red, _boxColor, (c) => setState(() => _boxColor = c)),
                  _swatch(Colors.blue, _boxColor, (c) => setState(() => _boxColor = c)),
                  TextButton(onPressed: () async { final c = await _pick(_boxColor); if (c != null) setState(() => _boxColor = c); }, child: const Text('Custom')),
                ]),
                Row(children: [
                  const Text('Tick', style: TextStyle(fontSize: 12)), const SizedBox(width: 8),
                  _swatch(const Color(0xFF007AFF), _tickColor, (c) => setState(() => _tickColor = c)),
                  _swatch(Colors.black, _tickColor, (c) => setState(() => _tickColor = c)),
                  _swatch(Colors.green, _tickColor, (c) => setState(() => _tickColor = c)),
                  TextButton(onPressed: () async { final c = await _pick(_tickColor); if (c != null) setState(() => _tickColor = c); }, child: const Text('Custom')),
                ]),
              ],
              if (widget.kind == 'date') ...[
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: _customDate, firstDate: DateTime(1990), lastDate: DateTime(2100));
                    if (picked != null) setState(() => _customDate = picked);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF007AFF), width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_outlined, color: Color(0xFF007AFF), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${_customDate.day.toString().padLeft(2, '0')}-${_customDate.month.toString().padLeft(2, '0')}-${_customDate.year}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF007AFF)),
                        ),
                        const SizedBox(width: 8),
                        const Text('Change', style: TextStyle(fontSize: 11, color: Color(0xFF007AFF))),
                      ],
                    ),
                  ),
                ),
                Wrap(spacing: 8, children: ['DD-MM-YYYY', 'MM-DD-YYYY', 'YYYY-MM-DD', 'YYYY/MM/DD'].map((f) => ChoiceChip(label: Text(f, style: const TextStyle(fontSize: 10)), selected: _dateFormat == f, onSelected: (_) => setState(() => _dateFormat = f))).toList()),
              ],
              const SizedBox(height: 12),
              Row(children: [
                const Text('Color', style: TextStyle(fontSize: 12)), const SizedBox(width: 8),
                _swatch(const Color(0xFF111111), _textColor, (c) => setState(() => _textColor = c)),
                _swatch(Colors.white, _textColor, (c) => setState(() => _textColor = c)),
                _swatch(Colors.red, _textColor, (c) => setState(() => _textColor = c)),
                _swatch(Colors.blue, _textColor, (c) => setState(() => _textColor = c)),
                TextButton(onPressed: () async { final c = await _pick(_textColor); if (c != null) setState(() => _textColor = c); }, child: const Text('Custom')),
              ]),
              if (widget.kind == 'note')
                Row(children: [
                  const Text('Paper', style: TextStyle(fontSize: 12)), const SizedBox(width: 8),
                  _swatch(const Color(0xFFFFEB84), _noteBg, (c) => setState(() => _noteBg = c)),
                  _swatch(const Color(0xFFFFC9DE), _noteBg, (c) => setState(() => _noteBg = c)),
                  _swatch(const Color(0xFFC9E4FF), _noteBg, (c) => setState(() => _noteBg = c)),
                  _swatch(const Color(0xFFD3F8D9), _noteBg, (c) => setState(() => _noteBg = c)),
                  TextButton(onPressed: () async { final c = await _pick(_noteBg); if (c != null) setState(() => _noteBg = c); }, child: const Text('Custom')),
                ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: ['sans-serif', 'serif', 'monospace'].map((f) => ChoiceChip(label: Text(f), selected: _fontFamily == f, onSelected: (_) => setState(() => _fontFamily = f))).toList()),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [FontWeight.w400, FontWeight.w600, FontWeight.w700, FontWeight.w900].map((w) => ChoiceChip(label: Text(w.value.toString()), selected: _fontWeight == w, onSelected: (_) => setState(() => _fontWeight = w))).toList()),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [TextAlign.left, TextAlign.center, TextAlign.right].map((a) => ChoiceChip(label: Text(a == TextAlign.left ? 'L' : a == TextAlign.center ? 'C' : 'R'), selected: _align == a, onSelected: (_) => setState(() => _align = a))).toList()),
              SwitchListTile(title: const Text('White halo (readability)'), value: _halo, onChanged: (v) => setState(() => _halo = v)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _busy ? null : () async { setState(() => _busy = true); final r = await _generate(); if (!context.mounted) return; if (r != null) Navigator.pop(context, r); },
                  child: const Text('Create'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
