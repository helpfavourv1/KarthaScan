import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'conversion_workspace.dart';

/// Folders under the app's documents folder that only ever hold page pictures
/// (camera, gallery, merged, extracted and cropped pages). Other folders are never swept.
const List<String> pageFolders = <String>['managed_pages', 'combined_pages', 'scanner_fallback_pages', 'imported_pages', 'manual_crop_pages'];

/// Page pictures that no document uses any more (a page that was deleted or
/// replaced in the Pages manager). Only files older than [minAge] go, so a page
/// that was just removed can still come back with Undo. Returns how many were removed.
Future<int> sweepOrphanPageFiles(
  Directory root, {
  required Set<String> referenced,
  Duration minAge = const Duration(days: 1),
  DateTime? now,
}) async {
  final DateTime clock = now ?? DateTime.now();
  int removed = 0;
  for (final String folder in pageFolders) {
    final Directory dir = Directory(p.join(root.path, folder));
    if (!await dir.exists()) continue;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is! File || referenced.contains(e.path)) continue;
      try {
        if (clock.difference(await e.lastModified()) < minAge) continue;
        await e.delete();
        removed++;
      } catch (_) {}
    }
  }
  return removed;
}

/// Keeps the temporary export and share folders under [maxBytes] by deleting the
/// oldest first. Anything touched in the last [protect] is never removed, because
/// it may be on its way to the share sheet. Returns how many folders were removed.
Future<int> trimTempExports(
  Directory tmp, {
  int maxBytes = 200 * 1024 * 1024,
  Duration protect = const Duration(hours: 1),
  DateTime? now,
}) async {
  final DateTime clock = now ?? DateTime.now();
  if (!await tmp.exists()) return 0;
  final List<_Entry> entries = <_Entry>[];
  int total = 0;
  await for (final FileSystemEntity e in tmp.list()) {
    final String name = p.basename(e.path);
    if (e is! Directory || !(name.startsWith('export_') || name.startsWith('share_'))) continue;
    try {
      final int size = await directoryBytes(e);
      final DateTime modified = (await e.stat()).modified;
      entries.add(_Entry(e, size, modified));
      total += size;
    } catch (_) {}
  }
  if (total <= maxBytes) return 0;
  entries.sort((_Entry a, _Entry b) => a.modified.compareTo(b.modified));
  int removed = 0;
  for (final _Entry e in entries) {
    if (total <= maxBytes) break;
    if (clock.difference(e.modified) < protect) continue;
    try {
      await e.dir.delete(recursive: true);
      total -= e.size;
      removed++;
    } catch (_) {}
  }
  return removed;
}

class _Entry {
  _Entry(this.dir, this.size, this.modified);
  final Directory dir;
  final int size;
  final DateTime modified;
}

Future<int> directoryBytes(Directory d) async {
  int total = 0;
  if (!await d.exists()) return 0;
  await for (final FileSystemEntity e in d.list(recursive: true)) {
    if (e is File) {
      try {
        total += await e.length();
      } catch (_) {}
    }
  }
  return total;
}

/// What the Settings row shows.
class StorageUsage {
  const StorageUsage({required this.appBytes, required this.temporaryBytes});
  final int appBytes;
  final int temporaryBytes;
}

/// Thrown when there is clearly not enough free space for a job.
class LowStorageException implements Exception {
  LowStorageException({required this.neededBytes, required this.freeBytes});
  final int neededBytes;
  final int freeBytes;
  @override
  String toString() => 'LowStorageException(need $neededBytes, free $freeBytes)';
}

class StorageHygiene {
  StorageHygiene({Future<int?> Function()? freeBytes}) : _freeBytes = freeBytes ?? _nativeFreeBytes;
  final Future<int?> Function() _freeBytes;

  static const MethodChannel _channel = MethodChannel('com.zdmgold.katharscan/storage');

  /// Free space on the phone, or null when it cannot be read (then nothing is blocked).
  static Future<int?> _nativeFreeBytes() async {
    try {
      final num? v = await _channel.invokeMethod<num>('freeBytes');
      return v?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Throws [LowStorageException] when [neededBytes] plus a safety margin does not fit.
  Future<void> ensureFreeSpace(int neededBytes, {int marginBytes = 50 * 1024 * 1024}) async {
    final int? free = await _freeBytes();
    if (free == null) return;
    if (free < neededBytes + marginBytes) {
      throw LowStorageException(neededBytes: neededBytes + marginBytes, freeBytes: free);
    }
  }

  /// A cautious estimate of the room an export needs: the pages rendered once
  /// plus the output file, so about twice the size of the page files.
  static Future<int> estimateExportBytes(Iterable<String> pagePaths) async {
    int total = 0;
    for (final String path in pagePaths) {
      try {
        total += await File(path).length();
      } catch (_) {}
    }
    return total * 2;
  }

  /// Size of the file a conversion starts from, times three (render plus output).
  static Future<int> estimateConvertBytes(String sourcePath) async {
    try {
      return (await File(sourcePath).length()) * 3;
    } catch (_) {
      return 0;
    }
  }

  Future<StorageUsage> usage({Set<String> keep = const <String>{}}) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory tmp = await getTemporaryDirectory();
    final int app = await directoryBytes(docs);
    int temp = await (await ConversionWorkspace.create()).temporaryBytes(keep: keep);
    await for (final FileSystemEntity e in tmp.list()) {
      final String name = p.basename(e.path);
      if (e is Directory && (name.startsWith('export_') || name.startsWith('share_'))) temp += await directoryBytes(e);
    }
    return StorageUsage(appBytes: app, temporaryBytes: temp);
  }

  /// The Clear button: removes temporary files nothing is using. Returns bytes freed.
  Future<int> clearTemporary({Set<String> keep = const <String>{}}) async {
    final StorageUsage before = await usage(keep: keep);
    await (await ConversionWorkspace.create()).clearAll(keep: keep);
    final Directory tmp = await getTemporaryDirectory();
    await for (final FileSystemEntity e in tmp.list()) {
      final String name = p.basename(e.path);
      if (e is Directory && (name.startsWith('export_') || name.startsWith('share_'))) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    }
    final StorageUsage after = await usage(keep: keep);
    final int freed = before.temporaryBytes - after.temporaryBytes;
    return freed < 0 ? 0 : freed;
  }
}

/// "12.3 MB" style text.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB'];
  double v = bytes / 1024;
  int i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}
