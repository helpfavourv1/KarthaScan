// Harder round on the emulator: every language at large text sizes, heavy
// documents, rapid edits with undo, hammering the tray, app backgrounding.
// Each test prints "EMU: <id> | <status> | <detail>" like the main suite.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/models/export_job.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/providers/scan_provider.dart';
import 'package:katharscan/core/providers/settings_provider.dart';
import 'package:katharscan/core/providers/theme_provider.dart';
import 'package:katharscan/core/services/doc_scanner_service.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/main.dart' as app;
import 'package:katharscan/widgets/edit_tray.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void note(String id, String status, String detail) {
  // ignore: avoid_print
  print('EMU: $id | $status | ${detail.replaceAll('\n', ' / ')}');
}

Future<File> pagePng(String name, {int w = 900, int h = 1200, String text = 'Stress page'}) async {
  final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 40))
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: 40))
    ..addText('$text ' * 20);
  final ui.Paragraph para = b.build()..layout(ui.ParagraphConstraints(width: w - 100.0));
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  c.drawParagraph(para, const ui.Offset(50, 50));
  final ui.Image im = await rec.endRecording().toImage(w, h);
  final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
  final Directory dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'stress_pages'))..createSync(recursive: true);
  final File f = File(p.join(dir.path, '$name.png'));
  await f.writeAsBytes(bd!.buffer.asUint8List());
  return f;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const Timeout long = Timeout(Duration(minutes: 20));

  late LocalStorageService storage;
  late ScanProvider scan;

  Future<void> bootProvider() async {
    storage = LocalStorageService();
    await storage.initialize();
    scan = ScanProvider(storage: storage, docScanner: DocScannerService(), ocr: OcrService(), settings: SettingsProvider(storage));
    for (int i = 0; i < 100 && scan.isLoading.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<ScanDocument> seedDoc(String id, List<File> pages) async {
    final DateTime now = DateTime.now();
    final ScanDocument d = ScanDocument(
      id: id, title: 'Stress $id', pageCount: pages.length, pagePaths: pages.map((File f) => f.path).toList(),
      createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: pages.first.path,
    );
    await storage.saveDocument(d);
    return d;
  }

  // ---- S1 / S2: every language, light and dark, at normal and very large text
  testWidgets('S1 every language x text size x theme: screens draw without overflow or exceptions', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    final LocalStorageService seed = LocalStorageService();
    await seed.initialize();
    final File pg = await pagePng('s1');
    final DateTime now = DateTime.now();
    await seed.saveDocument(ScanDocument(id: 'stress_ui', title: 'Stress UI', pageCount: 1, pagePaths: <String>[pg.path], createdAt: now, updatedAt: now, ocrText: 'x', thumbnailPath: pg.path));

    final List<String> errors = <String>[];
    Future<void> pumpFor(int ms) async {
      for (int i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await app.main();
    await pumpFor(4000);
    final FlutterExceptionHandlerAlias? old = FlutterError.onError;
    String where = 'boot';
    FlutterError.onError = (FlutterErrorDetails d) {
      final String full = d.toString();
      final RegExpMatch? loc = RegExp(r'(lib/[\w/]+\.dart:\d+)').firstMatch(full);
      errors.add('[$where] ${d.exceptionAsString().split('\n').first} @ ${loc?.group(1) ?? '?'}');
      // Not forwarded: overflow messages must not end the sweep.
    };
    final BuildContext ctx = tester.element(find.byType(Scaffold).first);
    final SettingsProvider settings = Provider.of<SettingsProvider>(ctx, listen: false);
    final ThemeProvider theme = Provider.of<ThemeProvider>(ctx, listen: false);
    final GoRouter router = GoRouter.of(ctx);

    final Map<String, List<String>> bad = <String, List<String>>{};
    final Map<String, Set<String>> groups = <String, Set<String>>{};
    final List<String> locales = AppLocalizations.supportedLocales.map((Locale l) => l.languageCode).toList();
    int combos = 0;
    for (final String lang in locales) {
      await settings.setLanguage(lang);
      for (final double scale in <double>[1.0, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
          await theme.setThemeMode(mode);
          for (final String route in <String>['/', '/settings', '/scan/stress_ui']) {
            where = '$lang x$scale ${mode.name} $route';
            router.go(route);
            await pumpFor(700);
            combos++;
          }
        }
      }
      final List<String> mine = errors.where((String e) => e.contains('[$lang ')).toSet().toList();
      if (mine.isNotEmpty) bad[lang] = mine;
      for (final String e in errors.where((String e) => e.contains('[$lang '))) {
        final RegExpMatch m = RegExp(r'^\[(\S+) (x[\d.]+) (\w+) (\S+)\] (.*?)(?: by [\d.]+ pixels)?( on the \w+)? ?@ (.*)$').firstMatch(e) ?? RegExp(r'^(.*)$').firstMatch(e)!;
        final String key = m.groupCount >= 7 ? '${m.group(4)} ${m.group(2)} ${m.group(3)} | ${m.group(5)}${m.group(6) ?? ''} @ ${m.group(7)}' : e;
        groups.putIfAbsent(key, () => <String>{}).add(lang);
      }
      errors.clear();
    }
    tester.platformDispatcher.clearAllTestValues();
    FlutterError.onError = old;
    final bool ok = bad.isEmpty;
    final List<MapEntry<String, Set<String>>> sorted = groups.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    note('S1-languages', ok ? 'PASS' : 'FAIL', '$combos combinations; ${bad.length} languages with problems; ${groups.length} distinct problems');
    for (final MapEntry<String, Set<String>> g in sorted.take(14)) {
      note('S1-problem', 'FAIL', '${g.key} (${g.value.length} languages${g.value.length < 6 ? ': ${g.value.join(',')}' : ''})');
    }
    expect(bad, isEmpty);
  }, timeout: long);

  // ---- S3: heavy workloads
  for (final ExportFormat fmt in <ExportFormat>[ExportFormat.pdf, ExportFormat.jpg, ExportFormat.docx]) {
    testWidgets('S3 100-page document export ${fmt.name}', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await bootProvider();
        final File one = await pagePng('s3');
        final List<File> pages = <File>[];
        for (int i = 0; i < 100; i++) {
          final File f = File(p.join(one.parent.path, 's3_$i.png'));
          if (!f.existsSync()) await one.copy(f.path);
          pages.add(f);
        }
        final ScanDocument doc = await seedDoc('stress_100_${fmt.name}', pages);
        final Directory out = Directory(p.join((await getTemporaryDirectory()).path, 'stress_out'))..createSync(recursive: true);
        final Stopwatch sw = Stopwatch()..start();
        try {
          final List<String> files = await ExportService()
              .export(document: doc, format: fmt, outputDirectoryPath: out.path, docxMode: ExportDocxMode.imageEmbedded)
              .timeout(const Duration(minutes: 3));
          note('S3-100pages-${fmt.name}', 'PASS', '${files.length} file(s) in ${sw.elapsed.inSeconds}s');
        } on TimeoutException {
          note('S3-100pages-${fmt.name}', 'FAIL', 'did not finish in 3 minutes');
          fail('timeout');
        } catch (e) {
          note('S3-100pages-${fmt.name}', 'FAIL', 'error $e');
          rethrow;
        }
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  testWidgets('S3b PDF export scaling: 10, 25, 50 pages, time and memory', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await bootProvider();
      final File one = await pagePng('s3');
      final StringBuffer r = StringBuffer();
      for (final int n in <int>[10, 25, 50]) {
        final List<File> pages = <File>[];
        for (int i = 0; i < n; i++) {
          final File f = File(p.join(one.parent.path, 's3b_$i.png'));
          if (!f.existsSync()) await one.copy(f.path);
          pages.add(f);
        }
        final ScanDocument doc = await seedDoc('stress_scale_$n', pages);
        final Directory out = Directory(p.join((await getTemporaryDirectory()).path, 'stress_scale'))..createSync(recursive: true);
        final Stopwatch sw = Stopwatch()..start();
        try {
          await ExportService().export(document: doc, format: ExportFormat.pdf, outputDirectoryPath: out.path).timeout(const Duration(minutes: 2));
          r.write('$n pages: ${sw.elapsed.inSeconds}s, memory ${(ProcessInfo.currentRss / 1048576).round()}MB; ');
        } on TimeoutException {
          r.write('$n pages: over 2 min, memory ${(ProcessInfo.currentRss / 1048576).round()}MB; ');
          break;
        }
      }
      note('S3b-pdf-scaling', 'INFO', r.toString());
    });
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('S4 very large photos (12, 24 and 48 megapixel pages) export', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await bootProvider();
      final StringBuffer r = StringBuffer();
      bool ok = true;
      for (final List<int> size in <List<int>>[<int>[4000, 3000], <int>[6000, 4000], <int>[8000, 6000]]) {
        final img.Image big = img.Image(width: size[0], height: size[1]);
        final Random rnd = Random(3);
        for (int y = 0; y < size[1]; y += 7) {
          for (int x = 0; x < size[0]; x += 7) {
            big.setPixelRgb(x, y, rnd.nextInt(255), rnd.nextInt(255), rnd.nextInt(255));
          }
        }
        final Directory dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'stress_pages'))..createSync(recursive: true);
        final File f = File(p.join(dir.path, 'big_${size[0]}.jpg'));
        await f.writeAsBytes(img.encodeJpg(big, quality: 80));
        final ScanDocument doc = await seedDoc('stress_big_${size[0]}', <File>[f]);
        await scan.refresh();
        await scan.updatePageTransform(doc.id, 0, const PageTransform(rotationTurns: 1));
        final Directory out = Directory(p.join((await getTemporaryDirectory()).path, 'stress_big'))..createSync(recursive: true);
        final Stopwatch sw = Stopwatch()..start();
        try {
          final ScanDocument d = scan.documents.value.firstWhere((ScanDocument x) => x.id == doc.id);
          await ExportService().export(document: d, format: ExportFormat.pdf, outputDirectoryPath: out.path);
          r.write('${(size[0] * size[1] / 1e6).round()}MP ok ${sw.elapsed.inSeconds}s; ');
        } catch (e) {
          ok = false;
          r.write('${(size[0] * size[1] / 1e6).round()}MP FAILED ($e); ');
        }
      }
      note('S4-large-photos', ok ? 'PASS' : 'FAIL', r.toString());
      expect(ok, isTrue, reason: r.toString());
    });
  }, timeout: long);

  // ---- S5: rapid edits, undo/redo, delete while saving, then reload from disk
  testWidgets('S5 400 rapid edits with undo/redo and delete-while-saving, database matches memory', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await bootProvider();
      final List<File> pages = <File>[for (int i = 0; i < 4; i++) await pagePng('s5_$i')];
      await seedDoc('stress_edit', pages);
      await seedDoc('stress_gone', <File>[pages.first]);
      await scan.refresh();
      final Random rnd = Random(11);
      int errors = 0;
      final List<Future<void>> pending = <Future<void>>[];
      for (int i = 0; i < 400; i++) {
        try {
          switch (rnd.nextInt(6)) {
            case 0:
              pending.add(scan.addStampLayer('stress_edit', StampLayer(id: 's$i', pageIndex: rnd.nextInt(4), kind: 'text', placement: SignaturePlacement(pctX: rnd.nextDouble(), pctY: rnd.nextDouble()), text: 'S$i')));
            case 1:
              pending.add(scan.updatePageTransform('stress_edit', rnd.nextInt(4), PageTransform(rotationTurns: rnd.nextInt(4))));
            case 2:
              pending.add(scan.renameDocument('stress_edit', 'Name $i'));
            case 3:
              pending.add(scan.undoManager.undo());
            case 4:
              pending.add(scan.undoManager.redo());
            default:
              pending.add(scan.addWatermarkLayer('stress_edit', WatermarkLayer(pageIndex: rnd.nextInt(4), text: 'W$i', placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5))));
          }
          if (i == 200) pending.add(scan.deleteDocument('stress_gone'));
          if (i % 25 == 0) await Future<void>.delayed(const Duration(milliseconds: 5));
        } catch (e) {
          errors++;
        }
      }
      await Future.wait(pending.map((Future<void> f) => f.catchError((Object _) {})));
      await Future<void>.delayed(const Duration(seconds: 2));
      final ScanDocument mem = scan.documents.value.firstWhere((ScanDocument d) => d.id == 'stress_edit');
      final ScanDocument? disk = await storage.getDocumentById('stress_edit');
      final bool resurrected = (await storage.getDocumentById('stress_gone')) != null || scan.documents.value.any((ScanDocument d) => d.id == 'stress_gone');
      final bool same = disk != null && disk.title == mem.title && disk.stampLayers.length == mem.stampLayers.length && disk.watermarkLayers.length == mem.watermarkLayers.length && disk.pageTransforms.length == mem.pageTransforms.length;
      final bool ok = errors == 0 && same && !resurrected;
      note('S5-rapid-edits', ok ? 'PASS' : 'FAIL', 'sync errors=$errors, disk equals memory=$same (stamps ${mem.stampLayers.length}/${disk?.stampLayers.length}), deleted doc came back=$resurrected');
      expect(ok, isTrue);
    });
  }, timeout: long);

  // ---- S6: hammer the real tray and screens, background the app mid-way
  testWidgets('S6 hammer every tray tool 3x with no waits, random taps, backgrounding', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    final LocalStorageService seed = LocalStorageService();
    await seed.initialize();
    final List<File> pages = <File>[for (int i = 0; i < 3; i++) await pagePng('s6_$i')];
    final DateTime now = DateTime.now();
    await seed.saveDocument(ScanDocument(id: 'stress_tray', title: 'Stress tray', pageCount: 3, pagePaths: pages.map((File f) => f.path).toList(), createdAt: now, updatedAt: now, ocrText: 'x', thumbnailPath: pages.first.path));

    Future<void> pumpFor(int ms) async {
      for (int i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await app.main();
    await pumpFor(4000);
    final List<String> errors = <String>[];
    final FlutterExceptionHandlerAlias? old = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      errors.add(d.exceptionAsString().split('\n').first);
      old?.call(d);
    };
    final GoRouter router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/scan/stress_tray');
    await pumpFor(3500);
    expect(find.byType(EditTray), findsOneWidget);

    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Random rnd = Random(5);
    int taps = 0;
    for (int round = 0; round < 6; round++) {
      // Fast repeated taps on every tray target, no waiting for sheets.
      final List<Finder> targets = find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('trayTarget:')).evaluate().map((Element e) => find.byKey(e.widget.key!)).toList();
      note('S6-progress', 'INFO', 'round $round: ${targets.length} tray targets, $taps taps so far');
      for (final Finder t in targets) {
        final String label = (t.evaluate().isEmpty ? '?' : (t.evaluate().first.widget.key as ValueKey<String>?)?.value ?? '?');
        if (round == 0) note('S6-tap', 'INFO', 'about to tap $label');
        for (int k = 0; k < 3; k++) {
          try {
            await tester.tap(t, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 30));
            taps++;
          } catch (_) {}
        }
      }
      note('S6-progress', 'INFO', 'round $round: tray done, random taps next');
      for (int i = 0; i < 60; i++) {
        await tester.tapAt(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height));
        await tester.pump(const Duration(milliseconds: 40));
        taps++;
      }
      note('S6-progress', 'INFO', 'round $round: random taps done, backgrounding');
      // Send the app to the background and bring it back.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumpFor(500);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFor(800);
      if (find.byType(EditTray).evaluate().isEmpty) {
        router.go('/scan/stress_tray');
        await pumpFor(2500);
      }
    }
    FlutterError.onError = old;
    final Set<String> uniq = errors.toSet();
    note('S6-hammer', uniq.isEmpty ? 'PASS' : 'FAIL', '$taps taps, 6 background/resume cycles, ${uniq.length} distinct errors${uniq.isEmpty ? '' : ': ${uniq.take(5).join(' | ')}'}');
    expect(uniq, isEmpty);
  }, timeout: long);
}

typedef FlutterExceptionHandlerAlias = void Function(FlutterErrorDetails);
