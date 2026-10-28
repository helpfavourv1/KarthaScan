import '../core/utils/smooth_resize.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/models/scan_document.dart';
import '../core/utils/page_range.dart';
import '../core/models/signature_placement.dart';
import '../core/utils/constants.dart';
import 'color_picker_dialog.dart';
import '../l10n/app_localizations.dart';

/// Rich watermark styling sheet. Returns a WatermarkLayer with pageIndex=0
/// and placement at center (caller sets actual pageIndex + placement).
/// [initialConfig] enables edit mode (pre-filled values).
class WatermarkSheet extends StatefulWidget {
  const WatermarkSheet({super.key, this.initialConfig, this.pages, this.pageCount = 0, this.pickImage, this.logoDirectory});
  final WatermarkLayer? initialConfig;

  /// When given (adding a watermark), the sheet offers a page choice and writes it
  /// here: 'current', 'all', or a typed range such as "1-3, 5".
  final ValueNotifier<String>? pages;
  final int pageCount;

  /// Picks the logo picture (the gallery by default). Tests pass their own.
  final Future<Uint8List?> Function()? pickImage;

  /// Where chosen logos are kept (the app's folder by default).
  final Future<Directory> Function()? logoDirectory;

  @override
  State<WatermarkSheet> createState() => _WatermarkSheetState();
}

class _WatermarkSheetState extends State<WatermarkSheet> {
  late final TextEditingController _textController;
  bool _needsDefaultText = false;
  late double _opacity;
  late double _fontSize;
  late int _color;
  late String _fontFamily;
  late bool _bold;
  late bool _italic;
  late bool _underline;
  late int? _outlineColor;
  late double _outlineWidth;
  late double _shadowOffsetX;
  late double _shadowOffsetY;
  late int? _shadowColor;
  late String _align;
  late String _layout;
  String? _imagePath;
  bool _imageMode = false;
  String _pagesChoice = 'current';
  final TextEditingController _rangeController = TextEditingController();
  String? _rangeError;
  bool _busy = false;

