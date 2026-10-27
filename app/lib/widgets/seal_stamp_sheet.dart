import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models/scan_document.dart';
import '../core/models/seal_design.dart';
import '../core/services/seal_library.dart';
import '../core/utils/seal_logo.dart';
import '../l10n/app_localizations.dart';
import 'color_picker_dialog.dart';
import 'seal_preview.dart';
import 'text_stamp_sheet.dart';

Uint8List _prepareLogoOff(List<Object> args) => prepareSealLogo(args[0] as Uint8List, removeWhite: args[1] as bool);

class SealStampSheet extends StatefulWidget {
  const SealStampSheet({super.key, this.initial, this.library});
  final StampLayer? initial;

  /// Injectable for tests.
  final SealLibrary? library;

  @override
  State<SealStampSheet> createState() => _SealStampSheetState();
}

class _SealStampSheetState extends State<SealStampSheet> {
  late final TextEditingController _text;
  late final TextEditingController _subtext;
  late final TextEditingController _centerText;
  late String _shape;
  late String _centerMode;
  late Color _color;
  int? _textColor;
  double _scale = 1.0;
  String _font = 'sans';
  bool _ink = false;
  bool _removeWhite = false;
  Uint8List? _rawLogo;
  Uint8List? _logo;
  List<SavedSeal> _saved = <SavedSeal>[];
  late final SealLibrary _library = widget.library ?? SealLibrary();

