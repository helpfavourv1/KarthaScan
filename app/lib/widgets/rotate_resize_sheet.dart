import 'dart:io';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../core/models/page_transform.dart';
import '../core/utils/smooth_resize.dart' show resizeSmooth;
import 'document_canvas.dart' show PagePreviewJob, renderPagePreview;
import '../core/utils/constants.dart';
import '../core/utils/smooth_resize.dart' show straightenZoom;
import 'package:image/image.dart' as img;
import '../l10n/app_localizations.dart';


enum RotateResizeMode { rotate, resize }

/// What the rotate sheet returns: the NEW quarter turns (0 to 3) and the page's
/// tilt correction in degrees (replaces the old one), and whether to use both on
/// every page.
class RotateResult {
  const RotateResult(this.turns, this.straighten, this.applyAll);
  final int turns;
  final double straighten;
  final bool applyAll;
}

class RotateResizeSheet extends StatefulWidget {
  const RotateResizeSheet({
    super.key,
    required this.mode,
    required this.imagePath,
    this.onApplyAll,
    this.initialTurns = 0,
    this.initialStraighten = 0,
    this.baseSize,
    this.transform,
  });

  /// Size of the page as it is now (the cropped area, if the page is cropped).
  /// Resize starts from this, not from the full photo.
  final Size? baseSize;

  /// The page's edits, used to estimate the file size of the page as it is now.
  final PageTransform? transform;

  final RotateResizeMode mode;
  final String imagePath;
  final ValueChanged<bool>? onApplyAll;

  /// Quarter turns the page already has. The preview starts from this
  /// orientation; the sheet still returns only the NEW turns (0 to 3).
  final int initialTurns;

  /// Tilt correction the page already has, in degrees.
  final double initialStraighten;

  @override
  State<RotateResizeSheet> createState() => RotateResizeSheetState();
}

class RotateResizeSheetState extends State<RotateResizeSheet> {
  int _quarterTurns = 0;
  late double _tilt = widget.initialStraighten;
  bool _applyAll = false;
  bool _gridOn = false;
  img.Image? _originalImage;
  bool _loading = true;
  final TextEditingController _widthCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  bool _aspectLock = true;
  double _origAspect = 1.0;
  int _baseW = 1;
  int _baseH = 1;
  int _origBytes = 0;
  Uint8List? _sample; // the page as it is now, at most 2000 px, for size estimates
  int? _estBytes;
  Timer? _estTimer;
  String? _paper;
  int _dpi = 300;

  static const int _maxSide = 10000;
  static const int _maxPixels = 40000000;

  bool get _sizeValid {
    final w = int.tryParse(_widthCtrl.text);
    final h = int.tryParse(_heightCtrl.text);
    return w != null && h != null && w >= 1 && h >= 1 && w <= _maxSide && h <= _maxSide && w * h <= _maxPixels;
  }

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      _originalImage = img.decodeImage(bytes);
      _origBytes = bytes.length;
      if (widget.mode == RotateResizeMode.resize) {
        final PageTransform t = (widget.transform ?? const PageTransform()).copyWith(clearResize: true, straightenDegrees: 0, brightness: 0, contrast: 0);
        _sample = await compute(renderPagePreview, PagePreviewJob(bytes, t));
      }
      if (_originalImage != null) {
        final Size? base = widget.baseSize;
        _baseW = (base != null && base.width >= 1) ? base.width.round() : _originalImage!.width;
        _baseH = (base != null && base.height >= 1) ? base.height.round() : _originalImage!.height;
        _widthCtrl.text = _baseW.toString();
        _heightCtrl.text = _baseH.toString();
        _origAspect = _baseW / _baseH;
      }
      if (mounted) setState(() => _loading = false);
      _scheduleEstimate();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleEstimate() {
    _estTimer?.cancel();
    _estTimer = Timer(const Duration(milliseconds: 350), _estimate);
  }

  Future<void> _estimate() async {
    final Uint8List? sample = _sample;
    final int? w = int.tryParse(_widthCtrl.text), h = int.tryParse(_heightCtrl.text);
    if (sample == null || w == null || h == null || !_sizeValid) return;
    final int est = await compute(_estimateBytes, <String, dynamic>{'bytes': sample, 'w': w, 'h': h});
    if (mounted && int.tryParse(_widthCtrl.text) == w && int.tryParse(_heightCtrl.text) == h) setState(() => _estBytes = est);
  }

