import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../core/models/scan_document.dart';
import 'color_picker_dialog.dart';
import 'text_stamp_sheet.dart';
import '../l10n/app_localizations.dart';

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

  bool _controllersInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controllersInitialized) return;
    _controllersInitialized = true;
    final l10n = AppLocalizations.of(context);
    final i = widget.initial;
    _text = TextEditingController(text: i?.text ?? l10n.sealDefaultMainText);
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
    final processed = await compute(_renderCircularLogo, rawBytes);
    if (!mounted) return;
    setState(() {
      _imageBytes = rawBytes;
      _processedImageBytes = processed;
      _centerMode = 'image';
    });
  }

  /// The centre value 'star' or 'image' means a mode, so typed text that is
  /// exactly one of those words gets an invisible character added.
  String _safeCenterText(String t) {
    final String lower = t.toLowerCase();
    return (lower == 'star' || lower == 'image') ? '$t\u200B' : t;
  }

  void _confirm() {
    final centerValue = _centerMode == 'star'
        ? 'star'
        : (_centerMode == 'image' ? 'image' : (_centerMode == 'text' ? _safeCenterText(_centerText.text.trim()) : ''));
    Navigator.pop(context, StampResult(
      bytes: Uint8List(0),
      label: AppLocalizations.of(context).sealCustom,
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
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? AppLocalizations.of(context).sealEditTitle : AppLocalizations.of(context).sealCreateTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).sealMainTextLabel,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _subtext,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).sealSubtextLabel,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['oval', 'rectangle'].map((sh) => ChoiceChip(
                      label: Text(sh == 'oval' ? AppLocalizations.of(context).sealShapeOval : AppLocalizations.of(context).sealShapeBox),
                      selected: _shape == sh,
                      onSelected: (_) => setState(() => _shape = sh),
                    )).toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: Text(AppLocalizations.of(context).sealCenterStar), selected: _centerMode == 'star', onSelected: (_) => setState(() => _centerMode = 'star')),
                  ChoiceChip(label: Text(AppLocalizations.of(context).sealCenterText), selected: _centerMode == 'text', onSelected: (_) => setState(() => _centerMode = 'text')),
                  ChoiceChip(label: Text(AppLocalizations.of(context).sealCenterLogo), selected: _centerMode == 'image', onSelected: (_) { if (_imageBytes != null && _centerMode != 'image') { setState(() => _centerMode = 'image'); } else { _pickImage(); } }),
                  ChoiceChip(label: Text(AppLocalizations.of(context).sealCenterNone), selected: _centerMode == 'none', onSelected: (_) => setState(() => _centerMode = 'none')),
                ],
              ),
              if (_centerMode == 'text') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _centerText,
                  decoration: InputDecoration(labelText: AppLocalizations.of(context).sealCenterTextLabel, border: OutlineInputBorder()),
                ),
              ],
              if (_centerMode == 'image' && _imageBytes != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipOval(child: Image.memory(_imageBytes!, width: 48, height: 48, fit: BoxFit.cover)),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context).sealLogoReady, style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Text(AppLocalizations.of(context).commonColor, style: TextStyle(fontSize: 12)),
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
                  child: Text(AppLocalizations.of(context).commonCustom),
                ),
              ]),
              const SizedBox(height: 8),
              Text(AppLocalizations.of(context).textSizeLabel(_fontSize.round()), style: const TextStyle(fontSize: 12)),
              Slider(
                value: _fontSize,
                min: 24,
                max: 96,
                onChanged: (v) => setState(() => _fontSize = v),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEdit ? AppLocalizations.of(context).commonUpdate : AppLocalizations.of(context).commonCreate),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

  /// Pre-renders the uploaded image into a circular-cropped PNG.
  /// This ensures drawSeal() receives a ready-to-draw image.
Uint8List _renderCircularLogo(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    // Center-crop to the largest square first (no stretching), then resize.
    const targetSize = 400;
    final side = decoded.width < decoded.height ? decoded.width : decoded.height;
    final cropped = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = img.copyResize(cropped, width: targetSize, height: targetSize);

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