  static const List<int> _swatches = <int>[0xFFDD2222, 0xFF1F4E9C, 0xFF111111, 0xFF2E7D32];

  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final l10n = AppLocalizations.of(context);
    final i = widget.initial;
    _text = TextEditingController(text: i?.text ?? l10n.sealDefaultMainText);
    _subtext = TextEditingController(text: i?.sealSubtext ?? '');
    final c = i?.sealCenter ?? 'star';
    _centerMode = c == 'star' ? 'star' : (c == 'image' ? 'image' : (c.isEmpty ? 'none' : 'text'));
    _centerText = TextEditingController(text: (_centerMode == 'text') ? c : '');
    _shape = i?.sealShape == 'rectangle' ? 'rectangle' : (i?.sealShape == 'round' ? 'round' : 'oval');
    _color = Color(i?.color ?? 0xFFDD2222);
    _textColor = i?.sealTextColor;
    _scale = (i?.sealTextScale ?? 1.0).clamp(0.5, 1.0);
    _font = i?.sealFont ?? 'sans';
    _ink = i?.sealInk ?? false;
    _logo = i?.sealImageBytes;
    _library.load().then((List<SavedSeal> v) {
      if (mounted) setState(() => _saved = v);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _subtext.dispose();
    _centerText.dispose();
    super.dispose();
  }

  /// The centre value 'star' or 'image' means a mode, so typed text that is
  /// exactly one of those words gets an invisible character added.
  String _safeCenterText(String t) {
    final String lower = t.toLowerCase();
    return (lower == 'star' || lower == 'image') ? '$t​' : t;
  }

  String get _centerValue => _centerMode == 'star'
      ? 'star'
      : (_centerMode == 'image' ? 'image' : (_centerMode == 'text' ? _safeCenterText(_centerText.text.trim()) : ''));

  SealDesign _design() => SealDesign(
        text: _text.text.trim().isEmpty ? 'SEAL' : _text.text.trim(),
        subtext: _subtext.text.trim(),
        shape: _shape,
        center: _centerValue,
        logo: _centerMode == 'image' ? _logo : null,
        color: _color.toARGB32(),
        textColor: _textColor,
        textScale: _scale,
        font: _font,
        ink: _ink,
      );

  void _apply(SealDesign d) {
    setState(() {
      _text.text = d.text;
      _subtext.text = d.subtext;
      _shape = d.shape;
      _centerMode = d.center == 'star' ? 'star' : (d.center == 'image' ? 'image' : (d.center.isEmpty ? 'none' : 'text'));
      _centerText.text = _centerMode == 'text' ? d.center : '';
      _logo = d.logo;
      _rawLogo = null;
      _color = Color(d.color);
      _textColor = d.textColor;
      _scale = d.textScale.clamp(0.5, 1.0);
      _font = d.font;
      _ink = d.ink;
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final raw = await File(picked.path).readAsBytes();
    final processed = await compute(_prepareLogoOff, <Object>[raw, _removeWhite]);
    if (!mounted) return;
    setState(() {
      _rawLogo = raw;
      _logo = processed;
      _centerMode = 'image';
    });
  }

  Future<void> _reprocessLogo() async {
    final Uint8List? raw = _rawLogo;
    if (raw == null) return;
    final processed = await compute(_prepareLogoOff, <Object>[raw, _removeWhite]);
    if (mounted) setState(() => _logo = processed);
  }

  void _confirm() {
    final SealDesign d = _design();
    Navigator.pop(
      context,
      StampResult(
        bytes: Uint8List(0),
        label: AppLocalizations.of(context).sealCustom,
        widthFraction: 0.25,
        aspect: 1.0,
        text: d.text,
        fontSize: 40,
        color: d.color,
        sealShapeValue: d.shape,
        sealSubtextValue: d.subtext,
        sealCenterValue: d.center,
        sealImageBytesValue: d.logo,
        sealTextColorValue: d.textColor,
        sealTextScaleValue: d.textScale,
        sealFontValue: d.font,
        sealInkValue: d.ink,
      ),
    );
  }

  Future<void> _saveToLibrary() async {
    final List<SavedSeal> v = await _library.save(_design());
    if (!mounted) return;
    setState(() => _saved = v);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).sealSavedMessage), duration: const Duration(seconds: 2)));
  }

  Widget _swatch(int value, {required bool selected, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Color(value),
            shape: BoxShape.circle,
            border: Border.all(color: selected ? const Color(0xFF007AFF) : Colors.grey, width: selected ? 3 : 1),
          ),
        ),
      );

  Future<int?> _pickCustom(Color initial) => showDialog<Color>(
        context: context,
        builder: (ctx) => ColorPickerDialog(initial: initial),
      ).then((Color? c) => c?.toARGB32());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.initial != null;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final SealDesign design = _design();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? l10n.sealEditTitle : l10n.sealCreateTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              // Live preview on paper white, so the colours read as they will on a page.
              Center(
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.4))),
                  padding: const EdgeInsets.all(6),
                  child: SealPreview(design: design, size: 150),
                ),
              ),
              if (_saved.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(l10n.sealSavedHeading, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final SavedSeal s in _saved)
                        GestureDetector(
                          key: ValueKey('savedSeal:${s.id}'),
                          onTap: () => _apply(s.design),
                          onLongPress: () async {
                            final List<SavedSeal> v = await _library.delete(s.id);
                            if (mounted) setState(() => _saved = v);
                          },
                          child: Container(
                            width: 64,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.withValues(alpha: 0.4))),
                            child: SealPreview(design: s.design, size: 64),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sealMainText'),
                controller: _text,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n.sealMainTextLabel, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('sealSubText'),
                controller: _subtext,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n.sealSubtextLabel, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final String sh in <String>['oval', 'round', 'rectangle'])
                    ChoiceChip(
                      key: ValueKey('sealShape:$sh'),
                      label: Text(sh == 'oval' ? l10n.sealShapeOval : (sh == 'round' ? l10n.sealShapeRound : l10n.sealShapeBox)),
                      selected: _shape == sh,
                      onSelected: (_) => setState(() => _shape = sh),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: Text(l10n.sealCenterStar), selected: _centerMode == 'star', onSelected: (_) => setState(() => _centerMode = 'star')),
                  ChoiceChip(label: Text(l10n.sealCenterText), selected: _centerMode == 'text', onSelected: (_) => setState(() => _centerMode = 'text')),
                  ChoiceChip(
                    label: Text(l10n.sealCenterLogo),
                    selected: _centerMode == 'image',
                    onSelected: (_) {
                      if (_logo != null && _centerMode != 'image') {
                        setState(() => _centerMode = 'image');
                      } else {
                        _pickImage();
                      }
                    },
                  ),
                  ChoiceChip(label: Text(l10n.sealCenterNone), selected: _centerMode == 'none', onSelected: (_) => setState(() => _centerMode = 'none')),
                ],
              ),
              if (_centerMode == 'text') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _centerText,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: l10n.sealCenterTextLabel, border: const OutlineInputBorder()),
                ),
              ],
              if (_centerMode == 'image' && _logo != null)
                SwitchListTile(
                  key: const ValueKey('sealRemoveWhite'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.sealRemoveWhite, style: const TextStyle(fontSize: 13)),
                  value: _removeWhite,
                  onChanged: _rawLogo == null
                      ? null
                      : (bool v) {
                          setState(() => _removeWhite = v);
                          _reprocessLogo();
                        },
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(key: const ValueKey('sealFont:sans'), label: Text(l10n.sealFontSans), selected: _font == 'sans', onSelected: (_) => setState(() => _font = 'sans')),
                  ChoiceChip(key: const ValueKey('sealFont:serif'), label: Text(l10n.sealFontSerif), selected: _font == 'serif', onSelected: (_) => setState(() => _font = 'serif')),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text(l10n.commonColor, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                for (final int sw in _swatches) _swatch(sw, selected: _color.toARGB32() == sw, onTap: () => setState(() => _color = Color(sw))),
                TextButton(
                  onPressed: () async {
                    final int? c = await _pickCustom(_color);
                    if (c != null) setState(() => _color = Color(c));
                  },
                  child: Text(l10n.commonCustom),
                ),
              ]),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  Text(l10n.sealTextColorLabel, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: const ValueKey('sealTextColorSame'),
                    label: Text(l10n.sealTextColorSame),
                    selected: _textColor == null,
                    onSelected: (_) => setState(() => _textColor = null),
                  ),
                  const SizedBox(width: 8),
                  for (final int sw in _swatches) _swatch(sw, selected: _textColor == sw, onTap: () => setState(() => _textColor = sw)),
                  TextButton(
                    onPressed: () async {
                      final int? c = await _pickCustom(Color(_textColor ?? _color.toARGB32()));
                      if (c != null) setState(() => _textColor = c);
                    },
                    child: Text(l10n.commonCustom),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              Text(l10n.sealTextSizePercent((_scale * 100).round()), style: const TextStyle(fontSize: 12)),
              Slider(key: const ValueKey('sealTextSize'), value: _scale, min: 0.5, max: 1.0, onChanged: (v) => setState(() => _scale = v)),
              SwitchListTile(
                key: const ValueKey('sealInk'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.sealInkLook, style: const TextStyle(fontSize: 13)),
                value: _ink,
                onChanged: (bool v) => setState(() => _ink = v),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(key: const ValueKey('sealSave'), onPressed: _saveToLibrary, child: Text(l10n.sealSaveToLibrary)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
                const SizedBox(width: 12),
                ElevatedButton(
                  key: const ValueKey('sealConfirm'),
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEdit ? l10n.commonUpdate : l10n.commonCreate),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
