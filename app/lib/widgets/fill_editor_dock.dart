import 'package:flutter/material.dart';

import '../core/models/fill_snippet.dart';
import '../core/models/scan_document.dart';
import '../l10n/app_localizations.dart';
import 'color_picker_dialog.dart';

/// The bar that sits above the keyboard while typing Fill text.
///
/// The text shows on the page as it is typed (the page draws [draft] live); this
/// bar holds the text field, quick inserts, saved phrases and the style controls.
/// Every control is visible; nothing scrolls or hides.
class FillEditorDock extends StatefulWidget {
  const FillEditorDock({
    super.key,
    required this.draft,
    required this.snippets,
    required this.onChanged,
    required this.onDone,
    required this.onSaveSnippet,
    required this.onDeleteSnippet,
    required this.accent,
    required this.surface,
    required this.textPrimary,
  });

  final StampLayer draft;
  final List<FillSnippet> snippets;
  final ValueChanged<StampLayer> onChanged;
  final VoidCallback onDone;
  final void Function(String text) onSaveSnippet;
  final void Function(String snippetId) onDeleteSnippet;
  final Color accent;
  final Color surface;
  final Color textPrimary;

  static const List<int> swatches = <int>[0xFF111111, 0xFF1A44C2, 0xFFC62828, 0xFF2E7D32, 0xFF6A1B9A];
  static const List<String> fonts = <String>['sans-serif', 'serif', 'monospace', 'DancingScript', 'Caveat'];

  /// Today's date as DD-MM-YYYY, the same default the Date stamp uses.
  static String todayText([DateTime? now]) {
    final DateTime d = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  @override
  State<FillEditorDock> createState() => _FillEditorDockState();
}

class _FillEditorDockState extends State<FillEditorDock> {
  late final TextEditingController _controller = TextEditingController(text: widget.draft.text);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(FillEditorDock old) {
    super.didUpdateWidget(old);
    // A different box was opened: show its text.
    if (old.draft.id != widget.draft.id && _controller.text != widget.draft.text) {
      _controller.text = widget.draft.text;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _emit(StampLayer next) => widget.onChanged(next);

  void _insert(String text) {
    final TextSelection sel = _controller.selection;
    final String current = _controller.text;
    final int start = sel.isValid ? sel.start : current.length;
    final int end = sel.isValid ? sel.end : current.length;
    final String next = current.replaceRange(start, end, text);
    _controller.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + text.length));
    _emit(widget.draft.copyWith(text: next));
    _focus.requestFocus();
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool active = false, String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active ? widget.accent.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: active ? widget.accent : widget.textPrimary),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap, {VoidCallback? onLongPress}) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StampLayer d = widget.draft;
    final IconData alignIcon = d.align == 'center' ? Icons.format_align_center : (d.align == 'right' ? Icons.format_align_right : Icons.format_align_left);
    final String nextAlign = d.align == 'left' ? 'center' : (d.align == 'center' ? 'right' : 'left');
    final int fontIndex = FillEditorDock.fonts.indexOf(d.fontFamily);
    final String nextFont = FillEditorDock.fonts[(fontIndex + 1) % FillEditorDock.fonts.length];
    return Material(
      color: widget.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('fillTextField'),
                    controller: _controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 600,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.fillTypeHint,
                      isDense: true,
                      counterText: '',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (String v) => _emit(d.copyWith(text: v)),
                  ),
                ),
                const SizedBox(width: 4),
                _iconBtn(Icons.bookmark_add_outlined, () {
                  final String t = _controller.text.trim();
                  if (t.isNotEmpty) widget.onSaveSnippet(t);
                }, tooltip: l10n.fillSaveSnippet),
                const SizedBox(width: 2),
                IconButton.filled(
                  key: const ValueKey<String>('fillDone'),
                  onPressed: widget.onDone,
                  icon: const Icon(Icons.check),
                  tooltip: l10n.commonDone,
                  style: IconButton.styleFrom(backgroundColor: widget.accent, foregroundColor: Colors.white),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 6,
                runSpacing: 0,
                children: [
                  _chip(l10n.dateLabel, () => _insert(FillEditorDock.todayText())),
                  _chip('✓', () => _insert('✓')),
                  _chip('✗', () => _insert('✗')),
                  for (final FillSnippet s in widget.snippets)
                    _chip(s.label, () => _insert(s.text), onLongPress: () => widget.onDeleteSnippet(s.id)),
                ],
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              children: [
                _iconBtn(Icons.text_decrease, () => _emit(d.copyWith(fillSize: (d.fillSize / 1.1).clamp(0.008, 0.12))), tooltip: 'A−'),
                _iconBtn(Icons.text_increase, () => _emit(d.copyWith(fillSize: (d.fillSize * 1.1).clamp(0.008, 0.12))), tooltip: 'A+'),
                _iconBtn(Icons.width_normal, () => _emit(d.copyWith(boxWidth: (d.boxWidth - 0.05).clamp(0.1, 0.95))), tooltip: '←→'),
                _iconBtn(Icons.width_wide, () => _emit(d.copyWith(boxWidth: (d.boxWidth + 0.05).clamp(0.1, 0.95))), tooltip: '→←'),
                _iconBtn(Icons.format_bold, () => _emit(d.copyWith(fontWeight: d.fontWeight >= 700 ? 400 : 700)), active: d.fontWeight >= 700, tooltip: 'B'),
                _iconBtn(alignIcon, () => _emit(d.copyWith(align: nextAlign)), tooltip: 'Align'),
                _iconBtn(Icons.font_download_outlined, () => _emit(d.copyWith(fontFamily: nextFont)), tooltip: d.fontFamily),
                for (final int c in FillEditorDock.swatches)
                  GestureDetector(
                    onTap: () => _emit(d.copyWith(color: c)),
                    child: Container(
                      width: 26,
                      height: 26,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: d.color == c ? widget.accent : Colors.black26, width: d.color == c ? 3 : 1),
                      ),
                    ),
                  ),
                _iconBtn(Icons.palette_outlined, () async {
                  final Color? c = await showDialog<Color>(context: context, builder: (ctx) => ColorPickerDialog(initial: Color(d.color)));
                  if (c != null) _emit(d.copyWith(color: c.toARGB32()));
                }, tooltip: l10n.commonCustom),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
