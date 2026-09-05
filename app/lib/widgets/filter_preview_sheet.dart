import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'package:image/image.dart' as img;
import '../core/services/export_service.dart' show FilterType;
import '../core/services/filter_service.dart';
import '../l10n/app_localizations.dart';

Uint8List _previewFilterIsolate(Map<String, dynamic> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) return args['bytes'] as Uint8List;
  final filtered = FilterService.applyToImage(decoded, FilterType.values[args['filter'] as int]);
  final double t = (args['intensity'] as double?) ?? 1.0;
  img.Image out = filtered;
  if (t != 1.0) {
    out = img.Image(width: filtered.width, height: filtered.height);
    for (int y = 0; y < filtered.height; y++) {
      for (int x = 0; x < filtered.width; x++) {
        final bp = decoded.getPixel(x, y);
        final fp = filtered.getPixel(x, y);
        final r = (bp.r.toInt() + (fp.r.toInt() - bp.r.toInt()) * t).clamp(0, 255).round();
        final g = (bp.g.toInt() + (fp.g.toInt() - bp.g.toInt()) * t).clamp(0, 255).round();
        final b = (bp.b.toInt() + (fp.b.toInt() - bp.b.toInt()) * t).clamp(0, 255).round();
        out.setPixelRgba(x, y, r, g, b, 255);
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

class _LeftClip extends CustomClipper<Rect> {
  _LeftClip(this.f);
  final double f;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(covariant _LeftClip oldClipper) => oldClipper.f != f;
}

class FilterPreviewSheet extends StatefulWidget {
  const FilterPreviewSheet({super.key, required this.imagePath});
  final String imagePath;
  @override State<FilterPreviewSheet> createState() => _FilterPreviewSheetState();
}

class _FilterPreviewSheetState extends State<FilterPreviewSheet> {
  FilterType _selected = FilterType.none;
  Uint8List? _baseBytes; Uint8List? _previewBytes; bool _busy = false;
  double _intensity = 1.0;
  double _splitX = 0.5;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes); if (decoded == null) return;
      final small = decoded.width > 600 ? img.copyResize(decoded, width: 600) : decoded;
      final base = Uint8List.fromList(img.encodeJpg(small, quality: 85));
      if (mounted) setState(() { _baseBytes = base; _previewBytes = base; });
    } catch (_) {}
  }

  Future<void> _select(FilterType f) async {
    if (_baseBytes == null || _busy) return;
    setState(() { _selected = f; _busy = true; });
    final out = await compute(_previewFilterIsolate, {'bytes': _baseBytes, 'filter': f.index, 'intensity': _intensity});
    if (mounted) setState(() { _previewBytes = out; _busy = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(height: MediaQuery.of(context).size.height * 0.8, decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(AppLocalizations.of(context).filterTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))])),
          Expanded(
          child: _previewBytes == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, cons) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) => setState(() => _splitX = (d.localPosition.dx / cons.maxWidth).clamp(0.0, 1.0)),
                      child: Stack(
                        children: [
                          Positioned.fill(child: Center(child: Image.memory(_previewBytes!, fit: BoxFit.contain))),
                          Positioned.fill(child: ClipRect(clipper: _LeftClip(_splitX), child: Center(child: Image.memory(_baseBytes!, fit: BoxFit.contain)))),
                          Positioned(left: cons.maxWidth * _splitX - 1, top: 0, bottom: 0, child: Container(width: 3, color: const Color(0xFF007AFF))),
                        ],
                      ),
                    );
                  },
                ),
        ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(AppLocalizations.of(context).intensityLabel, style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _intensity, min: 0.2, max: 2.0, divisions: 18,
                    label: _intensity.toStringAsFixed(1),
                    onChanged: (v) { setState(() => _intensity = v); _select(_selected); },
                    onChangeEnd: (_) => _select(_selected),
                  ),
                ),
                Text(_intensity.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: FilterType.values.map((f) {
            final chipLabel = f == FilterType.none ? AppLocalizations.of(context).filterOriginal : f == FilterType.grayscale ? AppLocalizations.of(context).filterGrayscale : f == FilterType.blackAndWhite ? AppLocalizations.of(context).filterBlackAndWhite : f == FilterType.colorEnhance ? AppLocalizations.of(context).filterColorEnhance : AppLocalizations.of(context).filterShadowRemoval;
            return ChoiceChip(label: Text(chipLabel), selected: _selected == f, onSelected: (_) => _select(f));
          }).toList()),
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)), const SizedBox(width: 12),
            ElevatedButton(onPressed: () => Navigator.pop(context, _selected), style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(AppLocalizations.of(context).commonApply)),
          ])),
        ]),
      ),
    );
  }
}