  static const _swatches = [
    0xFF8E8E93,
    0xFF000000,
    0xFFFF3B30,
    0xFF007AFF,
    0xFF34C759,
    0xFFFF9500,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsDefaultText) {
      _needsDefaultText = false;
      _textController.text = AppLocalizations.of(context).watermarkDefaultText;
    }
  }

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _textController = TextEditingController(text: c?.text ?? '');
    _needsDefaultText = c?.text == null;
    _opacity = c?.opacity ?? 0.15;
    _fontSize = c?.fontSize ?? 48;
    _color = c?.color ?? 0xFF8E8E93;
    _fontFamily = c?.fontFamily ?? 'sans-serif';
    _bold = c?.bold ?? true;
    _italic = c?.italic ?? false;
    _underline = c?.underline ?? false;
    _outlineColor = c?.outlineColor;
    _outlineWidth = c?.outlineWidth ?? 0;
    _shadowOffsetX = c?.shadowOffsetX ?? 0;
    _shadowOffsetY = c?.shadowOffsetY ?? 0;
    _shadowColor = c?.shadowColor;
    _align = c?.align ?? 'center';
    _layout = c?.layout ?? 'single';
    _imagePath = c?.imagePath;
    _imageMode = c?.isImage ?? false;
  }

  @override
  void dispose() {
    _textController.dispose();
    _rangeController.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final Uint8List? raw = widget.pickImage != null
          ? await widget.pickImage!()
          : await (() async {
              final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery);
              return f == null ? null : await File(f.path).readAsBytes();
            })();
      if (raw == null) return;
      // A logo is kept as a PNG no bigger than 1024 px, so it is light to store and draw.
      final Uint8List? png = await compute(_prepareWatermarkLogo, raw);
      if (png == null || !mounted) return;
      final Directory docs = widget.logoDirectory != null ? await widget.logoDirectory!() : await getApplicationDocumentsDirectory();
      final Directory dir = Directory(p.join(docs.path, 'watermark_logos'));
      await dir.create(recursive: true);
      final String path = p.join(dir.path, 'wm_${DateTime.now().microsecondsSinceEpoch}.png');
      await File(path).writeAsBytes(png, flush: true);
      if (!mounted) return;
      setState(() {
        _imagePath = path;
        _imageMode = true;
      });
    } catch (_) {
      // A picture that cannot be read is simply not chosen.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirm() {
    if (_imageMode && _imagePath == null) return;
    final bool image = _imageMode && _imagePath != null;
    if (!image && _textController.text.trim().isEmpty) return;
    if (widget.pages != null) {
      if (_pagesChoice == 'range') {
        if (parsePageRange(_rangeController.text, widget.pageCount) == null) {
          setState(() => _rangeError = AppLocalizations.of(context).watermarkPagesInvalid(widget.pageCount));
          return;
        }
        widget.pages!.value = _rangeController.text.trim();
      } else {
        widget.pages!.value = _pagesChoice;
      }
    }
    final double sizeScale = _fontSize / 48;
    final SignaturePlacement placement = switch (_layout) {
      'tiled' => SignaturePlacement(pctX: 0.5, pctY: 0.5, rotationDegrees: -30, scale: sizeScale.clamp(0.25, 5.0).toDouble()),
      'diagonal' => SignaturePlacement(pctX: 0.5, pctY: 0.5, rotationDegrees: -35, scale: (sizeScale * 2).clamp(0.1, 5.0).toDouble()),
      _ => SignaturePlacement(pctX: 0.5, pctY: 0.5, scale: sizeScale.clamp(0.1, 5.0).toDouble()),
    };
    final layer = WatermarkLayer(
      pageIndex: 0,
      text: image ? '' : _textController.text.trim(),
      placement: placement,
      opacity: _opacity,
      fontSize: _fontSize,
      color: _color,
      fontFamily: _fontFamily,
      bold: _bold,
      italic: _italic,
      underline: _underline,
      outlineColor: _outlineColor,
      outlineWidth: _outlineWidth,
      shadowOffsetX: _shadowOffsetX,
      shadowOffsetY: _shadowOffsetY,
      shadowColor: _shadowColor,
      align: _align,
      layout: _layout,
      imagePath: image ? _imagePath : null,
    );
    Navigator.pop(context, layer);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final isEdit = widget.initialConfig != null;

    return Padding(
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
                Text(isEdit ? AppLocalizations.of(context).watermarkEditTitle : AppLocalizations.of(context).watermarkAddTitle,
                    style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<bool>(
                  key: const ValueKey<String>('wmKind'),
                  segments: <ButtonSegment<bool>>[
                    ButtonSegment<bool>(value: false, label: Text(AppLocalizations.of(context).watermarkKindText), icon: const Icon(Icons.text_fields)),
                    ButtonSegment<bool>(value: true, label: Text(AppLocalizations.of(context).watermarkKindImage), icon: const Icon(Icons.image_outlined)),
                  ],
                  selected: <bool>{_imageMode},
                  onSelectionChanged: (Set<bool> v) => setState(() => _imageMode = v.first),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_imageMode) ...[
                  Row(
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey<String>('wmChooseImage'),
                        onPressed: _busy ? null : _chooseImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(AppLocalizations.of(context).watermarkChooseImage),
                      ),
                      const SizedBox(width: 12),
                      if (_imagePath != null)
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: Image.file(File(_imagePath!), key: const ValueKey<String>('wmLogoPreview'), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                        ),
                    ],
                  ),
                ] else
                  TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).watermarkTextLabel,
                      labelStyle: TextStyle(color: textSecondary),
                    ),
                    style: TextStyle(color: textPrimary),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(AppLocalizations.of(context).watermarkLayoutLabel, style: TextStyle(color: textPrimary, fontSize: 12)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final String l in const <String>['single', 'diagonal', 'tiled'])
                      ChoiceChip(
                        key: ValueKey<String>('wmLayout:$l'),
                        label: Text(l == 'single'
                            ? AppLocalizations.of(context).watermarkLayoutSingle
                            : l == 'diagonal'
                                ? AppLocalizations.of(context).watermarkLayoutDiagonal
                                : AppLocalizations.of(context).watermarkLayoutTiled),
                        selected: _layout == l,
                        onSelected: (_) => setState(() => _layout = l),
                      ),
                  ],
                ),
                if (widget.pages != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(AppLocalizations.of(context).watermarkPagesLabel, style: TextStyle(color: textPrimary, fontSize: 12)),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final String c in const <String>['current', 'all', 'range'])
                        ChoiceChip(
                          key: ValueKey<String>('wmPages:$c'),
                          label: Text(c == 'current'
                              ? AppLocalizations.of(context).watermarkPagesThis
                              : c == 'all'
                                  ? AppLocalizations.of(context).watermarkPagesAll
                                  : AppLocalizations.of(context).watermarkPagesRange),
                          selected: _pagesChoice == c,
                          onSelected: (_) => setState(() {
                            _pagesChoice = c;
                            _rangeError = null;
                          }),
                        ),
                    ],
                  ),
                  if (_pagesChoice == 'range')
                    TextField(
                      key: const ValueKey<String>('wmRange'),
                      controller: _rangeController,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).watermarkPagesRangeHint,
                        errorText: _rangeError,
                      ),
                      onChanged: (_) => setState(() => _rangeError = null),
                    ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(AppLocalizations.of(context).opacityPercentLabel((_opacity * 100).round()), style: TextStyle(color: textPrimary, fontSize: 12)),
                Slider(
                  value: _opacity,
                  min: 0.05,
                  max: 1.0,
                  onChanged: (v) => setState(() => _opacity = v),
                ),
                Text(AppLocalizations.of(context).sizePtLabel(_fontSize.round()), style: TextStyle(color: textPrimary, fontSize: 12)),
                Slider(
                  value: _fontSize,
                  min: 12,
                  max: 144,
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(AppLocalizations.of(context).commonColor, style: TextStyle(color: textPrimary, fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final sw in _swatches)
                      GestureDetector(
                        onTap: () => setState(() => _color = sw),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(sw),
                            shape: BoxShape.circle,
                            border: Border.all(color: _color == sw ? accent : Colors.grey, width: _color == sw ? 2 : 1),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDialog<Color>(
                          context: context,
                          builder: (c2) => ColorPickerDialog(initial: Color(_color)),
                        );
                        if (picked != null) setState(() => _color = picked.toARGB32());
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: textSecondary, width: 1),
                        ),
                        child: const Icon(Icons.colorize, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    FilterChip(
                      label: Text(AppLocalizations.of(context).textBold),
                      selected: _bold,
                      onSelected: (v) => setState(() => _bold = v),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(AppLocalizations.of(context).textItalic),
                      selected: _italic,
                      onSelected: (v) => setState(() => _italic = v),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(AppLocalizations.of(context).textUnderline),
                      selected: _underline,
                      onSelected: (v) => setState(() => _underline = v),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(AppLocalizations.of(context).alignLabel, style: TextStyle(color: textPrimary, fontSize: 12)),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Icon(Icons.format_align_left, size: 16),
                      selected: _align == 'left',
                      onSelected: (_) => setState(() => _align = 'left'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Icon(Icons.format_align_center, size: 16),
                      selected: _align == 'center',
                      onSelected: (_) => setState(() => _align = 'center'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Icon(Icons.format_align_right, size: 16),
                      selected: _align == 'right',
                      onSelected: (_) => setState(() => _align = 'right'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                      onPressed: _confirm,
                      child: Text(isEdit ? AppLocalizations.of(context).commonUpdate : AppLocalizations.of(context).commonAdd),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chosen logo as a PNG of at most 1024 px on its longest side; null if unreadable.
Uint8List? _prepareWatermarkLogo(Uint8List raw) {
  try {
    final img.Image? decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    img.Image out = decoded;
    final int longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest > 1024) {
      out = decoded.width >= decoded.height ? resizeSmooth(decoded, width: 1024) : resizeSmooth(decoded, height: 1024);
    }
    if (out.numChannels != 4) out = out.convert(numChannels: 4);
    return Uint8List.fromList(img.encodePng(out));
  } catch (_) {
    return null;
  }
}

/// What to store when an existing watermark is changed in the sheet. If the layout
/// was changed (single, diagonal, tiled) its turn and size take the new layout's
/// preset; otherwise the watermark keeps where the person put it.
WatermarkLayer applyWatermarkEdit(WatermarkLayer existing, WatermarkLayer config) {
  final bool layoutChanged = config.layout != existing.layout;
  return config.copyWith(
    pageIndex: existing.pageIndex,
    placement: layoutChanged
        ? SignaturePlacement(
            pctX: existing.placement.pctX,
            pctY: existing.placement.pctY,
            rotationDegrees: config.placement.rotationDegrees,
            scale: config.placement.scale,
          )
        : existing.placement,
    clearImage: config.imagePath == null,
  );
}
