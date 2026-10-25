// Drives the real app on the emulator through the features changed in the editing
// overhaul: the three clear scopes with Undo, Fill typing and re-edit, deleting a
// saved signature, the Compress sheet, and the filters on large pages.
// Prints "EMU: <id> | PASS|FAIL|INFO | detail" like the other suites.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/providers/scan_provider.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/main.dart' as app;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void note(String id, String status, String detail) {
  // ignore: avoid_print
  print('EMU: $id | $status | ${detail.replaceAll('\n', ' / ')}');
}

Future<File> pagePng(String name, {int w = 900, int h = 1200}) async {
  final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 40))
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: 40))
    ..addText('Feature page $name');
  final ui.Paragraph para = b.build()..layout(ui.ParagraphConstraints(width: w - 100.0));
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  c.drawParagraph(para, const ui.Offset(50, 50));
  final ui.Image im = await rec.endRecording().toImage(w, h);
  final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
  final Directory dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'feature_pages'))..createSync(recursive: true);
  final File f = File(p.join(dir.path, '$name.png'));
  await f.writeAsBytes(bd!.buffer.asUint8List());
  return f;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('F features: clear scopes, Fill, saved signature, Compress sheet, filters', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    final LocalStorageService seed = LocalStorageService();
    await seed.initialize();
    final List<File> pages = <File>[for (int i = 0; i < 3; i++) await pagePng('f$i')];
    final img.Image art = img.Image(width: 160, height: 80, numChannels: 4);
    img.fill(art, color: img.ColorRgba8(220, 30, 30, 255));
    final File annFile = File(p.join(pages.first.parent.path, 'ann.png'))..writeAsBytesSync(img.encodePng(art));
    final img.Image ink = img.Image(width: 200, height: 70, numChannels: 4);
    img.fill(ink, color: img.ColorRgba8(0, 0, 200, 255));
    final DateTime now = DateTime.now();
    await seed.saveDocument(ScanDocument(
      id: 'feat_doc', title: 'Feature document', pageCount: 3,
      pagePaths: pages.map((File f) => f.path).toList(),
      createdAt: now, updatedAt: now, ocrText: 'x', thumbnailPath: pages.first.path,
      watermarkLayers: <WatermarkLayer>[
        for (int i = 0; i < 3; i++) WatermarkLayer(id: 'wm$i', pageIndex: i, text: 'CONFIDENTIAL', placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5), opacity: 0.8),
      ],
      annotateLayers: <AnnotateLayer>[
        for (int i = 0; i < 3; i++) AnnotateLayer(id: 'an$i', pageIndex: i, bytesPath: annFile.path, placement: const SignaturePlacement(pctX: 0.5, pctY: 0.25)),
      ],
      signatureInks: <SignatureInk>[SignatureInk(id: 'ink1', bytes: Uint8List.fromList(img.encodePng(ink)), label: 'Signer 1', aspect: 200 / 70)],
      signatureLayers: <SignatureLayer>[
        for (int i = 0; i < 3; i++) SignatureLayer(pageIndex: i, placement: const SignaturePlacement(pctX: 0.5, pctY: 0.75), inkId: 'ink1'),
      ],
    ));

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
    final ScanProvider scan = Provider.of<ScanProvider>(ctx, listen: false);
    ScanDocument doc() => scan.documents.value.firstWhere((ScanDocument d) => d.id == 'feat_doc');

    void check(String id, bool ok, String detail) => note(id, ok ? 'PASS' : 'FAIL', detail);

    Future<void> tapText(String text) async {
      final Finder f = find.text(text);
      if (f.evaluate().isEmpty) throw StateError('text "$text" not on screen');
      await tester.ensureVisible(f.first);
      await tester.tap(f.first, warnIfMissed: false);
      await pumpFor(900);
    }

    Future<void> tapTray(String label) async {
      final Finder f = find.byKey(ValueKey<String>('trayTarget:$label'));
      if (f.evaluate().isEmpty) throw StateError('tray item "$label" not found');
      await tester.ensureVisible(f);
      await pumpFor(300);
      await tester.tap(f, warnIfMissed: false);
      await pumpFor(1500);
    }

    Future<void> section(String id, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, st) {
        note(id, 'FAIL', 'exception: $e / ${st.toString().split('\n').take(3).join(' / ')}');
      }
    }

    // ---- F1: the three clear scopes, through the real buttons, with Undo ----
    await section('F1-clear-scopes', () async {
      router.go('/');
      await pumpFor(500);
      router.push('/edit/feat_doc');
      await pumpFor(3000);
      await tester.tap(find.text('CONFIDENTIAL').first, warnIfMissed: false);
      await pumpFor(1000);
      check('F1-controls-visible', find.text(l10n.clearThis).evaluate().isNotEmpty && find.text(l10n.clearPage).evaluate().isNotEmpty && find.text(l10n.clearAllPages).evaluate().isNotEmpty,
          'Clear this / Clear page / Clear all pages all on screen');
      // Clear this: only the selected watermark.
      await tapText(l10n.clearThis);
      check('F1-clear-this', doc().watermarkLayers.length == 2 && doc().annotateLayers.length == 3, 'watermarks ${doc().watermarkLayers.length} (want 2), pictures ${doc().annotateLayers.length} (want 3)');
      check('F1-message', find.text(l10n.clearedCount(1)).evaluate().isNotEmpty, 'Cleared 1 message shown');
      await tapText(l10n.undoTooltip);
      check('F1-undo-this', doc().watermarkLayers.length == 3, 'after Undo ${doc().watermarkLayers.length} watermarks (want 3)');
      // Clear page: select a watermark again, clear this page only.
      await tester.tap(find.text('CONFIDENTIAL').first, warnIfMissed: false);
      await pumpFor(900);
      await tapText(l10n.clearPage);
      final int onPage0 = doc().watermarkLayers.where((WatermarkLayer l) => l.pageIndex == 0).length;
      check('F1-clear-page', doc().watermarkLayers.length == 2 && onPage0 == 0 && doc().annotateLayers.length == 3, 'watermarks ${doc().watermarkLayers.length} (want 2), on page 1: $onPage0 (want 0), pictures ${doc().annotateLayers.length} (want 3)');
      await tapText(l10n.undoTooltip);
      check('F1-undo-page', doc().watermarkLayers.length == 3, 'after Undo ${doc().watermarkLayers.length} (want 3)');
      // Clear all pages.
      await tester.tap(find.text('CONFIDENTIAL').first, warnIfMissed: false);
      await pumpFor(900);
      await tapText(l10n.clearAllPages);
      check('F1-clear-all-pages', doc().watermarkLayers.isEmpty && doc().annotateLayers.length == 3 && doc().signatureLayers.length == 3, 'watermarks ${doc().watermarkLayers.length} (want 0), pictures ${doc().annotateLayers.length} (want 3), signatures ${doc().signatureLayers.length} (want 3)');
      await tapText(l10n.undoTooltip);
      check('F1-undo-all-pages', doc().watermarkLayers.length == 3, 'after Undo ${doc().watermarkLayers.length} (want 3)');
    });

    // ---- F2: Fill, type with the real keyboard path, place, re-edit, export ----
    await section('F2-fill', () async {
      router.go('/');
      await pumpFor(500);
      router.push('/edit/feat_doc');
      await pumpFor(3000);
      await tapTray(l10n.fillTooltip);
      final Finder canvas = find.byWidgetPredicate((Widget w) => w.runtimeType.toString() == 'DocumentCanvas');
      final Rect r = tester.getRect(canvas.first);
      // An empty spot: the seeded layers sit at 25 to 75 percent of the height.
      final Offset at = Offset(r.left + r.width * 0.3, r.top + r.height * 0.86);
      note('F2-info', 'INFO', 'canvas $r, tap at $at, fill hint shown: ${find.text(l10n.fillTapHint).evaluate().isNotEmpty}');
      await tester.tapAt(at);
      await pumpFor(1500);
      final Finder field = find.byKey(const ValueKey<String>('fillTextField'));
      check('F2-typing-bar', field.evaluate().isNotEmpty, 'typing bar opened after tapping the page');
      await tester.enterText(field, 'Emulator fill text');
      await pumpFor(600);
      await tester.tap(find.byKey(const ValueKey<String>('fillDone')));
      await pumpFor(1200);
      final List<StampLayer> fills = doc().stampLayers.where((StampLayer l) => l.kind == 'fill').toList();
      check('F2-placed', fills.length == 1 && fills.first.text == 'Emulator fill text' && fills.first.isFlowFill, 'fill layers ${fills.length}, text "${fills.isEmpty ? '' : fills.first.text}"');
      // Double tap reopens it.
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await pumpFor(1500);
      final bool reopened = find.byKey(const ValueKey<String>('fillTextField')).evaluate().isNotEmpty;
      check('F2-double-tap-edit', reopened, 'double tap reopened the typing bar');
      if (reopened) {
        await tester.enterText(find.byKey(const ValueKey<String>('fillTextField')), 'Edited text');
        await pumpFor(500);
        await tester.tap(find.byKey(const ValueKey<String>('fillDone')));
        await pumpFor(1200);
        final List<StampLayer> after = doc().stampLayers.where((StampLayer l) => l.kind == 'fill').toList();
        check('F2-edited', after.length == 1 && after.first.text == 'Edited text', 'fill layers ${after.length}, text "${after.isEmpty ? '' : after.first.text}"');
      }
      // The exported page carries the text pixels.
      final Uint8List with_ = await ExportService().renderPageForOutput(doc(), 0);
      final Uint8List without = await ExportService().renderPageForOutput(doc().copyWith(stampLayers: const <StampLayer>[]), 0);
      final img.Image a = img.decodePng(with_)!, b = img.decodePng(without)!;
      int diff = 0;
      for (int y = 0; y < a.height; y += 2) {
        for (int x = 0; x < a.width; x += 2) {
          if ((a.getPixel(x, y).r - b.getPixel(x, y).r).abs() > 60) diff++;
        }
      }
      check('F2-exported', diff > 40, 'exported page differs from the page without Fill text in $diff sampled pixels');
    });

    // ---- F3: delete a saved signature from the picker, then Undo ----
    await section('F3-saved-signature', () async {
      router.go('/');
      await pumpFor(500);
      router.push('/edit/feat_doc');
      await pumpFor(3000);
      await tapTray(l10n.signatureTitle);
      final Finder del = find.byKey(const ValueKey<String>('deleteSavedSignature'));
      check('F3-delete-visible', del.evaluate().isNotEmpty, 'delete button in the signature picker');
      if (del.evaluate().isNotEmpty) {
        // Opening the Signature tool puts a copy of the active signature on this page.
        final int inks0 = doc().signatureInks.length, places0 = doc().signatureLayers.length;
        await tester.tap(del.first, warnIfMissed: false);
        await pumpFor(1500);
        check('F3-deleted', doc().signatureInks.length == inks0 - 1 && doc().signatureLayers.length < places0, 'inks ${doc().signatureInks.length} (was $inks0), placements ${doc().signatureLayers.length} (was $places0)');
        await tapText(l10n.undoTooltip);
        await pumpFor(1000);
        check('F3-undo', doc().signatureInks.length == inks0 && doc().signatureLayers.length == places0, 'inks ${doc().signatureInks.length} (want $inks0), placements ${doc().signatureLayers.length} (want $places0)');
      }
    });

    // ---- F4: Compress sheet ----
    await section('F4-compress-sheet', () async {
      router.go('/');
      await pumpFor(500);
      router.push('/edit/feat_doc');
      await pumpFor(3000);
      await tapTray(l10n.compressLabel);
      final Finder sheet = find.byKey(const ValueKey<String>('compressFormat'));
      check('F4-sheet-opens', sheet.evaluate().isNotEmpty, 'sheet opened instead of the export screen');
      for (int i = 0; i < 100 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await pumpFor(300);
      }
      final int sizes = find.textContaining(RegExp(r'^\d+(\.\d)? (MB|KB)$')).evaluate().length;
      check('F4-sizes', sizes == 3, '$sizes real sizes shown (want 3)');
      await tester.tap(find.byKey(const ValueKey<String>('compressCard:small')), warnIfMissed: false);
      await pumpFor(500);
      await tester.tap(find.byKey(const ValueKey<String>('compressGo')), warnIfMissed: false);
      await pumpFor(3000);
      final bool onExport = find.text(l10n.compressSmall).evaluate().isNotEmpty;
      check('F4-export-preselected', onExport, 'export screen opened with the compression choices');
    });

    // ---- F5: filters on a large shadowed page: time, memory, pixels ----
    await section('F5-filters-large', () async {
      const int w = 4000, h = 3000;
      final img.Image big = img.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final double shade = 1.0 - 0.5 * x / w;
          final bool inkPx = (y ~/ 150) % 3 == 0 && (y % 150) < 12 && x > 300 && x < 3700;
          final double k = shade * (inkPx ? 0.2 : 1.0);
          big.setPixelRgb(x, y, (240 * k).round(), (235 * k).round(), (225 * k).round());
        }
      }
      final File f = File(p.join(pages.first.parent.path, 'big.jpg'))..writeAsBytesSync(img.encodeJpg(big, quality: 90));
      final DateTime t0 = DateTime.now();
      for (final FilterType ft in <FilterType>[FilterType.shadowRemoval, FilterType.blackAndWhite, FilterType.grayscale, FilterType.colorEnhance]) {
        final ScanDocument d = ScanDocument(
          id: 'big_${ft.name}', title: 'big', pageCount: 1, pagePaths: <String>[f.path],
          createdAt: now, updatedAt: now, ocrText: '', thumbnailPath: f.path,
          pageTransforms: <int, PageTransform>{0: PageTransform(filter: ft)},
        );
        final DateTime s = DateTime.now();
        final Uint8List out = await ExportService().renderPageForOutput(d, 0);
        final img.Image o = img.decodePng(out)!;
        final int ms = DateTime.now().difference(s).inMilliseconds;
        // Paper on the shadowed (right) side and writing on the left.
        final img.Pixel paperRight = o.getPixel(w - 100, 20);
        final img.Pixel inkLeft = o.getPixel(1000, 5);
        bool ok;
        switch (ft) {
          case FilterType.shadowRemoval:
            ok = paperRight.g > 215 && inkLeft.g < 120;
          case FilterType.blackAndWhite:
            ok = paperRight.r == 255 && inkLeft.r == 0;
          case FilterType.grayscale:
            ok = paperRight.r == paperRight.g && paperRight.g == paperRight.b;
          case FilterType.colorEnhance:
            ok = paperRight.g > 100;
          case FilterType.none:
            ok = true;
        }
        check('F5-${ft.name}', ok && o.width == w, '12 MP page in $ms ms; paper right ${paperRight.r.toInt()}, ink ${inkLeft.r.toInt()}');
      }
      note('F5-total', 'INFO', 'all four filters on 12 MP: ${DateTime.now().difference(t0).inSeconds} s');
    });
  });
}
