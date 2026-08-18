// lib/widgets/scan_preview_card.dart
//
// Document viewer: swipeable pages, zoom, share button (Section 16 file
// #27).
//
// Presentational — takes page paths and an onShare callback via
// constructor rather than calling ShareService directly, so this stays
// reusable/testable without a BuildContext-bound service lookup.
// scan_detail_screen.dart (Phase 5) supplies the actual share wiring.
import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class ScanPreviewCard extends StatefulWidget {
  const ScanPreviewCard({
    super.key,
    required this.pagePaths,
    this.onShare,
    this.initialPage = 0,
    this.onPageChanged,
  });

  final List<String> pagePaths;
  final VoidCallback? onShare;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  @override
  State<ScanPreviewCard> createState() => _ScanPreviewCardState();
}

class _ScanPreviewCardState extends State<ScanPreviewCard> {
  late final PageController _pageController;
  late int _currentPage;

  int get _lastIndex => widget.pagePaths.isEmpty ? 0 : widget.pagePaths.length - 1;

  @override
  void initState() {
    super.initState();
    // Deliberately not using int.clamp() here — its return type varies by
    // Dart SDK version between `num` and `int`, and this project is
    // pinned to a specific Flutter/Dart pair (Section 1). A plain
    // conditional avoids betting on that.
    final int requested = widget.initialPage;
    _currentPage = requested < 0
        ? 0
        : (requested > _lastIndex ? _lastIndex : requested);
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    if (widget.pagePaths.isEmpty) {
      return ColoredBox(
        color: bg,
        child: Center(
          child: Text(
            l10n.scanPreviewNoPages,
            style: TextStyle(color: textSecondary, fontSize: AppTypography.bodySize),
          ),
        ),
      );
    }

    return ColoredBox(
      color: bg,
      child: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.pagePaths.length,
              onPageChanged: (int index) {
                setState(() => _currentPage = index);
                widget.onPageChanged?.call(index);
              },
              itemBuilder: (BuildContext context, int index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(
                      File(widget.pagePaths[index]),
                      fit: BoxFit.contain,
                      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                        return Icon(
                          Icons.broken_image_outlined,
                          color: textSecondary,
                          size: 48,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            color: surface,
            child: Row(
              children: <Widget>[
                Text(
                  '${_currentPage + 1} / ${widget.pagePaths.length}',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: AppTypography.footnoteSize,
                  ),
                ),
                const Spacer(),
                if (widget.onShare != null)
                  IconButton(
                    onPressed: widget.onShare,
                    icon: Icon(Icons.ios_share, color: accent),
                    tooltip: l10n.shareTooltip,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
