// lib/core/services/share_service.dart
//
// OS share sheet via share_plus (Section 16 file #16).
//
// SCOPE (confirmed, revised from the blueprint's original Section 20
// language): "Google Drive direct upload" and "iCloud direct upload" are
// BOTH delivered via the plain OS share sheet, not a bespoke Google OAuth
// + Drive API integration. Android's native share sheet already surfaces
// "Save to Drive" automatically when the Drive app is installed, the same
// way iOS's share sheet surfaces Files/iCloud — share_plus gets both for
// free on both platforms with zero Drive-specific code, zero new
// dependencies, and zero new external OAuth client setup. This keeps file
// #64's "No server. No cloud." privacy claim literally true (KatharScan
// never talks to Google's servers directly) and avoids a real sequencing
// problem: a true Drive OAuth client would need to be keyed to the app's
// release-signing SHA-1, which doesn't exist this early in the project.
// Section 19/20's copy gets updated in later phases to say "share to
// Drive, iCloud, and more" rather than implying a dedicated in-app
// connection. Because of this, cloud upload is no longer a distinct
// Pro-gated action here — it's just what the OS share sheet already does
// for any shared file, on both tiers; only *batch* export/share (Section
// 19) is Pro-gated, and that's a UI-layer decision, not something this
// service enforces.
//
// API NOTE: share_plus's static Share.share()/Share.shareXFiles() methods
// are deprecated as of share_plus 11.0.0 in favor of the
// SharePlus.instance.share(ShareParams(...)) instance API used below —
// verified against the package's current changelog/docs rather than
// assumed from memory, since this is a fresh build with no reason to
// write new code against a deprecated surface.
//
// LAYERING: imports share_plus and cross_file — both plugins with uniform
// cross-platform behavior and no OS-branching logic here, consistent with
// the confirmed core/services/ policy. sharePositionOrigin (required on
// iPad to avoid a crash) is accepted as an optional parameter supplied by
// the calling widget rather than resolved here — this file has no
// BuildContext, by design (Section 4 layering).
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show Rect;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Thrown when the share sheet itself fails to open — rare, usually only
/// an invalid file path or a platform channel error. A user simply
/// dismissing the share sheet is NOT an error; see [ShareOutcome.dismissed].
class ShareFailedException implements Exception {
  const ShareFailedException(this.message);
  final String message;

  @override
  String toString() => 'ShareFailedException: $message';
}

enum ShareOutcome { completed, dismissed, unavailable }

class ShareService {
  /// Shares one or more local files via the OS share sheet. [filePaths]
  /// must be local file paths, not remote URLs — XFile cannot fetch a
  /// remote resource on the app's behalf. This is how a user sends an
  /// exported PDF/DOCX/image/TXT anywhere, including to Drive or iCloud
  /// via whatever the OS share sheet already offers.
  Future<ShareOutcome> shareFiles({
    required List<String> filePaths,
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    if (filePaths.isEmpty) {
      throw const ShareFailedException('Nothing to share.');
    }
    try {
      final List<XFile> files =
          filePaths.map((String path) => XFile(path)).toList();
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          files: files,
          subject: subject,
          text: text,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return _outcomeFromResult(result);
    } on ShareFailedException {
      rethrow;
    } catch (error, stackTrace) {
      _logError('shareFiles', error, stackTrace);
      throw const ShareFailedException('Could not open the share sheet.');
    }
  }

  /// Shares plain text (no attached file) — used for lightweight actions
  /// like sharing a document's OCR text directly without exporting first.
  Future<ShareOutcome> shareText({
    required String text,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    try {
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: subject,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return _outcomeFromResult(result);
    } catch (error, stackTrace) {
      _logError('shareText', error, stackTrace);
      throw const ShareFailedException('Could not open the share sheet.');
    }
  }

  ShareOutcome _outcomeFromResult(ShareResult result) {
    switch (result.status) {
      case ShareResultStatus.success:
        return ShareOutcome.completed;
      case ShareResultStatus.dismissed:
        return ShareOutcome.dismissed;
      case ShareResultStatus.unavailable:
        return ShareOutcome.unavailable;
    }
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[ShareService] $operation failed: $error');
  }

  /// Fallback: force-open native mailto: composer when share sheet has no email option.
  /// Does NOT attach files — mailto: cannot carry attachments portably.
  /// B4 will prefer shareFiles (which attaches files) and call this only as a fallback.
  Future<bool> launchMailto({
    required String to,
    String? subject,
    String? body,
  }) async {
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: to,
        queryParameters: <String, String>{
          if (subject != null && subject.isNotEmpty) 'subject': subject,
          if (body != null && body.isNotEmpty) 'body': body,
        },
      );
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (error, stackTrace) {
      _logError('launchMailto', error, stackTrace);
      return false;
    }
  }
}
