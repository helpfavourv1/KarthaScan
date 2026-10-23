// Measures the real screens on the emulator: how tall each editing row is, how
// much of the screen the document gets, and what sits next to the ad banner.
// Prints "EMU: M-<screen> | INFO | ..." measurements and "SHOT: <id> | <base64 jpeg>"
// small screenshots so they can be read back from the check annotations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/main.dart' as app;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void note(String id, String detail) {
  // ignore: avoid_print
  print('EMU: $id | INFO | ${detail.replaceAll('\n', ' / ')}');
}

Future<File> pagePng(String name, {int w = 900, int h = 1200}) async {
  final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 40))
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: 40))
    ..addText('Invoice 2026-0417 Thank you for your order. ' * 14);
  final ui.Paragraph para = b.build()..layout(ui.ParagraphConstraints(width: w - 100.0));
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  c.drawParagraph(para, const ui.Offset(50, 50));
  final ui.Image im = await rec.endRecording().toImage(w, h);
  final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
  final Directory dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'measure_pages'))..createSync(recursive: true);
  final File f = File(p.join(dir.path, '$name.png'));
  await f.writeAsBytes(bd!.buffer.asUint8List());
  return f;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('M1 measure every screen and editing state', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    final LocalStorageService seed = LocalStorageService();
    await seed.initialize();
    final File pg1 = await pagePng('m1');
    final File pg2 = await pagePng('m2');

    final img.Image art = img.Image(width: 160, height: 80, numChannels: 4);
    img.fill(art, color: img.ColorRgba8(220, 30, 30, 255));
    final File annFile = File(p.join(pg1.parent.path, 'ann.png'))..writeAsBytesSync(img.encodePng(art));
    final img.Image ink = img.Image(width: 200, height: 70, numChannels: 4);
    img.fill(ink, color: img.ColorRgba8(0, 0, 200, 255));
    final Uint8List inkBytes = Uint8List.fromList(img.encodePng(ink));

    final DateTime now = DateTime.now();
    final ScanDocument doc = ScanDocument(
      id: 'measure_doc',
      title: 'Measure document',
      pageCount: 2,
      pagePaths: <String>[pg1.path, pg2.path],
      createdAt: now,
      updatedAt: now,
      ocrText: 'Invoice 2026-0417 Thank you for your order.',
      thumbnailPath: pg1.path,
      watermarkLayers: const <WatermarkLayer>[
        WatermarkLayer(id: 'wm1', pageIndex: 0, text: 'CONFIDENTIAL', placement: SignaturePlacement(pctX: 0.5, pctY: 0.5), opacity: 0.8),
      ],
      annotateLayers: <AnnotateLayer>[
        AnnotateLayer(id: 'an1', pageIndex: 0, bytesPath: annFile.path, placement: const SignaturePlacement(pctX: 0.5, pctY: 0.25)),
      ],
      signatureInks: <SignatureInk>[SignatureInk(id: 'ink1', bytes: inkBytes, label: 'Signer 1', aspect: 200 / 70)],
      signatureLayers: const <SignatureLayer>[SignatureLayer(pageIndex: 0, placement: SignaturePlacement(pctX: 0.5, pctY: 0.75), inkId: 'ink1')],
    );
    await seed.saveDocument(doc);

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

    Rect? rectOf(String typeName, {bool last = false}) {
      final Iterable<Element> found = find.byWidgetPredicate((Widget w) => w.runtimeType.toString() == typeName).evaluate();
      if (found.isEmpty) return null;
      final Element e = last ? found.last : found.first;
      final RenderObject? ro = e.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
      final Offset o = ro.localToGlobal(Offset.zero);
      return o & ro.size;
    }

    Rect? textRect(String text) {
      final Iterable<Element> found = find.text(text).evaluate();
      if (found.isEmpty) return null;
      final RenderObject? ro = found.first.renderObject;
      if (ro is! RenderBox || !ro.hasSize) return null;
      return ro.localToGlobal(Offset.zero) & ro.size;
    }

    String fmt(Rect? r) => r == null ? 'none' : 'y=${r.top.round()}..${r.bottom.round()} h=${r.height.round()} w=${r.width.round()}';

    Future<void> measure(String id, {List<String> types = const <String>[], List<String> texts = const <String>[]}) async {
      await pumpFor(1200);
      final double dpr = tester.view.devicePixelRatio;
      final Size sz = tester.view.physicalSize / dpr;
      final EdgeInsets pad = EdgeInsets.fromViewPadding(tester.view.padding, dpr);
      final StringBuffer sb = StringBuffer('screen ${sz.width.round()}x${sz.height.round()}dp, status ${pad.top.round()}, nav ${pad.bottom.round()}');
      for (final String t in types) {
        sb.write(' | $t ${fmt(rectOf(t))}');
      }
      for (final String t in texts) {
        sb.write(' | "$t" ${fmt(textRect(t))}');
      }
      sb.write(' | banner ${fmt(rectOf('ConditionalBanner'))}');
      note('M-$id', sb.toString());
      // Small screenshot, sent back through the check annotations.
      try {
        final Iterable<Element> boundaries = find.byType(RepaintBoundary).evaluate();
        final RenderRepaintBoundary rb = boundaries.first.renderObject! as RenderRepaintBoundary;
        final String? b64 = await tester.runAsync<String?>(() async {
          final ui.Image im = await rb.toImage(pixelRatio: 0.35);
          final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
          if (bd == null) return null;
          final img.Image? d = img.decodePng(bd.buffer.asUint8List());
          if (d == null) return null;
          return base64Encode(img.encodeJpg(d, quality: 55));
        });
        if (b64 != null) {
          // ignore: avoid_print
          print('SHOT: $id | $b64');
        }
      } catch (e) {
        note('M-$id-shot', 'screenshot failed: $e');
      }
    }

    Future<void> go(String route) async {
      router.go('/');
      await pumpFor(600);
      router.push(route);
      await pumpFor(2500);
    }

    Future<void> tapTray(String label) async {
      final Finder f = find.byKey(ValueKey<String>('trayTarget:$label'));
      if (f.evaluate().isEmpty) {
        note('M-tray-$label', 'tray item not found');
        return;
      }
      await tester.ensureVisible(f);
      await tester.tap(f, warnIfMissed: false);
      await pumpFor(1500);
    }

    const List<String> editorTypes = <String>[
      'DocumentCanvas', 'EditTray', 'LayerControlPanel', 'OverlayEditControls', 'SignatureEditorBar', 'SignatureOverlayControls',
    ];

    // Home and settings.
    await measure('home', types: const <String>['EditTray']);
    await go('/settings');
    await measure('settings');

    // Document screen: pages tab (compact tray) and text tab.
    await go('/scan/measure_doc');
    await measure('scan-detail-pages', types: const <String>['EditTray', 'ScanPreviewCard', 'DocumentCanvas', 'TabBar']);
    final Finder textTab = find.byType(Tab);
    if (textTab.evaluate().length > 1) {
      await tester.tap(textTab.at(1));
      await pumpFor(1000);
      await measure('scan-detail-text', texts: <String>[l10n.commonShare, l10n.exportTitle, l10n.commonCopy]);
    }

    // Full-screen editor.
    await go('/edit/measure_doc');
    await measure('editor-plain', types: editorTypes);

    if (find.text('CONFIDENTIAL').evaluate().isNotEmpty) {
      await tester.tap(find.text('CONFIDENTIAL').first, warnIfMissed: false);
      await pumpFor(1000);
      await measure('editor-watermark-selected', types: editorTypes, texts: <String>[l10n.commonDone, l10n.copyAll, l10n.clearThis, l10n.commonRemove, l10n.clearAll]);
    } else {
      note('M-editor-watermark-selected', 'watermark text not found on the page');
    }

    final Finder annImg = find.descendant(of: find.byWidgetPredicate((Widget w) => w.runtimeType.toString() == 'AnnotateOverlayPage'), matching: find.byType(Image));
    if (annImg.evaluate().isNotEmpty) {
      await tester.tap(annImg.first, warnIfMissed: false);
      await pumpFor(1000);
      await measure('editor-annotation-selected', types: editorTypes, texts: <String>[l10n.commonDone]);
    } else {
      note('M-editor-annotation-selected', 'annotation picture not found');
    }

    await tapTray(l10n.signatureTitle);
    await measure('editor-signature-mode', types: editorTypes, texts: <String>[l10n.commonDone, l10n.addSignature]);

    await tapTray(l10n.fillTooltip);
    await measure('editor-fill-mode', types: editorTypes, texts: <String>[l10n.commonDone]);
    // Tap the page to open the fill sheet.
    final Rect? canvas = rectOf('DocumentCanvas');
    if (canvas != null) {
      await tester.tapAt(Offset(canvas.center.dx, canvas.top + canvas.height * 0.62));
      await pumpFor(1800);
      await measure('editor-fill-sheet-open', types: <String>['TextStampSheet', 'DocumentCanvas'], texts: <String>[l10n.commonCreate, l10n.commonCancel]);
      final Finder cancel = find.text(l10n.commonCancel);
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel.first);
        await pumpFor(800);
      }
    }

    await tapTray(l10n.textLabel);
    await measure('editor-text-tool', types: editorTypes);

    // Export screen, PDF and JPG.
    router.go('/');
    await pumpFor(400);
    router.push('/export', extra: <String, dynamic>{'ids': <String>['measure_doc'], 'format': 'pdf'});
    await pumpFor(3500);
    await measure('export-pdf', texts: <String>[l10n.commonShare, l10n.saveToDeviceButton, l10n.compressSmall, l10n.compressMedium, l10n.filterOriginal]);
    router.go('/');
    await pumpFor(400);
    router.push('/export', extra: <String, dynamic>{'ids': <String>['measure_doc'], 'format': 'jpg'});
    await pumpFor(3500);
    await measure('export-jpg', texts: <String>[l10n.commonShare, l10n.saveToDeviceButton]);

    note('M-done', 'finished');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
