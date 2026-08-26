import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'package:image/image.dart' as img;
import '../core/services/export_service.dart' show FilterType;
import '../core/services/filter_service.dart';

Uint8List _previewFilterIsolate(Map<String, dynamic> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) return args['bytes'] as Uint8List;
  final filtered = FilterService.applyToImage(decoded, FilterType.values[args['filter'] as int]);
  return Uint8List.fromList(img.encodeJpg(filtered, quality: 85));
}

class FilterPreviewSheet extends StatefulWidget {
  const FilterPreviewSheet({super.key, required this.imagePath});
  final String imagePath;
  @override State<FilterPreviewSheet> createState() => _FilterPreviewSheetState();
}

class _FilterPreviewSheetState extends State<FilterPreviewSheet> {
  FilterType _selected = FilterType.none;
  Uint8List? _baseBytes; Uint8List? _previewBytes; bool _busy = false;

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
    final out = await compute(_previewFilterIsolate, {'bytes': _baseBytes, 'filter': f.index});
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
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Filter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))])),
          Expanded(child: _previewBytes == null ? const Center(child: CircularProgressIndicator()) : Center(child: Image.memory(_previewBytes!, fit: BoxFit.contain))),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: FilterType.values.map((f) {
            final label = f == FilterType.none ? 'Original' : f == FilterType.grayscale ? 'Grayscale' : f == FilterType.blackAndWhite ? 'B&W' : f == FilterType.colorEnhance ? 'Enhance' : 'Shadow';
            return ChoiceChip(label: Text(label), selected: _selected == f, onSelected: (_) => _select(f));
          }).toList()),
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), const SizedBox(width: 12),
            ElevatedButton(onPressed: () => Navigator.pop(context, _selected), style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Apply')),
          ])),
        ]),
      ),
    );
  }
}
