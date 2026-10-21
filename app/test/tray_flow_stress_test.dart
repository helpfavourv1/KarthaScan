// test/tray_flow_stress_test.dart
//
// Stress test for the edit tray's data flow: many quick edits, undo/redo,
// page changes, deleting while saving, and export of heavily edited
// documents in every format. Uses the real provider, the real sqlite (FFI)
// and the real export code with real pictures.
//
// A failing test here is a confirmed defect; the message says what was seen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/core/models/export_job.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/providers/scan_provider.dart';
import 'package:katharscan/core/providers/settings_provider.dart';
import 'package:katharscan/core/services/doc_scanner_service.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const SignaturePlacement _mid = SignaturePlacement(pctX: 0.5, pctY: 0.5);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;
  late LocalStorageService storage;
  late ScanProvider scan;

  Future<File> page(String name, int w, int h, int shade) async {
    final img.Image im = img.Image(width: w, height: h);
    img.fill(im, color: img.ColorRgb8(shade, 255 - shade, 128));
    final File f = File('${tmp.path}/pages/$name.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(img.encodePng(im));
    return f;
  }

  Future<File> annotationPng(String name) async {
    final img.Image im = img.Image(width: 20, height: 10, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
    final File f = File('${tmp.path}/annotate_pages/$name.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(img.encodePng(im));
    return f;
  }

  Uint8List inkPng() {
    final img.Image im = img.Image(width: 30, height: 12, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(0, 0, 255, 255));
    return Uint8List.fromList(img.encodePng(im));
  }

  Future<ScanDocument> makeDoc(String id, List<File> pages) async {
    final DateTime now = DateTime(2026, 1, 1);
    final ScanDocument d = ScanDocument(
      id: id,
      title: 'Doc $id',
      pageCount: pages.length,
      pagePaths: pages.map((File f) => f.path).toList(),
      createdAt: now,
      updatedAt: now,
      ocrText: '',
      thumbnailPath: pages.first.path,
    );
    await storage.saveDocument(d);
    return d;
  }

  Future<void> boot(List<ScanDocument> docs) async {
    scan = ScanProvider(
      storage: storage,
      docScanner: DocScannerService(),
      ocr: OcrService(),
      settings: SettingsProvider(storage),
    );
    for (int i = 0; i < 200 && scan.isLoading.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  ScanDocument current(String id) => scan.documents.value.firstWhere((ScanDocument d) => d.id == id);

  Future<ScanDocument> fromDb(String id) async =>
      (await storage.getAllDocuments()).firstWhere((ScanDocument d) => d.id == id);

  String fingerprint(ScanDocument d) {
    final Map<String, dynamic> j = Map<String, dynamic>.from(d.toJson());
    j.remove('updatedAt');
    j.remove('updated_at');
    return jsonEncode(j);
  }

  Future<void> settle() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('tray_stress_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tmp.path,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = LocalStorageService();
    await storage.initialize();
  });

  tearDown(() {
    try {
      scan.dispose();
    } catch (_) {}
  });

  group('quick edits', () {
    test('150 mixed edits fired without waiting: nothing lost, memory equals database', () async {
      final List<File> pages = <File>[
        await page('a', 60, 40, 10),
        await page('b', 60, 40, 120),
        await page('c', 60, 40, 220),
      ];
      final ScanDocument d = await makeDoc('d1', pages);
      await boot(<ScanDocument>[d]);
      await scan.addSignatureInk('d1', 'ink1', inkPng(), 'Me', 2.5);
      final File ann = await annotationPng('ann1');

      final List<Future<bool>> ops = <Future<bool>>[];
      int wm = 0, st = 0, sig = 0, an = 0;
      for (int i = 0; i < 150; i++) {
        final int pg = i % 3;
        switch (i % 6) {
          case 0:
            ops.add(scan.addWatermarkLayer('d1', WatermarkLayer(pageIndex: pg, text: 'W$i', placement: _mid)));
            wm++;
          case 1:
            ops.add(scan.addStampLayer('d1', StampLayer(id: 's$i', pageIndex: pg, kind: 'text', placement: _mid, text: 'T$i')));
            st++;
          case 2:
            ops.add(scan.addSignatureLayer('d1', pg, SignaturePlacement(pctX: (i % 10) / 10, pctY: 0.3), inkId: 'ink1'));
            sig++;
          case 3:
            ops.add(scan.addAnnotateLayer('d1', AnnotateLayer(pageIndex: pg, bytesPath: ann.path, placement: _mid)));
            an++;
          case 4:
            ops.add(scan.updatePageTransform('d1', pg, PageTransform(rotationTurns: i % 4)));
          case 5:
            ops.add(scan.updatePageTransform('d1', pg, PageTransform(filter: FilterType.grayscale, filterIntensity: (i % 10) / 10)));
        }
      }
      final List<bool> results = await Future.wait(ops);
      await settle();

      expect(results.every((bool ok) => ok), isTrue, reason: 'some edits reported a failed save');
      final ScanDocument mem = current('d1');
      expect(mem.watermarkLayers.length, wm, reason: 'watermarks lost');
      expect(mem.stampLayers.length, st, reason: 'stamps lost');
      expect(mem.signatureLayers.length, sig, reason: 'signatures lost');
      expect(mem.annotateLayers.length, an, reason: 'annotations lost');
      final ScanDocument disk = await fromDb('d1');
      expect(fingerprint(disk), fingerprint(mem), reason: 'what is saved differs from what is on screen');
    });

    test('delete while edits are still saving: the document does not come back', () async {
      final ScanDocument d = await makeDoc('d2', <File>[await page('a2', 40, 40, 50)]);
      await boot(<ScanDocument>[d]);
      final List<Future<bool>> ops = <Future<bool>>[
        for (int i = 0; i < 30; i++)
          scan.addWatermarkLayer('d2', WatermarkLayer(pageIndex: 0, text: 'x$i', placement: _mid)),
      ];
      final Future<bool> del = scan.deleteDocument('d2');
      await Future.wait(<Future<bool>>[...ops, del]);
      await settle();
      expect((await storage.getAllDocuments()).any((ScanDocument x) => x.id == 'd2'), isFalse,
          reason: 'a queued edit saved the deleted document again');
      expect(scan.documents.value.any((ScanDocument x) => x.id == 'd2'), isFalse);
    });

    test('edit on a document that does not exist is refused, not crashed', () async {
      final ScanDocument d = await makeDoc('d3', <File>[await page('a3', 40, 40, 50)]);
      await boot(<ScanDocument>[d]);
      expect(await scan.addWatermarkLayer('nope', const WatermarkLayer(pageIndex: 0, text: 'x', placement: _mid)), isFalse);
      expect(await scan.updatePageTransform('nope', 0, const PageTransform(rotationTurns: 1)), isFalse);
      expect(await scan.updatePageTransform('d3', 99, const PageTransform(rotationTurns: 1)), anyOf(isTrue, isFalse));
    });
  });

  group('undo and redo', () {
    test('undo all the way, then redo all the way, returns to the same documents', () async {
      final ScanDocument d = await makeDoc('d4', <File>[await page('a4', 50, 50, 70), await page('b4', 50, 50, 90)]);
      await boot(<ScanDocument>[d]);
      final String original = fingerprint(current('d4'));
      for (int i = 0; i < 20; i++) {
        await scan.addWatermarkLayer('d4', WatermarkLayer(pageIndex: i % 2, text: 'u$i', placement: _mid));
        await scan.updatePageTransform('d4', i % 2, PageTransform(rotationTurns: (i % 3) + 1));
      }
      final String edited = fingerprint(current('d4'));
      while (scan.undoManager.canUndo) {
        await scan.undoManager.undo();
      }
      expect(fingerprint(current('d4')), original, reason: 'undo did not return to the start');
      while (scan.undoManager.canRedo) {
        await scan.undoManager.redo();
      }
      expect(fingerprint(current('d4')), edited, reason: 'redo did not return to the edited state');
      await settle();
      expect(fingerprint(await fromDb('d4')), edited);
    });

    test('undo after deleting a page does not bring the deleted page back', () async {
      final List<File> pages = <File>[await page('a5', 50, 50, 10), await page('b5', 50, 50, 100), await page('c5', 50, 50, 200)];
      final ScanDocument d = await makeDoc('d5', pages);
      await boot(<ScanDocument>[d]);
      await scan.addWatermarkLayer('d5', const WatermarkLayer(pageIndex: 2, text: 'keep', placement: _mid));
      await scan.updateDocumentPages('d5', <String>[pages[0].path, pages[2].path]);
      expect(current('d5').pagePaths.length, 2);
      await scan.undoManager.undo();
      expect(current('d5').pagePaths.length, 2,
          reason: 'undoing the watermark restored an old copy of the whole document and the deleted page came back');
      expect(current('d5').watermarkLayers.any((WatermarkLayer w) => w.pageIndex >= 2), isFalse,
          reason: 'a layer points at a page that no longer exists');
    });

    test('undo does not revert a rename or tags made after the edit', () async {
      final ScanDocument d = await makeDoc('d6', <File>[await page('a6', 50, 50, 10)]);
      await boot(<ScanDocument>[d]);
      await scan.addWatermarkLayer('d6', const WatermarkLayer(pageIndex: 0, text: 'w', placement: _mid));
      await scan.renameDocument('d6', 'Renamed');
      await scan.updateTags('d6', <String>['tax']);
      await scan.undoManager.undo();
      expect(current('d6').title, 'Renamed', reason: 'undo reverted the new title');
      expect(current('d6').tags, <String>['tax'], reason: 'undo reverted the tags');
    });

    test('undo/redo pressed many times at once does not corrupt anything', () async {
      final ScanDocument d = await makeDoc('d7', <File>[await page('a7', 50, 50, 10)]);
      await boot(<ScanDocument>[d]);
      for (int i = 0; i < 10; i++) {
        await scan.addStampLayer('d7', StampLayer(id: 'x$i', pageIndex: 0, kind: 'text', placement: _mid, text: '$i'));
      }
      await Future.wait(<Future<void>>[
        for (int i = 0; i < 30; i++) (i.isEven ? scan.undoManager.undo() : scan.undoManager.redo()),
      ]);
      await settle();
      expect(fingerprint(await fromDb('d7')), fingerprint(current('d7')));
    });
  });

  group('pages', () {
    test('deleting the first page moves layers and edits with their pages', () async {
      final List<File> pages = <File>[await page('a8', 50, 50, 10), await page('b8', 50, 50, 100), await page('c8', 50, 50, 200)];
      final ScanDocument d = await makeDoc('d8', pages);
      await boot(<ScanDocument>[d]);
      await scan.addWatermarkLayer('d8', const WatermarkLayer(pageIndex: 0, text: 'gone', placement: _mid));
      await scan.addWatermarkLayer('d8', const WatermarkLayer(pageIndex: 1, text: 'one', placement: _mid));
      await scan.addWatermarkLayer('d8', const WatermarkLayer(pageIndex: 2, text: 'two', placement: _mid));
      await scan.updatePageTransform('d8', 2, const PageTransform(rotationTurns: 1));
      await scan.updateDocumentPages('d8', <String>[pages[1].path, pages[2].path]);
      final ScanDocument after = current('d8');
      expect(after.watermarkLayers.map((WatermarkLayer w) => '${w.text}@${w.pageIndex}').toSet(), <String>{'one@0', 'two@1'});
      expect(after.pageTransforms[1]?.rotationTurns, 1);
      expect(after.pageTransforms.containsKey(2), isFalse);
    });

    test('reordering pages (reverse) keeps each page\'s edits', () async {
      final List<File> pages = <File>[await page('a9', 50, 50, 10), await page('b9', 50, 50, 100), await page('c9', 50, 50, 200)];
      final ScanDocument d = await makeDoc('d9', pages);
      await boot(<ScanDocument>[d]);
      for (int i = 0; i < 3; i++) {
        await scan.addWatermarkLayer('d9', WatermarkLayer(pageIndex: i, text: 'p$i', placement: _mid));
        await scan.updatePageTransform('d9', i, PageTransform(rotationTurns: i + 1));
      }
      await scan.updateDocumentPages('d9', pages.reversed.map((File f) => f.path).toList());
      final ScanDocument after = current('d9');
      expect(after.watermarkLayers.map((WatermarkLayer w) => '${w.text}@${w.pageIndex}').toSet(), <String>{'p2@0', 'p1@1', 'p0@2'});
      expect(<int>[for (int i = 0; i < 3; i++) after.pageTransforms[i]?.rotationTurns ?? 0], <int>[3, 2, 1]);
    });

    test('delete every page but one, then add pages back: counts stay consistent', () async {
      final List<File> pages = <File>[for (int i = 0; i < 6; i++) await page('m$i', 40, 40, i * 30)];
      final ScanDocument d = await makeDoc('d10', pages);
      await boot(<ScanDocument>[d]);
      await scan.updateDocumentPages('d10', <String>[pages[3].path]);
      expect(current('d10').pageCount, 1);
      await scan.insertPageAt('d10', 0, pages[0].path);
      await scan.insertPageAt('d10', 99, pages[1].path);
      final ScanDocument doc = current('d10');
      expect(doc.pageCount, doc.pagePaths.length);
      expect(doc.pagePaths.length, 3);
      expect(doc.thumbnailPath, doc.pagePaths.first);
    });

    test('extract pages into a new document keeps edits and does not touch the source', () async {
      final List<File> pages = <File>[await page('a11', 50, 50, 10), await page('b11', 50, 50, 100), await page('c11', 50, 50, 200)];
      final ScanDocument d = await makeDoc('d11', pages);
      await boot(<ScanDocument>[d]);
      await scan.addWatermarkLayer('d11', const WatermarkLayer(pageIndex: 2, text: 'last', placement: _mid));
      final String before = fingerprint(current('d11'));
      final ScanDocument? part = await scan.extractToNewDocument('d11', <int>[2, 0], 'Part');
      expect(part, isNotNull);
      expect(part!.pagePaths.length, 2);
      expect(part.watermarkLayers.single.pageIndex, 0, reason: 'layer did not follow its page into the new document');
      expect(fingerprint(current('d11')), before);
    });
  });

  group('export of edited documents', () {
    Future<ScanDocument> heavy(String id) async {
      final List<File> pages = <File>[
        await page('h1$id', 120, 80, 20),
        await page('h2$id', 80, 120, 140),
        await page('h3$id', 100, 100, 230),
      ];
      final ScanDocument d = await makeDoc(id, pages);
      await boot(<ScanDocument>[d]);
      await scan.addSignatureInk(id, 'ink1', inkPng(), 'Me', 2.5);
      final File ann = await annotationPng('ann$id');
      for (int i = 0; i < 3; i++) {
        await scan.addSignatureLayer(id, i, const SignaturePlacement(pctX: 0.7, pctY: 0.8, rotationDegrees: 15, scale: 1.4), inkId: 'ink1');
        await scan.addAnnotateLayer(id, AnnotateLayer(pageIndex: i, bytesPath: ann.path, placement: _mid));
        await scan.addWatermarkLayer(id, WatermarkLayer(pageIndex: i, text: 'CONFIDENTIAL', placement: const SignaturePlacement(pctX: 0.5, pctY: 0.2, rotationDegrees: -30)));
        await scan.addStampLayer(id, StampLayer(id: 'st$i', pageIndex: i, kind: 'text', placement: _mid, text: 'Paid'));
        await scan.addStampLayer(id, StampLayer(id: 'cb$i', pageIndex: i, kind: 'checkbox', placement: const SignaturePlacement(pctX: 0.2, pctY: 0.5), checked: true));
        await scan.addStampLayer(id, StampLayer(id: 'dt$i', pageIndex: i, kind: 'date', placement: const SignaturePlacement(pctX: 0.3, pctY: 0.9), text: '2026-10-18'));
        await scan.addStampLayer(id, StampLayer(id: 'sl$i', pageIndex: i, kind: 'seal', placement: const SignaturePlacement(pctX: 0.8, pctY: 0.3), text: 'APPROVED'));
      }
      await scan.updatePageTransform(id, 0, const PageTransform(rotationTurns: 1, filter: FilterType.blackAndWhite));
      await scan.updatePageTransform(id, 1, PageTransform(cropRect: const Rect.fromLTWH(10, 10, 60, 90), resizeWidth: 50, resizeHeight: 75, filter: FilterType.colorEnhance, filterIntensity: 0.5));
      await scan.updatePageTransform(id, 2, const PageTransform(rotationTurns: 3, eraserStrokes: <Map<String, dynamic>>[
        <String, dynamic>{'points': <List<double>>[<double>[0.1, 0.1], <double>[0.9, 0.9]], 'color': 0xFFFFFFFF, 'width': 0.05},
        <String, dynamic>{'points': <List<double>>[<double>[0.0, 0.0], <double>[0.5, 0.5]], 'color': 0xFF000000, 'width': 0.05, 'rect': true},
      ]));
      await settle();
      return current(id);
    }

    for (final ExportFormat f in <ExportFormat>[ExportFormat.pdf, ExportFormat.jpg, ExportFormat.png, ExportFormat.docx, ExportFormat.txt]) {
      test('heavily edited document exports as ${f.name}', () async {
        final ScanDocument doc = await heavy('x_${f.name}');
        final Directory out = Directory('${tmp.path}/out_${f.name}')..createSync();
        final List<String> files = await ExportService().export(
          document: f == ExportFormat.txt ? doc.copyWith(ocrText: 'hello world') : doc,
          format: f,
          outputDirectoryPath: out.path,
          docxMode: ExportDocxMode.imageEmbedded,
        );
        expect(files, isNotEmpty);
        for (final String path in files) {
          expect(File(path).existsSync(), isTrue, reason: path);
          expect(File(path).lengthSync(), greaterThan(0), reason: path);
        }
        if (f == ExportFormat.pdf) {
          expect(String.fromCharCodes(File(files.single).readAsBytesSync().take(5)), '%PDF-');
        }
        if (f == ExportFormat.jpg || f == ExportFormat.png) {
          expect(files.length, 3, reason: 'one picture per page expected');
        }
      });
    }

    test('text export of a document with no text says so instead of writing an empty file', () async {
      final ScanDocument doc = await heavy('x_notext');
      final Directory out = Directory('${tmp.path}/out_notext')..createSync();
      await expectLater(
        ExportService().export(document: doc, format: ExportFormat.txt, outputDirectoryPath: out.path),
        throwsA(isA<ExportNoTextException>()),
      );
      expect(out.listSync(), isEmpty, reason: 'an empty file was left behind');
    });

    test('every compression level exports the edited PDF', () async {
      final ScanDocument doc = await heavy('x_comp');
      for (final CompressionTier tier in CompressionTier.values) {
        final Directory out = Directory('${tmp.path}/out_${tier.name}')..createSync();
        final List<String> files = await ExportService().export(
          document: doc, format: ExportFormat.pdf, outputDirectoryPath: out.path, compression: tier,
        );
        expect(File(files.single).lengthSync(), greaterThan(100), reason: '$tier');
      }
    });

    test('share rendering of an edited document returns one file per page', () async {
      final ScanDocument doc = await heavy('x_share');
      final List<String> files = await ExportService().renderPagesForShare(doc);
      expect(files.length, 3);
      for (final String f in files) {
        expect(File(f).lengthSync(), greaterThan(0));
      }
    });
  });

  group('odd pictures and odd edits', () {
    test('1 x 1 page with every edit exports without crashing', () async {
      final ScanDocument d = await makeDoc('o1', <File>[await page('tiny', 1, 1, 100)]);
      await boot(<ScanDocument>[d]);
      await scan.addWatermarkLayer('o1', const WatermarkLayer(pageIndex: 0, text: 'x', placement: _mid));
      await scan.updatePageTransform('o1', 0, const PageTransform(rotationTurns: 1, filter: FilterType.grayscale));
      final List<String> files = await ExportService().export(
        document: current('o1'), format: ExportFormat.pdf, outputDirectoryPath: (Directory('${tmp.path}/o1')..createSync()).path,
      );
      expect(File(files.single).lengthSync(), greaterThan(0));
    });

    test('very wide and very tall pages export in every picture format', () async {
      final ScanDocument d = await makeDoc('o2', <File>[await page('wide', 3000, 20, 80), await page('tall', 20, 3000, 160)]);
      await boot(<ScanDocument>[d]);
      for (int i = 0; i < 2; i++) {
        await scan.updatePageTransform('o2', i, const PageTransform(rotationTurns: 1));
        await scan.addStampLayer('o2', StampLayer(id: 'q$i', pageIndex: i, kind: 'text', placement: _mid, text: 'Hello'));
      }
      for (final ExportFormat f in <ExportFormat>[ExportFormat.pdf, ExportFormat.jpg, ExportFormat.png]) {
        final Directory out = Directory('${tmp.path}/o2_${f.name}')..createSync();
        final List<String> files = await ExportService().export(document: current('o2'), format: f, outputDirectoryPath: out.path);
        expect(files, isNotEmpty, reason: f.name);
      }
    });

    test('crop larger than the page, zero-size crop and negative crop do not break export', () async {
      final ScanDocument d = await makeDoc('o3', <File>[await page('cp', 60, 40, 100), await page('cq', 60, 40, 110), await page('cr', 60, 40, 120)]);
      await boot(<ScanDocument>[d]);
      await scan.updatePageTransform('o3', 0, const PageTransform(cropRect: Rect.fromLTWH(0, 0, 500, 500)));
      await scan.updatePageTransform('o3', 1, const PageTransform(cropRect: Rect.fromLTWH(10, 10, 0, 0)));
      await scan.updatePageTransform('o3', 2, const PageTransform(cropRect: Rect.fromLTWH(-20, -20, 30, 30)));
      final List<String> files = await ExportService().export(
        document: current('o3'), format: ExportFormat.png, outputDirectoryPath: (Directory('${tmp.path}/o3')..createSync()).path,
      );
      expect(files.length, 3);
    });

    test('a missing annotation file fails export with a clear error, not a crash', () async {
      final ScanDocument d = await makeDoc('o4', <File>[await page('ma', 40, 40, 100)]);
      await boot(<ScanDocument>[d]);
      await scan.addAnnotateLayer('o4', AnnotateLayer(pageIndex: 0, bytesPath: '${tmp.path}/annotate_pages/missing.png', placement: _mid));
      await expectLater(
        ExportService().export(document: current('o4'), format: ExportFormat.pdf, outputDirectoryPath: (Directory('${tmp.path}/o4')..createSync()).path),
        throwsA(isA<ExportFailedException>()),
      );
    });

    test('a layer on a page number that no longer exists is ignored by export', () async {
      final ScanDocument d = await makeDoc('o5', <File>[await page('ga', 40, 40, 100)]);
      await boot(<ScanDocument>[d]);
      await scan.addWatermarkLayer('o5', const WatermarkLayer(pageIndex: 7, text: 'ghost', placement: _mid));
      final List<String> files = await ExportService().export(
        document: current('o5'), format: ExportFormat.pdf, outputDirectoryPath: (Directory('${tmp.path}/o5')..createSync()).path,
      );
      expect(File(files.single).lengthSync(), greaterThan(0));
    });

    test('30 page document with edits on every page exports in reasonable time', () async {
      final List<File> pages = <File>[for (int i = 0; i < 30; i++) await page('big$i', 300, 400, (i * 8) % 255)];
      final ScanDocument d = await makeDoc('o6', pages);
      await boot(<ScanDocument>[d]);
      for (int i = 0; i < 30; i++) {
        await scan.addWatermarkLayer('o6', WatermarkLayer(pageIndex: i, text: 'DRAFT', placement: _mid));
        await scan.updatePageTransform('o6', i, PageTransform(rotationTurns: i % 4));
      }
      final Stopwatch sw = Stopwatch()..start();
      final List<String> files = await ExportService().export(
        document: current('o6'), format: ExportFormat.pdf, outputDirectoryPath: (Directory('${tmp.path}/o6')..createSync()).path,
      );
      sw.stop();
      expect(File(files.single).lengthSync(), greaterThan(0));
      expect(sw.elapsed.inSeconds, lessThan(90), reason: '30 small pages took ${sw.elapsed.inSeconds}s');
    });
  });

  group('atomic watermark and save-failure helpers', () {
    test('editing watermark text, copying to all pages and clearing a page are one undo step each', () async {
      final List<File> pages = <File>[await page('w1', 40, 60, 10), await page('w2', 40, 60, 20), await page('w3', 40, 60, 30)];
      final ScanDocument d = await makeDoc('wm', pages);
      await boot(<ScanDocument>[d]);
      const WatermarkLayer a = WatermarkLayer(pageIndex: 0, text: 'DRAFT', placement: _mid);
      await scan.addWatermarkLayer('wm', a);
      await scan.replaceWatermarkLayer('wm', a, a.copyWith(text: 'FINAL'));
      expect(current('wm').watermarkLayers.map((WatermarkLayer l) => l.text), <String>['FINAL']);
      await scan.undoManager.undo();
      expect(current('wm').watermarkLayers.map((WatermarkLayer l) => l.text), <String>['DRAFT']);
      await scan.undoManager.redo();
      await scan.addWatermarkLayerToPages('wm', current('wm').watermarkLayers.single, <int>[1, 2]);
      expect(current('wm').watermarkLayers.length, 3);
      await scan.undoManager.undo();
      expect(current('wm').watermarkLayers.length, 1);
      await scan.undoManager.redo();
      await scan.clearWatermarksOnPage('wm', 1);
      expect(current('wm').watermarkLayers.map((WatermarkLayer l) => l.pageIndex).toSet(), <int>{0, 2});
      await settle();
      expect((await fromDb('wm')).watermarkLayers.length, 2);
    });

    test('retryFailedSaves with nothing failed clears the banner counter', () async {
      final ScanDocument d = await makeDoc('rt', <File>[await page('r1', 40, 60, 10)]);
      await boot(<ScanDocument>[d]);
      scan.failedSaves.value = 2;
      expect(await scan.retryFailedSaves(), isTrue);
      expect(scan.failedSaves.value, 0);
    });
  });
}
