// Option dialogs for Print and Email. They only collect choices; the document
// tools mixin does the printing and sharing.
import 'package:flutter/material.dart';

import '../core/services/export_service.dart' show FilterType;
import '../core/services/print_service.dart';
import '../core/utils/page_range.dart';
import '../l10n/app_localizations.dart';

class PrintChoice {
  const PrintChoice({
    required this.indices,
    required this.filter,
    required this.paper,
    required this.margin,
    required this.fit,
    required this.perSheet,
  });

  /// Zero-based pages to print, or null for the whole document.
  final List<int>? indices;
  final FilterType filter;
  final PrintPaper paper;
  final PrintMargin margin;
  final PrintFit fit;
  final int perSheet;
}

class PrintOptionsDialog extends StatefulWidget {
  const PrintOptionsDialog({super.key, required this.pageCount, required this.currentIndex});
  final int pageCount;
  final int currentIndex;

  @override
  State<PrintOptionsDialog> createState() => _PrintOptionsDialogState();
}

class _PrintOptionsDialogState extends State<PrintOptionsDialog> {
  String _mode = 'all';
  FilterType _filter = FilterType.none;
  PrintPaper _paper = PrintPaper.a4;
  PrintMargin _margin = PrintMargin.none;
  PrintFit _fit = PrintFit.fit;
  int _perSheet = 1;
  final TextEditingController _range = TextEditingController();
  bool _rangeBad = false;

  @override
  void dispose() {
    _range.dispose();
    super.dispose();
  }

  String _filterName(AppLocalizations l10n, FilterType f) => switch (f) {
        FilterType.none => l10n.printFilterNone,
        FilterType.grayscale => l10n.filterGrayscale,
        FilterType.blackAndWhite => l10n.filterBlackAndWhite,
        FilterType.colorEnhance => l10n.filterColorEnhance,
        FilterType.magicColor => l10n.filterMagicColor,
        FilterType.shadowRemoval => l10n.filterShadowRemoval,
      };

  void _submit() {
    List<int>? indices;
    if (_mode == 'current') {
      indices = <int>[widget.currentIndex];
    } else if (_mode == 'range') {
      indices = parsePageRange(_range.text, widget.pageCount);
      if (indices == null) {
        setState(() => _rangeBad = true);
        return;
      }
    }
    Navigator.pop(
      context,
      PrintChoice(
        indices: indices,
        filter: _filter,
        paper: _paper,
        margin: _margin,
        fit: _fit,
        perSheet: _perSheet,
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _chips<T>(List<T> values, T selected, String Function(T) name, void Function(T) pick, String keyPrefix) => Wrap(
        spacing: 6,
        children: values
            .map((v) => ChoiceChip(
                  key: ValueKey<String>('$keyPrefix:${name(v)}'),
                  label: Text(name(v)),
                  selected: selected == v,
                  onSelected: (_) => setState(() => pick(v)),
                ))
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.printOptionsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chips<String>(
              const <String>['all', 'current', 'range'],
              _mode,
              (m) => m == 'all' ? l10n.printRangeAll : (m == 'current' ? l10n.printRangeCurrent : l10n.printRangeRange),
              (m) => _mode = m,
              'printMode',
            ),
            if (_mode == 'range')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  key: const ValueKey<String>('printRange'),
                  controller: _range,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    hintText: l10n.watermarkPagesRangeHint,
                    errorText: _rangeBad ? l10n.watermarkPagesInvalid(widget.pageCount) : null,
                  ),
                  onChanged: (_) {
                    if (_rangeBad) setState(() => _rangeBad = false);
                  },
                ),
              ),
            _label(l10n.printPaperLabel),
            _chips<PrintPaper>(
              PrintPaper.values,
              _paper,
              (v) => switch (v) {
                PrintPaper.a4 => 'A4',
                PrintPaper.a5 => 'A5',
                PrintPaper.letter => 'Letter',
                PrintPaper.legal => 'Legal',
              },
              (v) => _paper = v,
              'printPaper',
            ),
            _label(l10n.printMarginLabel),
            _chips<PrintMargin>(
              PrintMargin.values,
              _margin,
              (v) => switch (v) {
                PrintMargin.none => l10n.printMarginNone,
                PrintMargin.narrow => l10n.printMarginNarrow,
                PrintMargin.normal => l10n.printMarginNormal,
              },
              (v) => _margin = v,
              'printMargin',
            ),
            _label(l10n.printFitLabel),
            _chips<PrintFit>(
              PrintFit.values,
              _fit,
              (v) => v == PrintFit.fit ? l10n.printFitFit : l10n.printFitFill,
              (v) => _fit = v,
              'printFit',
            ),
            _label(l10n.printPerSheetLabel),
            _chips<int>(const <int>[1, 2, 4], _perSheet, (v) => '$v', (v) => _perSheet = v, 'printPerSheet'),
            const SizedBox(height: 8),
            DropdownButton<FilterType>(
              value: _filter,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              onChanged: (v) => setState(() => _filter = v!),
              items: FilterType.values.map((f) => DropdownMenuItem(value: f, child: Text(_filterName(l10n, f)))).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        TextButton(key: const ValueKey<String>('printGo'), onPressed: _submit, child: Text(l10n.commonPrint)),
      ],
    );
  }
}

class EmailChoice {
  const EmailChoice({required this.message, required this.targetMB});
  final String message;

  /// Size limit in MB for the PDF, or null for no limit.
  final int? targetMB;
}

class EmailOptionsDialog extends StatefulWidget {
  const EmailOptionsDialog({super.key, this.initialMessage = ''});
  final String initialMessage;

  @override
  State<EmailOptionsDialog> createState() => _EmailOptionsDialogState();
}

class _EmailOptionsDialogState extends State<EmailOptionsDialog> {
  late final TextEditingController _message = TextEditingController(text: widget.initialMessage);
  int? _mb;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.emailLabel),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey<String>('emailMessage'),
              controller: _message,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.emailMessageLabel, hintText: l10n.emailMessageHint),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(l10n.compressTargetLabel, style: Theme.of(context).textTheme.labelLarge),
            ),
            Wrap(
              spacing: 6,
              children: <int?>[null, 1, 2, 5]
                  .map((v) => ChoiceChip(
                        key: ValueKey<String>('emailTarget:${v ?? 0}'),
                        label: Text(v == null ? l10n.compressNoLimit : l10n.targetMbLabel(v)),
                        selected: _mb == v,
                        onSelected: (_) => setState(() => _mb = v),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        TextButton(
          key: const ValueKey<String>('emailGo'),
          onPressed: () => Navigator.pop(context, EmailChoice(message: _message.text.trim(), targetMB: _mb)),
          child: Text(l10n.commonShare),
        ),
      ],
    );
  }
}
