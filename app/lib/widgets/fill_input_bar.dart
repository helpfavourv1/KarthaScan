import 'package:flutter/material.dart';
import '../core/models/fill_snippet.dart';
import '../l10n/app_localizations.dart';

class FillInputBar extends StatefulWidget {
  const FillInputBar({
    super.key,
    required this.initialText,
    required this.snippets,
    required this.onConfirm,
    required this.onCancel,
    required this.onTextChange,
    required this.onSaveSnippet,
    required this.onDeleteSnippet,
  });

  final String initialText;
  final List<FillSnippet> snippets;
  final void Function(String text, bool allCaps, int color, double fontSize) onConfirm;
  final VoidCallback onCancel;
  final ValueChanged<String> onTextChange;
  final void Function(String text) onSaveSnippet;
  final void Function(String snippetId) onDeleteSnippet;

  @override
  State<FillInputBar> createState() => _FillInputBarState();
}

class _FillInputBarState extends State<FillInputBar> {
  late final TextEditingController _controller;
  bool _allCaps = false;
  final int _color = 0xFF111111;
  double _fontSize = 40;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: _allCaps ? TextCapitalization.characters : TextCapitalization.none,
                onChanged: widget.onTextChange,
                decoration: InputDecoration(
                  hintText: l10n.fillInputHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_border),
              tooltip: l10n.fillSaveSnippet,
              onPressed: _controller.text.isNotEmpty ? () => widget.onSaveSnippet(_controller.text) : null,
            ),
            IconButton(icon: const Icon(Icons.check), onPressed: () => widget.onConfirm(_controller.text, _allCaps, _color, _fontSize)),
            IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text(l10n.fillCapsLabel, style: const TextStyle(fontSize: 12)),
            Switch(value: _allCaps, onChanged: (v) => setState(() => _allCaps = v)),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context).textFontLetterA, style: const TextStyle(fontSize: 12)),
            IconButton(icon: const Icon(Icons.remove, size: 16), onPressed: () => setState(() => _fontSize = (_fontSize - 4).clamp(12, 144))),
            Text('${_fontSize.round()}', style: const TextStyle(fontSize: 12)),
            IconButton(icon: const Icon(Icons.add, size: 16), onPressed: () => setState(() => _fontSize = (_fontSize + 4).clamp(12, 144))),
          ]),
          if (widget.snippets.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.snippets.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    label: Text(s.label),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.fillDeleteSnippet),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.commonDelete)),
                          ],
                        ),
                      );
                      if (confirm == true) widget.onDeleteSnippet(s.id);
                    },
                    onPressed: () { _controller.text = s.text; widget.onTextChange(s.text); },
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
