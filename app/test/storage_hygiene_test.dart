import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/storage_hygiene.dart';
import 'package:path/path.dart' as p;

File _file(Directory d, String name, int bytes, DateTime modified) {
  final File f = File(p.join(d.path, name))..createSync(recursive: true);
  f.writeAsBytesSync(List<int>.filled(bytes, 1));
  f.setLastModifiedSync(modified);
  return f;
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('hygiene'));
  tearDown(() => root.deleteSync(recursive: true));

  group('sweepOrphanPageFiles', () {
    test('removes old unused pages, keeps used, young and other-folder files', () async {
      final DateTime now = DateTime(2026, 11, 9);
      final DateTime old = now.subtract(const Duration(days: 3));
      final Directory managed = Directory(p.join(root.path, 'managed_pages'));
      final File used = _file(managed, 'used.jpg', 10, old);
      final File orphan = _file(managed, 'orphan.jpg', 10, old);
      final File young = _file(managed, 'young.jpg', 10, now.subtract(const Duration(hours: 2)));
      final File elsewhere = _file(Directory(p.join(root.path, 'other')), 'x.jpg', 10, old);
      final File manual = _file(Directory(p.join(root.path, 'manual_crop_pages')), 'm.jpg', 10, old);
      final int removed = await sweepOrphanPageFiles(root, referenced: <String>{used.path}, now: now);
      expect(removed, 2);
      expect(used.existsSync(), isTrue);
      expect(orphan.existsSync(), isFalse);
      expect(young.existsSync(), isTrue);
      expect(elsewhere.existsSync(), isTrue);
      expect(manual.existsSync(), isFalse);
    });
    test('a missing folder is fine', () async {
      expect(await sweepOrphanPageFiles(root, referenced: <String>{}), 0);
    });
  });

  group('trimTempExports', () {
    test('deletes the oldest folders first until under the cap, never the protected ones', () async {
      final DateTime now = DateTime(2026, 11, 9, 12);
      Directory dir(String name, int bytes, Duration age) {
        final Directory d = Directory(p.join(root.path, name))..createSync();
        _file(d, 'a.pdf', bytes, now.subtract(age));
        return d;
      }
      final Directory oldest = dir('export_1', 400, const Duration(days: 3));
      final Directory middle = dir('share_2', 400, const Duration(days: 2));
      final Directory recent = dir('export_3', 400, const Duration(minutes: 5));
      final Directory other = dir('cache_keep', 5000, const Duration(days: 9));
      final int removed = await trimTempExports(root, maxBytes: 500, now: now);
      expect(removed, 2);
      expect(oldest.existsSync(), isFalse);
      expect(middle.existsSync(), isFalse);
      expect(recent.existsSync(), isTrue, reason: 'newer than the protect window');
      expect(other.existsSync(), isTrue, reason: 'not an export or share folder');
    });
    test('under the cap removes nothing', () async {
      final Directory d = Directory(p.join(root.path, 'export_1'))..createSync();
      _file(d, 'a.pdf', 100, DateTime.now().subtract(const Duration(days: 5)));
      expect(await trimTempExports(root, maxBytes: 1000), 0);
    });
  });

  group('ensureFreeSpace', () {
    test('throws when space is short and reports the needed amount', () async {
      final StorageHygiene h = StorageHygiene(freeBytes: () async => 60 * 1024 * 1024);
      await expectLater(h.ensureFreeSpace(30 * 1024 * 1024), throwsA(isA<LowStorageException>()));
      try {
        await h.ensureFreeSpace(30 * 1024 * 1024);
      } on LowStorageException catch (e) {
        expect(e.neededBytes, 80 * 1024 * 1024);
        expect(e.freeBytes, 60 * 1024 * 1024);
      }
    });
    test('passes when there is room, and when free space cannot be read', () async {
      await StorageHygiene(freeBytes: () async => 500 * 1024 * 1024).ensureFreeSpace(30 * 1024 * 1024);
      await StorageHygiene(freeBytes: () async => null).ensureFreeSpace(1 << 40);
    });
    test('export estimate is twice the page files, convert estimate three times the source', () async {
      final File a = _file(root, 'a.jpg', 1000, DateTime.now());
      final File b = _file(root, 'b.jpg', 500, DateTime.now());
      expect(await StorageHygiene.estimateExportBytes(<String>[a.path, b.path, '${root.path}/missing.jpg']), 3000);
      expect(await StorageHygiene.estimateConvertBytes(a.path), 3000);
      expect(await StorageHygiene.estimateConvertBytes('${root.path}/missing.pdf'), 0);
    });
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    expect(formatBytes(250 * 1024 * 1024), '250 MB');
  });
}
