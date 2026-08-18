// lib/core/utils/error_handler.dart
//
// Global FlutterError.onError + a full-screen retry ErrorWidget.builder
// replacement, with a "Report issue" email link (Section 15).
//
// LAYERING NOTE: Section 4 forbids plugin imports in core/. Opening a
// mailto: link requires `url_launcher`, which IS a plugin (it has native
// platform-channel implementations per OS). To honor the layering rule
// without dropping the required feature, this file does NOT import
// url_launcher. Instead:
//   - This file builds the mailto: URI as a plain Uri (pure dart:core,
//     not a plugin) via [buildReportIssueMailUri].
//   - This file exposes AppErrorScreen and installGlobalErrorHandling(),
//     which accept an `onReportIssue` callback rather than launching
//     anything themselves.
//   - lib/main.dart (Phase 6, outside core/) is where the callback gets
//     wired to an actual `url_launcher.launchUrl(...)` call.
// This is exactly the kind of core/ vs. app-shell split Section 4 asks
// the file manifest to visibly enforce.
import 'package:flutter/material.dart';

import 'constants.dart';

/// Installs a global, non-crashing error boundary:
///   - FlutterError.onError logs framework errors instead of letting them
///     propagate to a red screen of death in release builds.
///   - ErrorWidget.builder is replaced with [AppErrorScreen] so any widget
///     that fails to build shows a recoverable, on-brand screen instead of
///     Flutter's default error box.
///
/// [onReportIssue] is optional. When provided, it is called with the
/// mailto: [Uri] built by [buildReportIssueMailUri] — main.dart should wire
/// this to `url_launcher`'s `launchUrl`. When omitted, the "Report issue"
/// action is hidden rather than shown as a dead button.
void installGlobalErrorHandling({
  void Function(FlutterErrorDetails details)? onReportError,
  void Function(Uri mailUri)? onReportIssue,
}) {
  // Deliberately not chaining to the previous FlutterError.onError beyond
  // presenting the error — the whole point of this installer is that a
  // widget build error must never crash the app (Section 14/15: "never
  // crash"), and we own that contract end-to-end rather than delegating
  // part of it to whatever handler ran before this one.
  FlutterError.onError = (FlutterErrorDetails details) {
    // Always present the error to the console/observatory in debug so it
    // remains visible during development.
    FlutterError.presentError(details);
    onReportError?.call(details);
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return AppErrorScreen(
      errorDetails: details,
      onReportIssue: onReportIssue == null
          ? null
          : () => onReportIssue(buildReportIssueMailUri(details: details)),
    );
  };
}

/// Builds a mailto: URI pre-filled with a subject and a short, non-crashing
/// summary of what went wrong. Pure Dart (dart:core's Uri) — no plugin
/// required to construct it; only to launch it.
Uri buildReportIssueMailUri({
  required FlutterErrorDetails details,
  String? extraContext,
}) {
  final String summary = details.exceptionAsString();
  final String library = details.library ?? 'unknown';
  final StringBuffer body = StringBuffer()
    ..writeln('Please describe what you were doing when this happened:')
    ..writeln()
    ..writeln('---')
    ..writeln('Automatically included (please leave this in):')
    ..writeln('Library: $library')
    ..writeln('Error: $summary');

  if (extraContext != null && extraContext.trim().isNotEmpty) {
    body
      ..writeln()
      ..writeln('Context: $extraContext');
  }

  return Uri(
    scheme: 'mailto',
    path: AppSupportContact.supportEmail,
    queryParameters: <String, String>{
      'subject': 'KatharScan Bug Report',
      'body': body.toString(),
    },
  );
}

/// Full-screen, non-crashing fallback UI shown whenever a widget fails to
/// build. Deliberately built from base Material widgets only — it must
/// render correctly even if it's the very first thing the framework ever
/// draws, before any app-specific theme has necessarily been established.
class AppErrorScreen extends StatelessWidget {
  const AppErrorScreen({
    super.key,
    required this.errorDetails,
    this.onRetry,
    this.onReportIssue,
  });

  final FlutterErrorDetails errorDetails;

  /// Called when the user taps "Try again". If null, the retry button is
  /// hidden rather than shown disabled — main.dart should supply this,
  /// typically by rebuilding the app shell under a fresh key.
  final VoidCallback? onRetry;

  /// Called when the user taps "Report issue". If null, the action is
  /// hidden. See [installGlobalErrorHandling] for how this gets wired to
  /// url_launcher outside of core/.
  final VoidCallback? onReportIssue;

  @override
  Widget build(BuildContext context) {
    final Brightness platformBrightness =
        MediaQuery.maybeOf(context)?.platformBrightness ?? Brightness.light;
    final bool isDark = platformBrightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Material(
      color: bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, size: 48, color: textSecondary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: AppTypography.title1Size,
                    fontWeight: FontWeight.values[
                        (AppTypography.title1Weight ~/ 100) - 1],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'KatharScan ran into a problem displaying this screen. '
                  'Your scans are safe — they\'re stored on this device and '
                  'this doesn\'t affect them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: AppTypography.bodySize,
                    height: AppTypography.bodyLineHeight,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (onRetry != null)
                  SizedBox(
                    width: double.infinity,
                    height: AppShape.buttonMinHeight,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppShape.buttonRadius),
                        ),
                      ),
                      child: const Text('Try again'),
                    ),
                  ),
                if (onRetry != null && onReportIssue != null)
                  const SizedBox(height: AppSpacing.sm),
                if (onReportIssue != null)
                  SizedBox(
                    width: double.infinity,
                    height: AppShape.buttonMinHeight,
                    child: TextButton(
                      onPressed: onReportIssue,
                      child: Text(
                        'Report issue',
                        style: TextStyle(color: accent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
