import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns every temporary file a conversion makes.
///
/// A conversion works inside its own scratch folder (`work/<job>`), which is
/// deleted when the job ends, whether it finished, failed or was cancelled. Only
/// the deliverables are written outside it. [sweep] removes whatever a crash or a
/// force-kill left behind, and old converted output that no document uses.
class ConversionWorkspace {
  ConversionWorkspace(this.root);

  /// The app's documents folder (injectable for tests).
  final Directory root;

  static Future<ConversionWorkspace> create() async => ConversionWorkspace(await getApplicationDocumentsDirectory());

  Directory get workDir => Directory(p.join(root.path, 'work'));
  Directory get convertedDocs => Directory(p.join(root.path, 'converted_docs'));
  Directory get convertedImages => Directory(p.join(root.path, 'converted_images'));
  Directory get importPages => Directory(p.join(root.path, 'pdf_import_pages'));

  int _counter = 0;

  /// A fresh scratch folder for one job. Call [ConversionJob.dispose] in `finally`.
  Future<ConversionJob> begin(String label) async {
    final String safe = label.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final Directory dir = Directory(p.join(workDir.path, '${DateTime.now().microsecondsSinceEpoch}_${_counter++}_$safe'));
    await dir.create(recursive: true);
    return ConversionJob._(dir);
  }

  static final RegExp _strayName = RegExp(r'^(txt|csv|docx|conv)_\d+\.(pdf|txt|csv|docx)$');

  /// Removes leftovers. [keep] holds paths documents still use (pages, thumbnails);
  /// those are never touched. Returns the number of files and folders removed.
  Future<int> sweep({Set<String> keep = const <String>{}, DateTime? now, Duration scratchAge = const Duration(minutes: 10), Duration outputAge = const Duration(days: 1)}) async {
    final DateTime t = now ?? DateTime.now();
    int removed = 0;

    Future<void> removeEntity(FileSystemEntity e) async {
      try {
        await e.delete(recursive: true);
        removed++;
      } catch (_) {}
    }

    // 1. Scratch folders from jobs that never got to clean up after themselves.
    if (await workDir.exists()) {
      await for (final FileSystemEntity e in workDir.list()) {
        try {
          if (t.difference((await e.stat()).modified) > scratchAge) await removeEntity(e);
        } catch (_) {}
      }
    }
    // 2. Intermediate files the older converters left in the main folder.
    if (await root.exists()) {
      await for (final FileSystemEntity e in root.list()) {
        if (e is! File || !_strayName.hasMatch(p.basename(e.path)) || keep.contains(e.path)) continue;
        try {
          if (t.difference((await e.stat()).modified) > scratchAge) await removeEntity(e);
        } catch (_) {}
      }
    }
    // 3. Old converted output nobody saved as a document.
    for (final Directory d in <Directory>[convertedDocs, convertedImages, importPages]) {
      if (!await d.exists()) continue;
      await for (final FileSystemEntity e in d.list()) {
        if (e is! File || keep.contains(e.path)) continue;
        try {
          if (t.difference((await e.stat()).modified) > outputAge) await removeEntity(e);
        } catch (_) {}
      }
    }
    return removed;
  }

  /// Size of everything the sweeper could remove right now, for a Settings row.
  Future<int> temporaryBytes({Set<String> keep = const <String>{}}) async {
    int total = 0;
    for (final Directory d in <Directory>[workDir, convertedDocs, convertedImages, importPages]) {
      if (!await d.exists()) continue;
      await for (final FileSystemEntity e in d.list(recursive: true)) {
        if (e is File && !keep.contains(e.path)) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    }
    return total;
  }

  /// Clears everything temporary that no document uses (the Settings button).
  Future<int> clearAll({Set<String> keep = const <String>{}}) =>
      sweep(keep: keep, now: DateTime.now().add(const Duration(days: 3650)));
}

class ConversionJob {
  ConversionJob._(this.dir);
  final Directory dir;

  String path(String name) => p.join(dir.path, name);

  Future<void> dispose() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
