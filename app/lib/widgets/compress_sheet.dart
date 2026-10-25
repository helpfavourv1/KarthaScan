import 'package:flutter/material.dart';

import '../core/models/export_job.dart';
import '../core/models/scan_document.dart';
import '../core/services/export_service.dart';
import '../l10n/app_localizations.dart';

/// What the person picked in the compress sheet.
class CompressChoice {
  const CompressChoice(this.format, this.tier);
  final ExportFormat format;
  final CompressionTier tier;
}

/// Opens when Compress is tapped in the tray: PDF or JPG, and three levels, each
/// showing the real size it will produce (measured on the edited first page,
/// scaled by the page count) and how much smaller that is than Original.
class CompressSheet extends StatefulWidget {
  const CompressSheet({super.key, required this.document});
  final ScanDocument document;

  @override
  State<CompressSheet> createState() => _CompressSheetState();
}

class _CompressSheetState extends State<CompressSheet> {
  ExportFormat _format = ExportFormat.pdf;
  CompressionTier _tier = CompressionTier.medium;
  Map<CompressionTier, int>? _sizes;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final int run = ++_run;
    setState(() => _sizes = null);
    Map<CompressionTier, int> sizes;
    try {
      sizes = await ExportService().estimateSizes(widget.document, _format);
    } catch (_) {
      sizes = <CompressionTier, int>{};
    }
    if (!mounted || run != _run) return;
    setState(() => _sizes = sizes);
  }

  static String _mb(int bytes) {
    final double mb = bytes / (1024 * 1024);
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(bytes / 1024).round()} KB';
  }

  String _label(AppLocalizations l10n, CompressionTier t) => switch (t) {
        CompressionTier.small => l10n.compressSmall,
        CompressionTier.medium => l10n.compressMedium,
        CompressionTier.original => l10n.filterOriginal,
      };

  Widget _card(AppLocalizations l10n, CompressionTier t, Color accent) {
    final bool selected = _tier == t;
    final Map<CompressionTier, int>? sizes = _sizes;
    final int? size = sizes?[t];
    final int? orig = sizes?[CompressionTier.original];
    String sub = '';
    if (size != null && orig != null && orig > 0 && t != CompressionTier.original) {
      final int pct = (100 - size * 100 / orig).round();
      sub = pct > 0 ? '−$pct%' : '';
    }
    return Expanded(
      child: InkWell(
        key: ValueKey<String>('compressCard:${t.name}'),
        onTap: () => setState(() => _tier = t),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? accent.withValues(alpha: 0.14) : null,
            border: Border.all(color: selected ? accent : Colors.grey.withValues(alpha: 0.4), width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_label(l10n, t), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              if (sizes == null)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text(size == null || size == 0 ? '—' : _mb(size), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.compressLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<ExportFormat>(
              key: const ValueKey<String>('compressFormat'),
              showSelectedIcon: false,
              segments: const <ButtonSegment<ExportFormat>>[
                ButtonSegment<ExportFormat>(value: ExportFormat.pdf, label: Text('PDF')),
                ButtonSegment<ExportFormat>(value: ExportFormat.jpg, label: Text('JPG')),
              ],
              selected: <ExportFormat>{_format},
              onSelectionChanged: (Set<ExportFormat> s) {
                setState(() => _format = s.first);
                _measure();
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              _card(l10n, CompressionTier.small, accent),
              _card(l10n, CompressionTier.medium, accent),
              _card(l10n, CompressionTier.original, accent),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              key: const ValueKey<String>('compressGo'),
              onPressed: () => Navigator.pop(context, CompressChoice(_format, _tier)),
              child: Text(l10n.compressLabel),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
