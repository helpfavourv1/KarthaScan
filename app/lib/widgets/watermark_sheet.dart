import 'package:flutter/material.dart';
import '../core/models/scan_document.dart';
import '../core/models/signature_placement.dart';
import '../core/utils/constants.dart';
import 'color_picker_dialog.dart';
import '../l10n/app_localizations.dart';

/// Rich watermark styling sheet. Returns a WatermarkLayer with pageIndex=0
/// and placement at center (caller sets actual pageIndex + placement).
/// [initialConfig] enables edit mode (pre-filled values).
class WatermarkSheet extends StatefulWidget {
  const WatermarkSheet({super.key, this.initialConfig});
  final WatermarkLayer? initialConfig;

  @override
  State<WatermarkSheet> createState() => _WatermarkSheetState();
}

class _WatermarkSheetState extends State<WatermarkSheet> {
  late final TextEditingController _textController;
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

  static const _swatches = [
    0xFF8E8E93,
    0xFF000000,
    0xFFFF3B30,
    0xFF007AFF,
    0xFF34C759,
    0xFFFF9500,
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _textController = TextEditingController(text: c?.text ?? 'CONFIDENTIAL');
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
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_textController.text.trim().isEmpty) return;
    final layer = WatermarkLayer(
      pageIndex: 0,
      text: _textController.text.trim(),
      placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5),
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
                TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).watermarkTextLabel,
                    labelStyle: TextStyle(color: textSecondary),
                  ),
                  style: TextStyle(color: textPrimary),
                ),
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
