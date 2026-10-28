import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/services/signature_library.dart';
import '../core/utils/constants.dart';
import '../core/utils/typed_signature.dart';
import '../l10n/app_localizations.dart';
import 'signature_canvas.dart';

const List<int> _inkColors = <int>[0xFF000000, 0xFF1B3A8C, 0xFF0A4FD6, 0xFF7A1F1F];
const List<double> _penWidths = <double>[2, 3.5, 6];

/// Draw or type a signature. Returns the picture (transparent PNG, cut to the
/// ink) or null when skipped.
class InkSignatureSheet extends StatefulWidget {
  const InkSignatureSheet({super.key});

  @override
  State<InkSignatureSheet> createState() => InkSignatureSheetState();
}

class InkSignatureSheetState extends State<InkSignatureSheet> {
  final GlobalKey<SignatureCanvasState> _signatureKey = GlobalKey<SignatureCanvasState>();
  final TextEditingController _typed = TextEditingController();
  bool _typeMode = false;
  int _color = _inkColors.first;
  int _widthIndex = 1;
  String _font = typedSignatureFonts.first;
  bool _busy = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    if (_busy) return;
    setState(() => _busy = true);
    Uint8List? bytes;
    if (_typeMode) {
      bytes = await renderTypedSignature(_typed.text, fontFamily: _font, color: _color);
    } else {
      bytes = await _signatureKey.currentState?.exportPng();
    }
    if (!mounted) return;
    Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
                topRight: Radius.circular(AppShape.bottomSheetTopRadius),
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.signatureTitle,
                      style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<bool>(
                    key: const ValueKey<String>('sigMode'),
                    segments: <ButtonSegment<bool>>[
                      ButtonSegment<bool>(value: false, label: Text(l10n.signatureTabDraw), icon: const Icon(Icons.draw_outlined)),
                      ButtonSegment<bool>(value: true, label: Text(l10n.signatureTabType), icon: const Icon(Icons.keyboard_outlined)),
                    ],
                    selected: <bool>{_typeMode},
                    onSelectionChanged: (Set<bool> v) => setState(() => _typeMode = v.first),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_typeMode) ..._typeBody(l10n, textPrimary) else _drawBody(),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      for (final int c in _inkColors)
                        GestureDetector(
                          key: ValueKey<String>('sigColor:$c'),
                          onTap: () {
                            setState(() => _color = c);
                            _signatureKey.currentState?.setColor(Color(c));
                          },
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(color: _color == c ? accent : Colors.grey, width: _color == c ? 3 : 1),
                            ),
                          ),
                        ),
                      if (!_typeMode) ...[
                        const SizedBox(width: 8),
                        Text(l10n.signatureWidthLabel, style: TextStyle(color: textPrimary, fontSize: 12)),
                        for (int i = 0; i < _penWidths.length; i++)
                          ChoiceChip(
                            key: ValueKey<String>('sigWidth:$i'),
                            label: Container(
                              width: 22,
                              height: _penWidths[i],
                              decoration: BoxDecoration(color: textPrimary, borderRadius: BorderRadius.circular(4)),
                            ),
                            selected: _widthIndex == i,
                            onSelected: (_) {
                              setState(() => _widthIndex = i);
                              _signatureKey.currentState?.setWidth(_penWidths[i]);
                            },
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (!_typeMode) ...[
                        IconButton(
                          key: const ValueKey<String>('sigUndo'),
                          tooltip: l10n.undoTooltip,
                          onPressed: () => _signatureKey.currentState?.undo(),
                          icon: const Icon(Icons.undo),
                        ),
                        TextButton(
                          key: const ValueKey<String>('sigClear'),
                          onPressed: () => _signatureKey.currentState?.clear(),
                          child: Text(l10n.commonClear),
                        ),
                      ],
                      const Spacer(),
                      TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonSkip)),
                      const SizedBox(width: AppSpacing.xs),
                      ElevatedButton(
                        key: const ValueKey<String>('sigUse'),
                        style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                        onPressed: _use,
                        child: Text(l10n.commonUse),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawBody() {
    return SizedBox(
      height: 240,
      child: SignatureCanvas(
        key: _signatureKey,
        strokeColor: Color(_color),
        strokeWidth: _penWidths[_widthIndex],
      ),
    );
  }

  List<Widget> _typeBody(AppLocalizations l10n, Color textPrimary) {
    return <Widget>[
      TextField(
        key: const ValueKey<String>('sigTypeField'),
        controller: _typed,
        onChanged: (_) => setState(() {}),
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: l10n.signatureTypeHint),
      ),
      const SizedBox(height: AppSpacing.xs),
      Row(
        children: [
          for (final String f in typedSignatureFonts) ...[
            ChoiceChip(
              key: ValueKey<String>('sigFont:$f'),
              label: Text(f == 'DancingScript' ? l10n.signatureFontFlowing : l10n.signatureFontHandwritten),
              selected: _font == f,
              onSelected: (_) => setState(() => _font = f),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bgSecondaryLight,
          borderRadius: BorderRadius.circular(AppShape.cardRadius),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _typed.text.trim().isEmpty ? l10n.signatureCanvasHint : _typed.text.trim(),
              key: const ValueKey<String>('sigTypePreview'),
              style: TextStyle(fontFamily: _font, fontSize: 56, color: Color(_color)),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Lists the saved signatures so one can be reused. Pops the chosen picture,
/// or the string 'new' when the person wants to draw or type another.
class SignaturePickerSheet extends StatefulWidget {
  const SignaturePickerSheet({super.key, required this.library, required this.saved});
  final SignatureLibrary library;
  final List<SavedSignature> saved;

  @override
  State<SignaturePickerSheet> createState() => _SignaturePickerSheetState();
}

class _SignaturePickerSheetState extends State<SignaturePickerSheet> {
  late List<SavedSignature> _saved = widget.saved;

  Future<void> _delete(SavedSignature s) async {
    await widget.library.remove(s.id);
    if (!mounted) return;
    setState(() => _saved = _saved.where((x) => x.id != s.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
              topRight: Radius.circular(AppShape.bottomSheetTopRadius),
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.signatureSavedHeading,
                    style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                for (final SavedSignature s in _saved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            key: ValueKey<String>('savedSig:${s.id}'),
                            onTap: () => Navigator.pop(context, s.bytes),
                            child: Container(
                              height: 72,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.bgSecondaryLight,
                                borderRadius: BorderRadius.circular(AppShape.cardRadius),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Image.memory(s.bytes, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: ValueKey<String>('deleteSig:${s.id}'),
                          tooltip: l10n.signatureDeleteSaved,
                          onPressed: () => _delete(s),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                ElevatedButton.icon(
                  key: const ValueKey<String>('newSignature'),
                  style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context, 'new'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.signatureNewOne),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
