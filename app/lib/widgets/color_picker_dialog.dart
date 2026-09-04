import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({super.key, required this.initial});
  final Color initial;
  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();
    return AlertDialog(
      title: Text(AppLocalizations.of(context).customColorTitle),
      content: SizedBox(
        width: 260,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 40, width: double.infinity, decoration: BoxDecoration(color: current, borderRadius: BorderRadius.circular(8))),
          const SizedBox(height: 12),
          _slider(AppLocalizations.of(context).hueLabel, _hsv.hue, 360, (v) => _hsv = _hsv.withHue(v)),
          _slider(AppLocalizations.of(context).satLabel, _hsv.saturation, 1, (v) => _hsv = _hsv.withSaturation(v)),
          _slider(AppLocalizations.of(context).valLabel, _hsv.value, 1, (v) => _hsv = _hsv.withValue(v)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
        ElevatedButton(onPressed: () => Navigator.pop(context, current), child: Text(AppLocalizations.of(context).commonUse)),
      ],
    );
  }

  Widget _slider(String label, double value, double max, ValueChanged<double> on) {
    return Row(children: [
      SizedBox(width: 34, child: Text(label, style: const TextStyle(fontSize: 11))),
      Expanded(child: Slider(value: value, min: 0, max: max, onChanged: (v) => setState(() => on(v)))),
    ]);
  }
}
