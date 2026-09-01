import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../core/models/scan_document.dart';
import 'color_picker_dialog.dart';
import 'text_stamp_sheet.dart';

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
  late String _centerMode;
  late Color _color;
  late double _fontSize;
  Uint8List? _imageBytes;
  Uint8List? _processedImageBytes;

  static const _swatches = [0xFFDD2222, 0xFF1F4E9C, 0xFF111111, 0xFF2E7D32];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _text = TextEditingController(text: i?.text ?? 'YOUR COMPANY');
    _subtext = TextEditingController(text: i?.sealSubtext ?? '');
    final c = i?.sealCenter ?? 'star';
    _centerMode = c == 'star' ? 'star' : (c == 'image' ? 'image' : (c.isEmpty ? 'none' : 'text'));
    _centerText = TextEditingController(text: (_centerMode == 'text') ? c : '');
    _shape = i?.sealShape ?? 'oval';
    _color = Color(i?.color ?? 0xFFDD2222);
    _fontSize = i?.fontSize ?? 40;
    _imageBytes = i?.sealImageBytes;
    _processedImageBytes = i?.sealImageBytes;
  }

  @override
  void dispose() {
    _text.dispose();
    _subtext.dispose();
    _centerText.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final rawBytes = await File(picked.path).readAsBytes();
    final processed = await _preRenderCircularImage(rawBytes);
    if (!mounted) return;
    setState(() {
      _imageBytes = rawBytes;
      _processedImageBytes = processed;
      _centerMode = 'image';
    });
  }

  /// Pre-renders the uploaded image into a circular-cropped PNG.
  /// This ensures drawSeal() receives a ready-to-draw image.
  Future<Uint8List> _preRenderCircularImage(Uint8List rawBytes) async {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    // Resize to 400x400 for quality
    const targetSize = 400;
    final resized = img.copyResize(decoded, width: targetSize, height: targetSize);

    // Apply circular mask
    final mask = img.Image(width: targetSize, height: targetSize);
    img.fill(mask, color: img.ColorRgb8(0, 0, 0));
    img.fillCircle(mask, x: targetSize ~/ 2, y: targetSize ~/ 2, radius: targetSize ~/ 2, color: img.ColorRgb8(255, 255, 255));

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final maskPixel = mask.getPixel(x, y);
        if (maskPixel.r.toInt() == 0) {
          resized.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
        }
      }
    }

    return Uint8List.fromList(img.encodePng(resized));
  }

  void _confirm() {
    final centerValue = _centerMode == 'star'
        ? 'star'
        : (_centerMode == 'image' ? 'image' : (_centerMode == 'text' ? _centerText.text.trim() : ''));
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
      sealImageBytesValue: _processedImageBytes,
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
                children: ['oval', 'rectangle'].map((sh) => ChoiceChip(
                      label: Text(sh == 'oval' ? 'Oval' : 'Box'),
                      selected: _shape == sh,
                      onSelected: (_) => setState(() => _shape = sh),
                    )).toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('Star'), selected: _centerMode == 'star', onSelected: (_) => setState(() => _centerMode = 'star')),
                  ChoiceChip(label: const Text('Text'), selected: _centerMode == 'text', onSelected: (_) => setState(() => _centerMode = 'text')),
                  ChoiceChip(label: const Text('Logo'), selected: _centerMode == 'image', onSelected: (_) => _pickImage()),
                  ChoiceChip(label: const Text('None'), selected: _centerMode == 'none', onSelected: (_) => setState(() => _centerMode = 'none')),
                ],
              ),
              if (_centerMode == 'text') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _centerText,
                  decoration: const InputDecoration(labelText: 'Center text', border: OutlineInputBorder()),
                ),
              ],
              if (_centerMode == 'image' && _imageBytes != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipOval(child: Image.memory(_imageBytes!, width: 48, height: 48, fit: BoxFit.cover)),
                    const SizedBox(width: 8),
                    const Text('Logo ready', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                  ],
                ),
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
