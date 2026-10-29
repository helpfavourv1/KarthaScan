import '../core/utils/smooth_resize.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'package:image/image.dart' as img;
import '../core/services/export_service.dart' show FilterType;
import '../core/services/filter_service.dart';
import '../core/models/page_transform.dart';
import '../l10n/app_localizations.dart';
import 'document_canvas.dart' show PagePreviewJob, renderPagePreview;

/// What the filter sheet returns: the chosen filter, how strong it is, the
/// brightness and contrast, and whether to use them on every page.
class FilterChoice {
  const FilterChoice(this.filter, this.intensity, {this.brightness = 0, this.contrast = 0, this.applyAll = false});
  final FilterType filter;
  final double intensity;
  final double brightness;
  final double contrast;
  final bool applyAll;
}

Uint8List _previewFilterIsolate(Map<String, dynamic> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) return args['bytes'] as Uint8List;
  final double t = (args['intensity'] as double?) ?? 1.0;
  img.Image out = FilterService.applyToImage(decoded, FilterType.values[args['filter'] as int], intensity: t);
  out = FilterService.adjust(out, brightness: (args['brightness'] as double?) ?? 0, contrast: (args['contrast'] as double?) ?? 0);
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

/// The page as it is after crop, tilt and resize (no filter), small, so the
/// preview shows the same picture the export will filter.
Uint8List? _previewBaseIsolate(Map<String, dynamic> args) {
  final PageTransform t = (args['transform'] as PageTransform).copyWith(filter: FilterType.none, brightness: 0, contrast: 0);
  final Uint8List? full = renderPagePreview(PagePreviewJob(args['bytes'] as Uint8List, t));
  if (full == null) return null;
  final img.Image? im = img.decodeImage(full);
  if (im == null) return full;
  final img.Image small = im.width >= im.height
      ? (im.width > 700 ? resizeSmooth(im, width: 700) : im)
      : (im.height > 700 ? resizeSmooth(im, height: 700) : im);
  return Uint8List.fromList(img.encodeJpg(small, quality: 88));
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
  const FilterPreviewSheet({super.key, required this.imagePath, this.transform, this.pageCount = 1});
  final String imagePath;

  /// What the page already has (crop, tilt, filter...). The preview is built from it.
  final PageTransform? transform;
  final int pageCount;
  @override State<FilterPreviewSheet> createState() => _FilterPreviewSheetState();
}

class _FilterPreviewSheetState extends State<FilterPreviewSheet> {
  late FilterType _selected = widget.transform?.filter ?? FilterType.none;
  Uint8List? _baseBytes; Uint8List? _previewBytes; bool _busy = false;
  late double _intensity = widget.transform?.filterIntensity ?? 1.0;
  late double _brightness = widget.transform?.brightness ?? 0;
  late double _contrast = widget.transform?.contrast ?? 0;
  bool _applyAll = false;
  bool _again = false;
  double _splitX = 0.5;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final Uint8List? base = await compute(_previewBaseIsolate, {'bytes': bytes, 'transform': widget.transform ?? const PageTransform()});
      if (base == null) return;
      if (mounted) setState(() { _baseBytes = base; _previewBytes = base; });
      if (mounted) _render();
    } catch (_) {}
  }

  void _select(FilterType f) {
    setState(() => _selected = f);
    _render();
  }

  /// Draws the preview for the current settings. If settings change while a
  /// picture is being made, one more is made afterwards, so the final setting
  /// is always the one shown.
  Future<void> _render() async {
    if (_baseBytes == null) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final out = await compute(_previewFilterIsolate, {
          'bytes': _baseBytes,
          'filter': _selected.index,
          'intensity': _intensity,
          'brightness': _brightness,
          'contrast': _contrast,
        });
        if (mounted) setState(() => _previewBytes = out);
      } while (_again && mounted);
    } finally {
      _busy = false;
    }
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
                    onChanged: (v) { setState(() => _intensity = v); _render(); },
                  ),
                ),
                Text(_intensity.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          _slider(AppLocalizations.of(context).filterBrightnessLabel, const Key('brightnessSlider'), _brightness, (v) { setState(() => _brightness = v); _render(); }),
          _slider(AppLocalizations.of(context).filterContrastLabel, const Key('contrastSlider'), _contrast, (v) { setState(() => _contrast = v); _render(); }),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: FilterType.values.map((f) {
            final chipLabel = f == FilterType.none ? AppLocalizations.of(context).filterOriginal : f == FilterType.grayscale ? AppLocalizations.of(context).filterGrayscale : f == FilterType.blackAndWhite ? AppLocalizations.of(context).filterBlackAndWhite : f == FilterType.colorEnhance ? AppLocalizations.of(context).filterColorEnhance : f == FilterType.magicColor ? AppLocalizations.of(context).filterMagicColor : AppLocalizations.of(context).filterShadowRemoval;
            return ChoiceChip(label: Text(chipLabel), selected: _selected == f, key: Key('filter:${f.name}'), onSelected: (_) => _select(f));
          }).toList()),
          if (widget.pageCount > 1)
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                key: const Key('filterApplyAll'),
                dense: true,
                title: Text(AppLocalizations.of(context).applyToAllPages),
                value: _applyAll,
                onChanged: (v) => setState(() => _applyAll = v),
              ),
            ),
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)), const SizedBox(width: 12),
            ElevatedButton(onPressed: () => Navigator.pop(context, FilterChoice(_selected, _intensity, brightness: _brightness, contrast: _contrast, applyAll: _applyAll)), style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(AppLocalizations.of(context).commonApply)),
          ])),
        ]),
      ),
    );
  }

  Widget _slider(String label, Key key, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(child: Slider(key: key, value: value, min: -1, max: 1, divisions: 40, label: value.toStringAsFixed(2), onChanged: onChanged)),
        SizedBox(width: 36, child: Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 12))),
      ]),
    );
  }
}
