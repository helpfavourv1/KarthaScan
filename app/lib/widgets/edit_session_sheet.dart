import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/models/edit_session.dart';
import 'text_stamp_sheet.dart';

class EditSessionSheet extends StatefulWidget {
  const EditSessionSheet({super.key, required this.imagePath, required this.initialBytes, required this.initialLabel, required this.initialWidthFraction, required this.initialAspect});
  final String imagePath; final Uint8List initialBytes; final String initialLabel; final double initialWidthFraction; final double initialAspect;
  @override State<EditSessionSheet> createState() => _EditSessionSheetState();
}

class _EditSessionSheetState extends State<EditSessionSheet> {
  late final List<EditLayer> _layers;
  int _selected = 0;
  @override void initState() { super.initState(); _layers = [EditLayer(pngBytes: widget.initialBytes, label: widget.initialLabel, widthFraction: widget.initialWidthFraction, aspect: widget.initialAspect)]; }
  EditLayer get _current => _layers[_selected];

  Future<void> _addLayer(String kind) async {
    final stamp = await showModalBottomSheet<StampResult>(context: context, isScrollControlled: true, builder: (ctx) => TextStampSheet(kind: kind));
    if (stamp == null || !mounted) return;
    setState(() { _layers.add(EditLayer(pngBytes: stamp.bytes, label: stamp.label, widthFraction: stamp.widthFraction, aspect: stamp.aspect)); _selected = _layers.length - 1; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

    return SafeArea(
      child: Container(height: MediaQuery.of(context).size.height * 0.9, decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Edit Layers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))])),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth; final h = constraints.maxHeight;
            return Stack(children: [
              Positioned.fill(child: Image.file(File(widget.imagePath), fit: BoxFit.contain)),
              for (int i = 0; i < _layers.length; i++) ...[
                Positioned(
                  left: _layers[i].pctX * w - (w * _layers[i].widthFraction * _layers[i].scale) / 2,
                  top: _layers[i].pctY * h - (w * _layers[i].widthFraction * _layers[i].scale * _layers[i].aspect) / 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    onPanUpdate: (d) => setState(() { _layers[i].pctX = (_layers[i].pctX + d.delta.dx / w).clamp(0.0, 1.0); _layers[i].pctY = (_layers[i].pctY + d.delta.dy / h).clamp(0.0, 1.0); }),
                    child: Transform.rotate(angle: _layers[i].rotationDegrees * 3.14159 / 180, child: Opacity(opacity: _layers[i].opacity, child: Image.memory(_layers[i].pngBytes, width: w * _layers[i].widthFraction * _layers[i].scale))),
                  ),
                ),
              ],
            ]);
          }))),
          SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (int i = 0; i < _layers.length; i++) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text('${_layers[i].label} ${i + 1}'), selected: _selected == i, onSelected: (_) => setState(() => _selected = i))),
            ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Add'), onPressed: () => _showAddMenu()),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [const Text('Rotate', style: TextStyle(fontSize: 12)), Expanded(child: Slider(value: _current.rotationDegrees, min: -180, max: 180, onChanged: (v) => setState(() => _current.rotationDegrees = v))), Text('${_current.rotationDegrees.round()}°', style: const TextStyle(fontSize: 12))])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [const Text('Scale', style: TextStyle(fontSize: 12)), Expanded(child: Slider(value: _current.scale, min: 0.3, max: 2.5, onChanged: (v) => setState(() => _current.scale = v))), Text('${_current.scale.toStringAsFixed(2)}x', style: const TextStyle(fontSize: 12))])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [const Text('Opacity', style: TextStyle(fontSize: 12)), Expanded(child: Slider(value: _current.opacity, min: 0.05, max: 1.0, onChanged: (v) => setState(() => _current.opacity = v))), Text(_current.opacity.toStringAsFixed(2), style: const TextStyle(fontSize: 12))])),
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), const SizedBox(width: 12),
            ElevatedButton(onPressed: () => Navigator.pop(context, _layers), style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Confirm')),
          ])),
        ]),
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.title), title: const Text('Text'), onTap: () => Navigator.pop(ctx, 'text')),
      ListTile(leading: const Icon(Icons.note_outlined), title: const Text('Note'), onTap: () => Navigator.pop(ctx, 'note')),
      ListTile(leading: const Icon(Icons.date_range), title: const Text('Date'), onTap: () => Navigator.pop(ctx, 'date')),
      ListTile(leading: const Icon(Icons.check_box_outlined), title: const Text('Checkbox'), onTap: () => Navigator.pop(ctx, 'checkbox')),
    ]))).then((kind) { if (kind != null) _addLayer(kind); });
  }
}
