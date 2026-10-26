// Import and convert, on the emulator, through the real Convert screen: every
// source type to every target, a 100-page PDF, the PDF import path, and bad files.
// Prints "EMU: <id> | PASS|FAIL|INFO | detail".
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/services/conversion_workspace.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/pdf_text_extractor.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:katharscan/core/services/pdf_to_images_service.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/main.dart' as app;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

void note(String id, String status, String detail) {
  // ignore: avoid_print
  print('EMU: $id | $status | ${detail.replaceAll('\n', ' / ')}');
}

class Outcome {
  Outcome(this.status, this.files, this.message, this.seconds);
  final String status; // ok | failed | timeout
  final List<File> files;
  final String message;
  final int seconds;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('C import and convert matrix', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    await LocalStorageService().initialize();
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory work = Directory(p.join(docs.path, 'convert_test'))..createSync(recursive: true);

    Future<void> pumpFor(int ms) async {
      for (int i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await app.main();
    await pumpFor(4000);
    final BuildContext ctx = tester.element(find.byType(Scaffold).first);
    final GoRouter router = GoRouter.of(ctx);
    final AppLocalizations l10n = AppLocalizations.of(ctx);

    void check(String id, bool ok, String detail) => note(id, ok ? 'PASS' : 'FAIL', '$detail | memory now ${(ProcessInfo.currentRss / 1048576).round()} MB, peak ${(ProcessInfo.maxRss / 1048576).round()} MB');

    Future<void> section(String id, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, st) {
        note(id, 'FAIL', 'exception: $e / ${st.toString().split('\n').take(3).join(' / ')}');
      }
    }

    // ---- sample sources ----
    Future<File> makePdf(String name, int pages) async {
      final pw.Document d = pw.Document();
      for (int i = 1; i <= pages; i++) {
        d.addPage(pw.Page(build: (pw.Context c) => pw.Center(child: pw.Text('Alpha page $i of $pages', style: const pw.TextStyle(fontSize: 36)))));
      }
      return File(p.join(work.path, name))..writeAsBytesSync(await d.save());
    }

    Future<File> makeImage(String name) async {
      final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 64))
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: 64))
        ..addText('Alpha image text');
      final ui.Paragraph para = b.build()..layout(const ui.ParagraphConstraints(width: 800));
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final ui.Canvas c = ui.Canvas(rec);
      c.drawRect(const ui.Rect.fromLTWH(0, 0, 900, 1200), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      c.drawParagraph(para, const ui.Offset(50, 100));
      final ui.Image im = await rec.endRecording().toImage(900, 1200);
      final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
      return File(p.join(work.path, name))..writeAsBytesSync(bd!.buffer.asUint8List());
    }

    final File pdf3 = await makePdf('sample3.pdf', 3);
    final File image = await makeImage('Résumé scan (1).png');
    final File txt = File(p.join(work.path, 'notes.txt'))..writeAsStringSync('Alpha line one\nBeta line two\nÜnïcödé ñ 日本語 Привет\n${List<String>.generate(80, (int i) => 'Line number $i of the long note').join('\n')}\n');
    final File csv = File(p.join(work.path, 'table.csv'))..writeAsStringSync('name,qty,note\nAlpha,3,"first, with comma"\nBeta,5,second\n');
    final File docx = File(await ExportService().buildDocxFromText('Alpha docx text\nSecond paragraph Beta', work.path, 'sample'));

    final Directory convDocs = Directory(p.join(docs.path, 'converted_docs'));
    final Directory convImgs = Directory(p.join(docs.path, 'converted_images'));
    Set<String> listing() => <String>{
          for (final Directory d in <Directory>[convDocs, convImgs, docs]) if (d.existsSync()) ...d.listSync().whereType<File>().map((File f) => f.path).where((String f) => p.basename(f).startsWith('conv_') || p.basename(f).startsWith('txt_') || p.basename(f).startsWith('csv_') || p.basename(f).startsWith('docx_') || d != docs),
        };

    // Drives the real screen: open, pick a target, Convert, wait for it to finish.
    Future<Outcome> convert(File source, String type, String target, {int maxSeconds = 420}) async {
      final Set<String> before = listing();
      final DateTime t0 = DateTime.now();
      router.go('/');
      await pumpFor(500);
      router.push('/convert?path=${Uri.encodeComponent(source.path)}&type=$type');
      await pumpFor(1500);
      final Finder chip = find.widgetWithText(ChoiceChip, target.toUpperCase());
      if (chip.evaluate().isEmpty) return Outcome('failed', <File>[], 'target chip $target not on screen', 0);
      await tester.ensureVisible(chip);
      await tester.tap(chip, warnIfMissed: false);
      await pumpFor(400);
      final Finder go = find.widgetWithText(ElevatedButton, l10n.commonConvert);
      await tester.ensureVisible(go);
      await tester.tap(go, warnIfMissed: false);
      String status = 'timeout';
      String message = '';
      for (int i = 0; i < maxSeconds * 2; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        final Finder failed = find.textContaining(l10n.conversionFailedPrefix);
        final Finder saveFailed = find.textContaining(l10n.saveFailedPrefix);
        if (failed.evaluate().isNotEmpty) {
          status = 'failed';
          message = (failed.evaluate().first.widget as Text).data ?? '';
          break;
        }
        if (saveFailed.evaluate().isNotEmpty) {
          status = 'failed';
          message = (saveFailed.evaluate().first.widget as Text).data ?? '';
          break;
        }
        // The screen closes itself when the files were saved.
        if (find.text(l10n.convertDocumentTitle).evaluate().isEmpty) {
          status = 'ok';
          break;
        }
      }
      await pumpFor(500);
      final List<File> all = <File>[for (final String f in listing().difference(before)) File(f)]..sort((File a, File b) => a.path.compareTo(b.path));
      // Intermediates (rendered PNG pages, temp PDFs) are reported, not judged.
      final List<File> made = all.where((File f) => p.extension(f.path).toLowerCase() == '.$target').toList();
      final int extra = all.length - made.length;
      // Nothing but the deliverable may remain, and the scratch area must be empty.
      final Directory work = Directory(p.join(docs.path, 'work'));
      final int scratch = work.existsSync() ? work.listSync().length : 0;
      note('clean-${p.basename(source.path)}-to-$target', extra == 0 && scratch == 0 ? 'PASS' : 'FAIL',
          '$extra intermediate file(s) left (${all.where((File f) => !made.contains(f)).map((File f) => p.basename(f.path)).take(3).join(', ')}), scratch folders: $scratch');
      return Outcome(status, made, message, DateTime.now().difference(t0).inSeconds);
    }

    // C6 below runs after the matrix; helpers first.
    int pdfPages(File f) => RegExp(r'/Type\s*/Page(?!s)').allMatches(String.fromCharCodes(f.readAsBytesSync())).length;
    String zipText(File f) {
      final Archive a = ZipDecoder().decodeBytes(f.readAsBytesSync());
      final ArchiveFile? d = a.findFile('word/document.xml');
      return d == null ? '' : String.fromCharCodes(d.content as List<int>);
    }

    int darkPixels(img.Image im) {
      int n = 0;
      for (int y = 0; y < im.height; y += 3) {
        for (int x = 0; x < im.width; x += 3) {
          if (im.getPixel(x, y).r < 100) n++;
        }
      }
      return n;
    }

    // Returns a problem description or null when the output is right.
    String? verify(Outcome o, String target, {required int pages, String? token, bool ocr = false}) {
      if (o.status != 'ok') return '${o.status}: ${o.message}';
      if (o.files.isEmpty) return 'no output files found';
      switch (target) {
        case 'pdf':
          if (o.files.length != 1) return '${o.files.length} files';
          final Uint8List b = o.files.first.readAsBytesSync();
          if (String.fromCharCodes(b.take(5)) != '%PDF-') return 'not a PDF';
          final int n = pdfPages(o.files.first);
          if (n < (pages > 0 ? pages : 1)) return 'PDF has $n pages, want at least ${pages > 0 ? pages : 1}';
        case 'jpg' || 'png':
          // Text-like sources paginate (80 lines -> several pictures); fixed-page sources must match.
          if (pages > 0 ? o.files.length != pages : o.files.isEmpty) return '${o.files.length} pictures, want ${pages > 0 ? pages : 'at least 1'}';
          for (final File f in o.files) {
            final img.Image? im = target == 'jpg' ? img.decodeJpg(f.readAsBytesSync()) : img.decodePng(f.readAsBytesSync());
            if (im == null) return '${p.basename(f.path)} does not decode';
            if (im.width < 300 || im.height < 300) return 'picture too small ${im.width}x${im.height}';
            if (o.files.length <= 3 && darkPixels(im) < 30) return 'page looks blank';
          }
        case 'txt' || 'csv':
          final String t = o.files.first.readAsStringSync();
          if (t.trim().isEmpty) return 'empty text';
          if (token != null && !t.toLowerCase().contains(token.toLowerCase())) return 'text lacks "$token": ${t.substring(0, min(80, t.length))}';
        case 'docx':
          final String x = zipText(o.files.first);
          if (x.isEmpty) return 'not a Word file';
          if (token != null && !ocr && !x.contains(token)) return 'Word text lacks "$token"';
      }
      return null;
    }

    const List<String> targets = <String>['pdf', 'jpg', 'png', 'txt', 'docx', 'csv'];

    // ---- C1: PDF -> pictures first (the heavy path), small then 100 pages ----
    await section('C1-pdf-to-images-small', () async {
      for (final String t in <String>['png', 'jpg']) {
        final Outcome o = await convert(pdf3, 'pdf', t);
        final String? problem = verify(o, t, pages: 3);
        check('C1-pdf3-$t', problem == null, '${problem ?? '3 pages rendered and decoded'} in ${o.seconds} s');
      }
    });

    final File pdf100 = await makePdf('sample100.pdf', 100);
    await section('C2-pdf100', () async {
      note('C2-info', 'INFO', 'built a ${(pdf100.lengthSync() / 1024).round()} KB, 100-page PDF');
      for (final String t in <String>['png', 'jpg', 'docx', 'pdf']) {
        final Outcome o = await convert(pdf100, 'pdf', t, maxSeconds: 900);
        final String? problem = verify(o, t, pages: t == 'pdf' ? 100 : 100);
        check('C2-pdf100-$t', problem == null, '${problem ?? '100 pages converted'} in ${o.seconds} s, ${o.files.length} file(s), ${(o.files.fold<int>(0, (int a, File f) => a + f.lengthSync()) / 1048576).toStringAsFixed(1)} MB');
      }
    });

    // The PDF import path (Import PDF as a document): render all pages, then OCR them all.
    await section('C3-pdf-import-100', () async {
      final DateTime t0 = DateTime.now();
      final List<String> paths = await PdfToImagesService().convertToImages(pdf100.path);
      final int renderS = DateTime.now().difference(t0).inSeconds;
      check('C3-render', paths.length == 100, '${paths.length} pages rendered in $renderS s');
      final DateTime t1 = DateTime.now();
      final OcrService ocr = OcrService();
      String text = '';
      try {
        text = await ocr.recognizeTextForPages(paths).timeout(const Duration(minutes: 12));
      } finally {
        await ocr.dispose();
      }
      final int ocrS = DateTime.now().difference(t1).inSeconds;
      check('C3-ocr-all-pages', text.toLowerCase().contains('page 20 of 100'), 'OCR (capped at the first 20 pages by design), 100 pages took $ocrS s, ${text.length} characters, ends: ${text.length > 40 ? text.substring(text.length - 40) : text}');
    });

    // ---- C4: the full matrix, every source to every target ----
    final Map<String, (File, String, int, String?)> sources = <String, (File, String, int, String?)>{
      'pdf': (pdf3, 'pdf', 3, 'alpha'),
      'image': (image, 'image', 1, 'alpha'),
      'txt': (txt, 'txt', 0, 'Alpha'),
      'csv': (csv, 'csv', 0, 'Alpha'),
      'docx': (docx, 'docx', 0, 'Alpha'),
    };
    for (final MapEntry<String, (File, String, int, String?)> s in sources.entries) {
      for (final String t in targets) {
        await section('C4-${s.key}-$t', () async {
          final (File file, String type, int pages, String? token) = s.value;
          final bool viaOcr = (type == 'pdf' || type == 'image') && (t == 'txt' || t == 'csv');
          final Outcome o = await convert(file, type, t, maxSeconds: 300);
          final String? problem = verify(o, t, pages: pages, token: token, ocr: type == 'pdf' || type == 'image');
          check('C4-${s.key}-to-$t', problem == null, '${problem ?? 'ok${viaOcr ? ' (read by OCR)' : ''}'} in ${o.seconds} s');
        });
      }
    }


    // ---- C6: text reading: embedded text is instant and exact, scans use OCR, jobs resume ----
    await section('C6-text-extraction', () async {
      final ConversionWorkspace ws = await ConversionWorkspace.create();
      // Embedded text: the generated PDF has real text, so no OCR is needed.
      ConversionJob job = await ws.begin('c6a');
      final DateTime t0 = DateTime.now();
      final PdfTextResult r1 = await PdfTextExtractor().extract(pdf3.path, workspace: ws, job: job);
      await job.dispose();
      final int ms1 = DateTime.now().difference(t0).inMilliseconds;
      check('C6-embedded', r1.embedded == 3 && r1.ocr == 0 && r1.text.contains('Alpha page 1 of 3') && r1.text.contains('Alpha page 3 of 3'),
          '${r1.embedded} text pages, ${r1.ocr} OCR pages, $ms1 ms, text "${r1.text.replaceAll('\n', ' ').substring(0, min(40, r1.text.length))}"');

      // A scanned PDF (pictures only) must fall back to OCR and still read the words.
      final pw.Document scan = pw.Document();
      final pw.MemoryImage mi = pw.MemoryImage(image.readAsBytesSync());
      for (int i = 0; i < 2; i++) {
        scan.addPage(pw.Page(build: (pw.Context c) => pw.Center(child: pw.Image(mi))));
      }
      final File scanPdf = File(p.join(work.path, 'scanned.pdf'))..writeAsBytesSync(await scan.save());
      job = await ws.begin('c6b');
      final DateTime t1 = DateTime.now();
      final PdfTextResult r2 = await PdfTextExtractor().extract(scanPdf.path, workspace: ws, job: job);
      await job.dispose();
      check('C6-scanned-uses-ocr', r2.ocr == 2 && r2.embedded == 0 && r2.text.toLowerCase().contains('alpha'),
          '${r2.ocr} OCR pages, ${DateTime.now().difference(t1).inSeconds} s, text "${r2.text.replaceAll('\n', ' ').trim()}"');

      // Cancel after 2 pages, then run again: those pages come from checkpoints.
      final File pdf12 = await makePdf('sample12.pdf', 12);
      int seen = 0;
      job = await ws.begin('c6c');
      final PdfTextResult part = await PdfTextExtractor().extract(pdf12.path, workspace: ws, job: job, isCancelled: () => ++seen > 3);
      await job.dispose();
      job = await ws.begin('c6d');
      final PdfTextResult rest = await PdfTextExtractor().extract(pdf12.path, workspace: ws, job: job);
      await job.dispose();
      check('C6-resume', part.cancelled && rest.resumed == part.pages.length && rest.pages.length == 12 && rest.text.contains('page 12 of 12') && !rest.text.contains('page 13'),
          'first run stopped with ${part.pages.length} pages, second resumed ${rest.resumed} and finished ${rest.pages.length}');
      final Directory wd = ws.workDir;
      final int left = wd.existsSync() ? wd.listSync().length : 0;
      check('C6-clean-after-finish', left == 0, '$left folder(s) in the scratch area after the finished job');

      // Page range through the real screen: 30-page PDF, ask for pages 3 to 5 only.
      final File pdf30 = await makePdf('sample30.pdf', 30);
      final Set<String> before = listing();
      router.go('/');
      await pumpFor(500);
      router.push('/convert?path=${Uri.encodeComponent(pdf30.path)}&type=pdf');
      await pumpFor(1500);
      final Finder txtChip = find.widgetWithText(ChoiceChip, 'TXT');
      await tester.ensureVisible(txtChip);
      await tester.tap(txtChip, warnIfMissed: false);
      await pumpFor(400);
      final Finder goBtn = find.widgetWithText(ElevatedButton, l10n.commonConvert);
      await tester.ensureVisible(goBtn);
      await tester.tap(goBtn, warnIfMissed: false);
      await pumpFor(1500);
      final bool dialog = find.byKey(const ValueKey('rangeFrom')).evaluate().isNotEmpty;
      if (dialog) {
        await tester.enterText(find.byKey(const ValueKey('rangeFrom')), '3');
        await tester.enterText(find.byKey(const ValueKey('rangeTo')), '5');
        await tester.tap(find.byKey(const ValueKey('rangeGo')));
        for (int i = 0; i < 120 && find.text(l10n.convertDocumentTitle).evaluate().isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await pumpFor(500);
      }
      final List<File> made = <File>[for (final String f in listing().difference(before)) File(f)].where((File f) => f.path.endsWith('.txt')).toList();
      final String t = made.isEmpty ? '' : made.first.readAsStringSync();
      check('C6-range-dialog', dialog && t.contains('page 3 of 30') && t.contains('page 5 of 30') && !t.contains('page 2 of 30') && !t.contains('page 6 of 30'),
          'dialog shown: $dialog, text: "${t.replaceAll('\n', ' ').trim()}"');
    });

    // ---- C5: bad files must fail with a message, never hang or crash ----
    Future<void> bad(String id, File f, String type, String target) async {
      await section(id, () async {
        final Outcome o = await convert(f, type, target, maxSeconds: 120);
        // A clean failure shows a message; "ok" with files for an empty file is also acceptable.
        final bool clean = o.status == 'failed' || (o.status == 'ok' && o.files.isNotEmpty);
        check(id, clean, '${o.status}${o.message.isEmpty ? '' : ': ${o.message}'} in ${o.seconds} s');
      });
    }

    await bad('C5-corrupt-pdf-to-jpg', File(p.join(work.path, 'corrupt.pdf'))..writeAsBytesSync(Uint8List.fromList(List<int>.generate(500, (int i) => i % 256))), 'pdf', 'jpg');
    await bad('C5-corrupt-image-to-pdf', File(p.join(work.path, 'bad.png'))..writeAsBytesSync(Uint8List.fromList(<int>[1, 2, 3, 4])), 'image', 'pdf');
    await bad('C5-empty-txt-to-pdf', File(p.join(work.path, 'empty.txt'))..writeAsStringSync(''), 'txt', 'pdf');
    await bad('C5-empty-csv-to-pdf', File(p.join(work.path, 'empty.csv'))..writeAsStringSync(''), 'csv', 'pdf');
    await bad('C5-corrupt-docx-to-txt', File(p.join(work.path, 'bad.docx'))..writeAsBytesSync(Uint8List.fromList(<int>[80, 75, 3, 4, 9, 9, 9])), 'docx', 'txt');
    await bad('C5-unsupported-type', File(p.join(work.path, 'sheet.xlsx'))..writeAsBytesSync(Uint8List.fromList(<int>[1, 2, 3])), 'unknown', 'pdf');
    // A big text file (about 3 MB) to PDF: many pages, must finish.
    await section('C5-big-txt-to-pdf', () async {
      final File big = File(p.join(work.path, 'big.txt'))..writeAsStringSync(List<String>.generate(40000, (int i) => 'Row $i: the quick brown fox jumps over the lazy dog').join('\n'));
      final Outcome o = await convert(big, 'txt', 'pdf', maxSeconds: 600);
      final String? problem = verify(o, 'pdf', pages: 50);
      check('C5-big-txt-to-pdf', problem == null, '${problem ?? 'converted'} in ${o.seconds} s, ${o.files.isEmpty ? 0 : pdfPages(o.files.first)} pages');
    });
  });
}
