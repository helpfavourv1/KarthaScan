import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/conversion_workspace.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late ConversionWorkspace ws;
  setUp(() {
    root = Directory.systemTemp.createTempSync('ws');
    ws = ConversionWorkspace(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  File make(String rel, {int ageHours = 0}) {
    final File f = File(p.join(root.path, rel))..createSync(recursive: true)..writeAsStringSync('x');
    f.setLastModifiedSync(DateTime.now().subtract(Duration(hours: ageHours)));
    return f;
  }

  test('a job folder is removed on dispose, with everything in it', () async {
    final ConversionJob job = await ws.begin('convert');
    File(job.path('a.png')).writeAsStringSync('x');
    File(job.path('b.pdf')).writeAsStringSync('x');
    expect(job.dir.existsSync(), isTrue);
    await job.dispose();
    expect(job.dir.existsSync(), isFalse);
    expect(ws.workDir.listSync(), isEmpty);
  });

  test('two jobs never share a folder, odd labels are safe', () async {
    final ConversionJob a = await ws.begin('a/b c');
    final ConversionJob b = await ws.begin('a/b c');
    expect(a.dir.path == b.dir.path, isFalse);
    expect(p.isWithin(ws.workDir.path, a.dir.path), isTrue);
    await a.dispose();
    await b.dispose();
  });

  test('sweep removes old scratch folders, stray intermediates and old output; keeps what documents use', () async {
    final ConversionJob old = await ws.begin('crashed');
    File(old.path('page.png')).writeAsStringSync('x');
    // Dart cannot set a folder's time, the system tool can.
    expect(Process.runSync('touch', <String>['-d', '2 hours ago', old.dir.path]).exitCode, 0);
    final ConversionJob running = await ws.begin('running'); // fresh: must survive
    final File strayOld = make('txt_123.pdf', ageHours: 2);
    final File strayNew = make('csv_456.pdf');
    final File docPage = make('converted_images/pdf_1_1.png', ageHours: 72);
    final File orphan = make('converted_images/pdf_2_1.png', ageHours: 72);
    final File freshOutput = make('converted_docs/conv_9.pdf');
    final File unrelated = make('scan_001.jpg', ageHours: 500);

    final int removed = await ws.sweep(keep: <String>{docPage.path});
    expect(old.dir.existsSync(), isFalse);
    expect(running.dir.existsSync(), isTrue);
    expect(strayOld.existsSync(), isFalse);
    expect(strayNew.existsSync(), isTrue, reason: 'recent file could belong to a running job');
    expect(docPage.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
    expect(freshOutput.existsSync(), isTrue);
    expect(unrelated.existsSync(), isTrue, reason: 'never touch files outside the conversion areas');
    expect(removed, 3);
    await running.dispose();
  });

  test('sweep on an empty or missing root does not fail', () async {
    expect(await ConversionWorkspace(Directory(p.join(root.path, 'nope'))).sweep(), 0);
  });

  test('temporaryBytes counts only removable files, clearAll empties them', () async {
    final File kept = make('converted_docs/kept.pdf');
    make('converted_docs/other.pdf');
    make('converted_images/x.png');
    expect(await ws.temporaryBytes(keep: <String>{kept.path}), 2);
    await ws.clearAll(keep: <String>{kept.path});
    expect(await ws.temporaryBytes(keep: <String>{kept.path}), 0);
    expect(kept.existsSync(), isTrue);
  });
}
