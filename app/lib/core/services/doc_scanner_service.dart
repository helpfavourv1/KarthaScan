// lib/core/services/doc_scanner_service.dart
//
// Wrapper around flutter_doc_scanner: ML Kit Document Scanner (Android) +
// VisionKit (iOS). Returns cropped document images (Section 16 file #17).
//
// API VERIFIED against the package's actual Dart API docs rather than
// assumed: FlutterDocScanner exposes getScanDocuments(), getScanDocumentsUri(),
// getScannedDocumentAsImages(), and getScannedDocumentAsPdf(), all
// {int page = 4} and all returning untyped Future (dynamic). This service
// deliberately calls getScannedDocumentAsImages() rather than
// getScanDocuments() — the package's own docs note getScanDocuments()
// returns a PDF on Android but PNGs on iOS, which is exactly the kind of
// cross-platform inconsistency this app's architecture avoids by design
// (ScanDocument.pagePaths always holds per-page images; PDF assembly is
// this app's own export_service.dart, not the scanner's).
//
// EXCEPTION TYPE CORRECTION: Section 14 names `MlKitException` with code
// `UNSUPPORTED` as what to catch. The package's own documented usage
// exclusively shows `on PlatformException` — there's no evidence
// `MlKitException` is actually an exported type from this package. The
// underlying failure (device below ML Kit's Document Scanner RAM
// threshold, Play Services missing, etc.) surfaces as a
// PlatformException with code 'UNSUPPORTED' instead. This file catches
// that — same intent as Section 14, correct actual type.
//
// RESIDUAL UNCERTAINTY (flagged honestly, not silently assumed correct):
// the exact Map key getScannedDocumentAsImages() uses for its returned
// path list isn't fully confirmed from available documentation — sources
// reference "a map with images" but the key name is unclear. _extractPaths
// below tries several plausible keys defensively and normalizes to
// List<String> rather than betting on one guess; this should be verified
// against the actual plugin output on a real device once this repo is
// buildable, and the key list adjusted if none of them hit.
//
// LAYERING: imports flutter_doc_scanner and flutter/services (for
// PlatformException) — plugin/framework imports with uniform
// cross-platform behavior, no OS-branching logic in this file, consistent
// with the confirmed core/services/ policy.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';

import '../utils/constants.dart';

/// Thrown specifically for the &lt;1.7GB RAM / ML Kit module unavailable
/// case. Callers (scan_provider.dart) must catch this and route to the
/// manual crop fallback (files #74-75) per Section 14 — never a dead end.
class DocScannerUnsupportedException implements Exception {
  const DocScannerUnsupportedException(this.message);
  final String message;

  @override
  String toString() => 'DocScannerUnsupportedException: $message';
}

/// Thrown for any other scan failure (user cancelled is handled as an
/// empty result, not an exception — see [DocScannerService.scan]).
class DocScannerFailedException implements Exception {
  const DocScannerFailedException(this.message);
  final String message;

  @override
  String toString() => 'DocScannerFailedException: $message';
}

class DocScanResult {
  const DocScanResult({required this.pageImagePaths});

  /// Ordered local file paths for each cropped page. Empty means the user
  /// cancelled the scan flow before capturing anything — not an error.
  final List<String> pageImagePaths;
}

class DocScannerService {
  final FlutterDocScanner _scanner = FlutterDocScanner();

  /// Launches the native document scanner UI and returns the resulting
  /// cropped page images. An empty result means the user cancelled.
  /// Throws [DocScannerUnsupportedException] on the &lt;1.7GB RAM / ML Kit
  /// module unavailable case, or [DocScannerFailedException] for any
  /// other failure. Never lets a raw platform exception or an unexpected
  /// return shape propagate uncaught.
  Future<DocScanResult> scan({int maxPages = 20}) async {
    try {
      final dynamic raw =
          await _scanner.getScannedDocumentAsImages(page: maxPages);
      final List<String> paths = _extractPaths(raw);
      return DocScanResult(pageImagePaths: paths);
    } on PlatformException catch (error, stackTrace) {
      _logError('scan', error, stackTrace);
      if (error.code == 'UNSUPPORTED') {
        throw const DocScannerUnsupportedException(
          AppPluginFailureCopy.docScannerUnsupportedMessage,
        );
      }
      throw DocScannerFailedException(
        error.message ?? 'Document scanning failed.',
      );
    } catch (error, stackTrace) {
      _logError('scan', error, stackTrace);
      throw const DocScannerFailedException('Document scanning failed.');
    }
  }

  /// Normalizes flutter_doc_scanner's untyped return value to
  /// List&lt;String&gt;. Defensive by design — see the file header's
  /// "RESIDUAL UNCERTAINTY" note.
  List<String> _extractPaths(dynamic raw) {
    if (raw == null) return const <String>[];

    if (raw is List) {
      return raw.whereType<String>().toList();
    }

    if (raw is Map) {
      for (final String key in const <String>[
        'images',
        'Images',
        'Uri',
        'uri',
        'paths',
        'imageUris',
      ]) {
        final Object? value = raw[key];
        if (value is List) {
          return value.whereType<String>().toList();
        }
        if (value is String) {
          return <String>[value];
        }
      }
    }

    if (raw is String) {
      return <String>[raw];
    }

    debugPrint(
      '[DocScannerService] Unrecognized return shape from '
      'getScannedDocumentAsImages(): ${raw.runtimeType}',
    );
    return const <String>[];
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[DocScannerService] $operation failed: $error');
  }
}
