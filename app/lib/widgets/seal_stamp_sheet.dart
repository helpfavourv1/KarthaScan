import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/models/scan_document.dart';
import 'color_picker_dialog.dart';
import 'text_stamp_sheet.dart';

/// Custom Seal sheet — round (ring + curved arc text + star/text center)
/// or rectangle ("PAID"-style box). Returns a StampResult with seal recipe.
class SealStampSheet extends StatefulWidget {
  const SealStampSheet({super.key, this.initial});
  final StampLayer? initial;

  @override
  State<SealStampSheet> createState() => _SealStampSheetState();
}

class _SealStampSheetState extends State<SealStampSheet> {
  late final TextEditingController _text;
  late final TextEditingController _subtext;
  late final TextEditingController _centerText;
  late String _shape;
  late String _centerMode; // star | text | none
  late Color _color;
  late double _fontSize;

  static const _swatches = [0xFFDD2222, 0xFF1F4E9C, 0xFF111111, 0xFF2E7D32];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _text = TextEditingController(text: i?.text ?? 'YOUR COMPANY');
    _subtext = TextEditingController(text: i?.sealSubtext ?? '');
    final c = i?.sealCenter ?? 'star';
    _centerMode = c == 'star' ? 'star' : (c.isEmpty ? 'none' : 'text');
    _centerText = TextEditingController(text: _centerMode == 'text' ? c : '');
    _shape = i?.sealShape ?? 'round';
    _color = Color(i?.color ?? 0xFFDD2222);
    _fontSize = i?.fontSize ?? 40;
  }

  @override
  void dispose() {
    _text.dispose();
    _subtext.dispose();
    _centerText.dispose();
    super.dispose();
  }

  void _confirm() {
    final centerValue = _centerMode == 'star'
        ? 'star'
        : (_centerMode == 'text' ? _centerText.text.trim() : '');
    Navigator.pop(context, StampResult(
      bytes: Uint8List(0),
      label: 'Custom Seal',
      widthFraction: 0.25,
      aspect: 1.0,
      text: _text.text.trim().isEmpty ? 'SEAL' : _text.text.trim(),
      fontSize: _fontSize,
      color: _color.toARGB32(),
      sealShapeValue: _shape,
      sealSubtextValue: _subtext.text.trim(),
      sealCenterValue: centerValue,
    ));
  }

  Widget _swatch(int value) => GestureDetector(
        onTap: () => setState(() => _color = Color(value)),
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Color(value),
            shape: BoxShape.circle,
            border: Border.all(
              color: _color.toARGB32() == value ? const Color(0xFF007AFF) : Colors.grey,
              width: _color.toARGB32() == value ? 3 : 1,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Edit Custom Seal' : 'Custom Seal',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                decoration: const InputDecoration(
                  labelText: 'Main text (top arc / box)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _subtext,
                decoration: const InputDecoration(
                  labelText: 'Subtext (bottom arc / below)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['round', 'rectangle'].map((sh) => ChoiceChip(
                      label: Text(sh == 'round' ? 'Round' : 'Box'),
                      selected: _shape == sh,
                      onSelected: (_) => setState(() => _shape = sh),
                    )).toList(),
              ),
              const SizedBox(height: 8),
              if (_shape == 'round') ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(label: const Text('Star center'), selected: _centerMode == 'star', onSelected: (_) => setState(() => _centerMode = 'star')),
                    ChoiceChip(label: const Text('Text center'), selected: _centerMode == 'text', onSelected: (_) => setState(() => _centerMode = 'text')),
                    ChoiceChip(label: const Text('No center'), selected: _centerMode == 'none', onSelected: (_) => setState(() => _centerMode = 'none')),
                  ],
                ),
                if (_centerMode == 'text') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _centerText,
                    decoration: const InputDecoration(labelText: 'Center text', border: OutlineInputBorder()),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Row(children: [
                const Text('Color', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                for (final sw in _swatches) _swatch(sw),
                TextButton(
                  onPressed: () async {
                    final c = await showDialog<Color>(
                      context: context,
                      builder: (ctx) => ColorPickerDialog(initial: _color),
                    );
                    if (c != null) setState(() => _color = c);
                  },
                  child: const Text('Custom'),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Text size: ${_fontSize.round()}', style: const TextStyle(fontSize: 12)),
              Slider(
                value: _fontSize,
                min: 24,
                max: 96,
                onChanged: (v) => setState(() => _fontSize = v),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEdit ? 'Update' : 'Create'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
