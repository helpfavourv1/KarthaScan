import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/conversion_workspace.dart';
import 'package:katharscan/core/services/pdf_text_extractor.dart';
import 'package:path/path.dart' as p;

void main() {
  test('range is clamped to the document and never inverted', () {
    expect(PdfTextExtractor.normalizeRange(100, null, null), (1, 100));
    expect(PdfTextExtractor.normalizeRange(100, 5, 20), (5, 20));
    expect(PdfTextExtractor.normalizeRange(100, 0, 500), (1, 100));
    expect(PdfTextExtractor.normalizeRange(100, 50, 10), (50, 50));
    expect(PdfTextExtractor.normalizeRange(100, 200, 300), (100, 100));
    expect(PdfTextExtractor.normalizeRange(0, null, null), (1, 1));
  });

  test('a page counts as text only with enough visible characters', () {
    expect(PdfTextExtractor.hasEnoughText(null), isFalse);
    expect(PdfTextExtractor.hasEnoughText('   \n  '), isFalse);
    expect(PdfTextExtractor.hasEnoughText('1'), isFalse);
    expect(PdfTextExtractor.hasEnoughText('Alpha page 1 of 3 and more'), isTrue);
  });

  test('time estimate follows the average so far and is absent before any work', () {
    expect(PdfTextExtractor.estimateRemaining(spent: const Duration(seconds: 20), worked: 2, remaining: 8), const Duration(seconds: 80));
    expect(PdfTextExtractor.estimateRemaining(spent: Duration.zero, worked: 0, remaining: 8), isNull);
    expect(PdfTextExtractor.estimateRemaining(spent: const Duration(seconds: 5), worked: 1, remaining: 0), isNull);
  });

  test('the same file gives the same checkpoint folder, a changed file a different one', () {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(1000);
    final String a = PdfTextExtractor.checkpointKey('/x/My Scan (1).pdf', 100, t);
    expect(PdfTextExtractor.checkpointKey('/x/My Scan (1).pdf', 100, t), a);
    expect(PdfTextExtractor.checkpointKey('/x/My Scan (1).pdf', 101, t) == a, isFalse);
    expect(a.startsWith('ocr_'), isTrue);
    expect(RegExp(r'^[A-Za-z0-9_]+$').hasMatch(a), isTrue, reason: 'safe as a folder name: $a');
  });

  test('interrupted text jobs keep their checkpoints for a day, other scratch folders do not', () async {
    final Directory root = Directory.systemTemp.createTempSync('ws2');
    addTearDown(() => root.deleteSync(recursive: true));
    final ConversionWorkspace ws = ConversionWorkspace(root);
    final Directory ocr = Directory(p.join(ws.workDir.path, 'ocr_a_1_2'))..createSync(recursive: true);
    final Directory other = Directory(p.join(ws.workDir.path, '123_convert'))..createSync(recursive: true);
    for (final Directory d in <Directory>[ocr, other]) {
      expect(Process.runSync('touch', <String>['-d', '2 hours ago', d.path]).exitCode, 0);
    }
    await ws.sweep();
    expect(ocr.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
    await ws.sweep(now: DateTime.now().add(const Duration(days: 2)));
    expect(ocr.existsSync(), isFalse);
  });
}
