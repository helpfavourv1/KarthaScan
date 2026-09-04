import 'package:flutter/material.dart';
import 'annotation_overlay.dart';
import 'color_picker_dialog.dart';
import '../l10n/app_localizations.dart';

class AnnotateSheet extends StatefulWidget {
  const AnnotateSheet({super.key});
  @override
  State<AnnotateSheet> createState() => _AnnotateSheetState();
}

class _AnnotateSheetState extends State<AnnotateSheet> {
  final GlobalKey<AnnotationOverlayState> _overlayKey = GlobalKey();
  AnnotationMode _mode = AnnotationMode.pen;
  Color _color = Colors.black;
  double _width = 4.0;

  void _apply() {
    _overlayKey.currentState?.setColor(_color);
    _overlayKey.currentState?.setWidth(_width);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(AppLocalizations.of(context).annotateTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnnotationOverlay(key: _overlayKey),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: AnnotationMode.values.map((m) {
                  final icon = m == AnnotationMode.pen ? Icons.edit : m == AnnotationMode.highlighter ? Icons.highlight : m == AnnotationMode.rect ? Icons.crop_square : m == AnnotationMode.arrow ? Icons.arrow_forward : Icons.circle_outlined;
                  return ChoiceChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(m == AnnotationMode.pen ? AppLocalizations.of(context).annotationModePen : m == AnnotationMode.highlighter ? AppLocalizations.of(context).annotationModeHighlighter : m == AnnotationMode.rect ? AppLocalizations.of(context).annotationModeRect : m == AnnotationMode.arrow ? AppLocalizations.of(context).annotationModeArrow : AppLocalizations.of(context).annotationModeEllipse),
                    selected: _mode == m,
                    onSelected: (_) {
                      setState(() => _mode = m);
                      _overlayKey.currentState?.setMode(m);
                      _apply();
                    },
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final c in [Colors.black, Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.white])
                        GestureDetector(
                          onTap: () { setState(() => _color = c); _apply(); },
                          child: Container(
                            width: 28, height: 28, margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _color == c ? accent : Colors.grey, width: _color == c ? 3 : 1)),
                          ),
                        ),
                      TextButton(
                        onPressed: () async {
                          final c = await showDialog<Color>(context: context, builder: (ctx) => ColorPickerDialog(initial: _color));
                          if (c != null) { setState(() => _color = c); _apply(); }
                        },
                        child: Text(AppLocalizations.of(context).commonCustom),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(AppLocalizations.of(context).widthLabel, style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _width, min: 2, max: 20, divisions: 18,
                          label: _width.round().toString(),
                          onChanged: (v) { setState(() => _width = v); _apply(); },
                        ),
                      ),
                      Text(_width.round().toString(), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.undo), onPressed: () => _overlayKey.currentState?.undo()),
                  IconButton(icon: const Icon(Icons.redo), onPressed: () => _overlayKey.currentState?.redo()),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _overlayKey.currentState?.clear()),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final bytes = await _overlayKey.currentState?.exportPng();
                      if (!context.mounted) return;
                      if (bytes != null) Navigator.pop(context, bytes);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text(AppLocalizations.of(context).commonConfirm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
