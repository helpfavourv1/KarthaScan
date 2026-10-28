import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/overlay_files.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('overlay_sweep'));
  tearDown(() => root.deleteSync(recursive: true));

  File make(String rel, {Duration age = Duration.zero}) {
    final File f = File('${root.path}/$rel')..createSync(recursive: true);
    f.writeAsBytesSync(<int>[1, 2, 3]);
    f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  test('removes old unused drawings and logos, keeps everything else', () async {
    final File usedOld = make('annotate_pages/used.png', age: const Duration(days: 9));
    final File orphanOld = make('annotate_pages/orphan.png', age: const Duration(days: 9));
    final File orphanNew = make('annotate_pages/just_removed.png', age: const Duration(minutes: 5));
    final File logoUsed = make('watermark_logos/used.png', age: const Duration(days: 9));
    final File logoOrphan = make('watermark_logos/orphan.png', age: const Duration(days: 3));
    final File other = make('pages/scan_1.png', age: const Duration(days: 30));
    final int n = await sweepOrphanOverlayFiles(root, referenced: <String>{usedOld.path, logoUsed.path});
    expect(n, 2);
    expect(usedOld.existsSync(), isTrue, reason: 'a document still uses it (also when copied to many pages)');
    expect(orphanOld.existsSync(), isFalse);
    expect(orphanNew.existsSync(), isTrue, reason: 'recently removed: Undo may still need it');
    expect(logoUsed.existsSync(), isTrue);
    expect(logoOrphan.existsSync(), isFalse);
    expect(other.existsSync(), isTrue, reason: 'other folders are never touched');
  });

  test('missing folders and an empty app folder are fine; a second sweep removes nothing', () async {
    expect(await sweepOrphanOverlayFiles(root, referenced: <String>{}), 0);
    make('annotate_pages/a.png', age: const Duration(days: 2));
    expect(await sweepOrphanOverlayFiles(root, referenced: <String>{}), 1);
    expect(await sweepOrphanOverlayFiles(root, referenced: <String>{}), 0);
  });

  test('the age limit can be changed', () async {
    final File f = make('annotate_pages/a.png', age: const Duration(hours: 2));
    expect(await sweepOrphanOverlayFiles(root, referenced: <String>{}, minAge: const Duration(hours: 1)), 1);
    expect(f.existsSync(), isFalse);
  });
}
