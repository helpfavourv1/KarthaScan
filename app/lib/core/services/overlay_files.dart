import 'dart:io';

import 'package:path/path.dart' as p;

/// Folders the annotate and watermark tools keep their pictures in.
const List<String> overlayFolders = <String>['annotate_pages', 'watermark_logos'];

/// Removes drawings and logos that no document uses any more (a mark that was
/// deleted, a watermark that was replaced). A file is only removed when no
/// document refers to it and it is older than [minAge], so a mark that was just
/// removed can still come back with Undo. Returns how many files were removed.
Future<int> sweepOrphanOverlayFiles(
  Directory root, {
  required Set<String> referenced,
  Duration minAge = const Duration(days: 1),
  DateTime? now,
}) async {
  final DateTime clock = now ?? DateTime.now();
  int removed = 0;
  for (final String folder in overlayFolders) {
    final Directory dir = Directory(p.join(root.path, folder));
    if (!await dir.exists()) continue;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is! File) continue;
      if (referenced.contains(e.path)) continue;
      try {
        final DateTime changed = await e.lastModified();
        if (clock.difference(changed) < minAge) continue;
        await e.delete();
        removed++;
      } catch (_) {
        // A file that cannot be removed now is tried again next time.
      }
    }
  }
  return removed;
}