  @override
  void dispose() {
    _estTimer?.cancel();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final textSecondary = isDark ? const Color(0xFF8E8E93) : const Color(0xFF3A3A3C);
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.mode == RotateResizeMode.rotate ? AppLocalizations.of(context).rotateLabel : AppLocalizations.of(context).resizeTitle,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: _loading || _originalImage == null
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: widget.mode == RotateResizeMode.rotate
                            ? _buildRotatePreview(textSecondary)
                            : _buildResizePreview(textSecondary, accent),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: (widget.mode == RotateResizeMode.resize && !_sizeValid) ? null : () {
                      if (widget.mode == RotateResizeMode.rotate) {
                        widget.onApplyAll?.call(_applyAll);
                        Navigator.pop(context, RotateResult(_quarterTurns, _tilt, _applyAll));
                      } else {
                        final w = int.tryParse(_widthCtrl.text) ?? _baseW;
                        final h = int.tryParse(_heightCtrl.text) ?? _baseH;
                        Navigator.pop(context, (w, h));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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

  /// Sets the size so the page fits a paper size at the chosen dpi (same shape).
  void _applyPaper(String key) {
    const Map<String, (double, double)> inches = {'a4': (8.27, 11.69), 'a5': (5.83, 8.27), 'letter': (8.5, 11.0)};
    final (double pw0, double ph0) = inches[key]!;
    final bool landscape = _baseW > _baseH;
    final double pw = (landscape ? ph0 : pw0) * _dpi, ph = (landscape ? pw0 : ph0) * _dpi;
    final double k = (pw / _baseW) < (ph / _baseH) ? pw / _baseW : ph / _baseH;
    setState(() {
      _paper = key;
      _widthCtrl.text = (_baseW * k).round().toString();
      _heightCtrl.text = (_baseH * k).round().toString();
    });
    _scheduleEstimate();
  }

  Widget _buildRotatePreview(Color textSecondary) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: (widget.initialTurns + _quarterTurns) % 4,
            child: Center(
              child: AspectRatio(
                aspectRatio: _originalImage!.width / _originalImage!.height,
                child: ClipRect(
                  child: Stack(fit: StackFit.expand, children: [
                    Transform.scale(
                      scale: straightenZoom(_tilt, _originalImage!.width, _originalImage!.height),
                      child: Transform.rotate(
                        angle: _tilt * 3.141592653589793 / 180,
                        child: Image.file(File(widget.imagePath), fit: BoxFit.fill),
                      ),
                    ),
                    if (_tilt != 0 || _gridOn) IgnorePointer(child: CustomPaint(painter: _GridPainter())),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Row(children: [
          Text(AppLocalizations.of(context).straightenLabel, style: TextStyle(color: textSecondary)),
          Expanded(
            child: Slider(
              key: const Key('straightenSlider'),
              min: -45,
              max: 45,
              divisions: 180,
              value: _tilt.clamp(-45.0, 45.0).toDouble(),
              label: '${_tilt.toStringAsFixed(1)}°',
              onChangeStart: (_) => setState(() => _gridOn = true),
              onChangeEnd: (_) => setState(() => _gridOn = false),
              onChanged: (v) => setState(() => _tilt = v),
            ),
          ),
          SizedBox(width: 48, child: Text('${_tilt.toStringAsFixed(1)}°', key: const Key('straightenValue'), style: TextStyle(color: textSecondary))),
          IconButton(key: const Key('straightenReset'), icon: const Icon(Icons.restart_alt), onPressed: _tilt == 0 ? null : () => setState(() => _tilt = 0)),
        ]),
        const SizedBox(height: 16),
        Text('${((widget.initialTurns + _quarterTurns) % 4) * 90}°', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textSecondary)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
          icon: const Icon(Icons.rotate_90_degrees_ccw),
          label: Text(AppLocalizations.of(context).rotate90Action),
        ),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            title: Text(AppLocalizations.of(context).applyToAllPages),
            value: _applyAll,
            onChanged: (v) => setState(() => _applyAll = v),
          ),
        ),
      ],
    );
  }

  Widget _buildResizePreview(Color textSecondary, Color accent) {
    final origW = _baseW;
    final origH = _baseH;
    final newW = int.tryParse(_widthCtrl.text) ?? origW;
    final newH = int.tryParse(_heightCtrl.text) ?? origH;
    final ratio = (newW * newH) / (origW * origH);
    final estBytes = _estBytes ?? (_origBytes * ratio).round();
    final estMB = (estBytes / (1024 * 1024)).toStringAsFixed(2);
    final pctChange = ((ratio - 1) * 100).round();
    final bool enlarging = newW * newH > origW * origH * 1.05;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: Image.file(File(widget.imagePath), fit: BoxFit.contain)),
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context).originalDimensions(origW, origH), style: TextStyle(fontSize: 14, color: textSecondary)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: _widthCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: AppLocalizations.of(context).widthLabel, border: OutlineInputBorder()),
                onChanged: (v) {
                  setState(() => _paper = null);
                  _scheduleEstimate();
                  if (_aspectLock) {
                    final w = int.tryParse(v);
                    if (w != null) _heightCtrl.text = (w / _origAspect).round().toString();
                  }
                },
              ),
            ),
            Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context).multiplySymbol)),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _heightCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: AppLocalizations.of(context).heightLabel, border: OutlineInputBorder()),
                onChanged: (v) {
                  setState(() => _paper = null);
                  _scheduleEstimate();
                  if (_aspectLock) {
                    final h = int.tryParse(v);
                    if (h != null) _widthCtrl.text = (h * _origAspect).round().toString();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            title: Text(AppLocalizations.of(context).lockAspectRatio),
            value: _aspectLock,
            onChanged: (v) => setState(() => _aspectLock = v),
          ),
        ),
        Wrap(spacing: 8, children: [
          for (final pct in [0.25, 0.5, 0.75])
            ChoiceChip(
              label: Text('${(pct * 100).round()}%'),
              selected: false,
              onSelected: (_) {
                setState(() {
                  _paper = null;
                  _widthCtrl.text = (origW * pct).round().toString();
                  _heightCtrl.text = (origH * pct).round().toString();
                });
                _scheduleEstimate();
              },
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final String k in ['a4', 'a5', 'letter'])
            ChoiceChip(key: Key('paper:$k'), label: Text(k == 'letter' ? 'Letter' : k.toUpperCase()), selected: _paper == k, onSelected: (_) => _applyPaper(k)),
          for (final int d in [150, 300])
            ChoiceChip(key: Key('dpi:$d'), label: Text('$d dpi'), selected: _dpi == d, onSelected: (_) {
              setState(() => _dpi = d);
              if (_paper != null) _applyPaper(_paper!);
            }),
        ]),
        const SizedBox(height: 12),
        if (enlarging)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(AppLocalizations.of(context).resizeUpscaleWarning, key: const Key('upscaleWarning'), style: const TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        if (!_sizeValid)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('1 - $_maxSide px', style: const TextStyle(fontSize: 12, color: Colors.red)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: pctChange < 0 ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '≈ $estMB MB (${pctChange > 0 ? '+' : ''}$pctChange%)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pctChange < 0 ? Colors.green : Colors.orange),
          ),
        ),
      ],
    );
  }
}


/// A thin grid over the picture while the tilt is being set, to line text up.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;
    final Paint shadow = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 2;
    for (int i = 1; i < 8; i++) {
      final double x = size.width * i / 8, y = size.height * i / 8;
      for (final Paint q in [shadow, p]) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), q);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), q);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}


/// Real JPEG size of the page at the new pixel size: a sample of the page is resized
/// to the target (or as near as the sample allows) and encoded, then scaled by
/// pixel count when the target is bigger than the sample.
int _estimateBytes(Map<String, dynamic> args) {
  final img.Image? sample = img.decodeImage(args['bytes'] as Uint8List);
  final int w = args['w'] as int, h = args['h'] as int;
  if (sample == null) return 0;
  final double k = (w >= sample.width || h >= sample.height) ? 1.0 : 0.0;
  img.Image im = sample;
  double scale = 1;
  if (k == 0.0) {
    im = resizeSmooth(sample, width: w, height: h);
  } else {
    // Target is larger than the sample: encode the sample, scale by pixel count.
    scale = (w * h) / (sample.width * sample.height);
  }
  return (img.encodeJpg(im, quality: 85).length * scale).round();
}
