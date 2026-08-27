import 'dart:io';

import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'package:image/image.dart' as img;


enum RotateResizeMode { rotate, resize }

class RotateResizeSheet extends StatefulWidget {
  const RotateResizeSheet({
    super.key,
    required this.mode,
    required this.imagePath,
    this.onApplyAll,
  });

  final RotateResizeMode mode;
  final String imagePath;
  final ValueChanged<bool>? onApplyAll;

  @override
  State<RotateResizeSheet> createState() => RotateResizeSheetState();
}

class RotateResizeSheetState extends State<RotateResizeSheet> {
  int _quarterTurns = 0;
  bool _applyAll = false;
  img.Image? _originalImage;
  bool _loading = true;
  final TextEditingController _widthCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  bool _aspectLock = true;
  double _origAspect = 1.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      _originalImage = img.decodeImage(bytes);
      if (_originalImage != null) {
        _widthCtrl.text = _originalImage!.width.toString();
        _heightCtrl.text = _originalImage!.height.toString();
        _origAspect = _originalImage!.width / _originalImage!.height;
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final textSecondary = isDark ? const Color(0xFF8E8E93) : const Color(0xFF3A3A3C);
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.mode == RotateResizeMode.rotate ? 'Rotate' : 'Resize',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: _loading || _originalImage == null
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: widget.mode == RotateResizeMode.rotate
                            ? _buildRotatePreview(textSecondary)
                            : _buildResizePreview(textSecondary, accent),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (widget.mode == RotateResizeMode.rotate) {
                        widget.onApplyAll?.call(_applyAll);
                        Navigator.pop(context, _quarterTurns);
                      } else {
                        final w = int.tryParse(_widthCtrl.text) ?? _originalImage!.width;
                        final h = int.tryParse(_heightCtrl.text) ?? _originalImage!.height;
                        Navigator.pop(context, (w, h));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotatePreview(Color textSecondary) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: _quarterTurns,
            child: Image.file(File(widget.imagePath), fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 16),
        Text('${_quarterTurns * 90}°', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textSecondary)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
          icon: const Icon(Icons.rotate_90_degrees_ccw),
          label: const Text('Rotate 90°'),
        ),
        SwitchListTile(
          title: const Text('Apply to all pages'),
          value: _applyAll,
          onChanged: (v) => setState(() => _applyAll = v),
        ),
      ],
    );
  }

  Widget _buildResizePreview(Color textSecondary, Color accent) {
    final origW = _originalImage!.width;
    final origH = _originalImage!.height;
    final newW = int.tryParse(_widthCtrl.text) ?? origW;
    final newH = int.tryParse(_heightCtrl.text) ?? origH;
    final origBytes = File(widget.imagePath).lengthSync();
    final ratio = (newW * newH) / (origW * origH);
    final estBytes = (origBytes * ratio).round();
    final estMB = (estBytes / (1024 * 1024)).toStringAsFixed(2);
    final pctChange = ((ratio - 1) * 100).round();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: Image.file(File(widget.imagePath), fit: BoxFit.contain)),
        const SizedBox(height: 16),
        Text('Original: $origW×$origH', style: TextStyle(fontSize: 14, color: textSecondary)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: _widthCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Width', border: OutlineInputBorder()),
                onChanged: (v) {
                  setState(() {});
                  if (_aspectLock) {
                    final w = int.tryParse(v);
                    if (w != null) _heightCtrl.text = (w / _origAspect).round().toString();
                  }
                },
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _heightCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Height', border: OutlineInputBorder()),
                onChanged: (v) {
                  setState(() {});
                  if (_aspectLock) {
                    final h = int.tryParse(v);
                    if (h != null) _widthCtrl.text = (h * _origAspect).round().toString();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Lock aspect ratio'),
          value: _aspectLock,
          onChanged: (v) => setState(() => _aspectLock = v),
        ),
        Wrap(spacing: 8, children: [
          for (final pct in [0.25, 0.5, 0.75])
            ChoiceChip(
              label: Text('${(pct * 100).round()}%'),
              selected: false,
              onSelected: (_) => setState(() {
                _widthCtrl.text = (origW * pct).round().toString();
                _heightCtrl.text = (origH * pct).round().toString();
              }),
            ),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: pctChange < 0 ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '≈ $estMB MB (${pctChange > 0 ? '+' : ''}$pctChange%)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pctChange < 0 ? Colors.green : Colors.orange),
          ),
        ),
      ],
    );
  }
}
