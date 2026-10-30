// Drives the real detail, full-screen and export screens on the emulator and checks
// what carries from one to the next: page, signatures, edited preview, undo.
// Prints "EMU: F-<name> | PASS|FAIL | detail" rows, read back from the check annotations.
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
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/main.dart' as app;
import 'package:katharscan/widgets/scan_preview_card.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void row(String id, bool ok, String detail) {
  // ignore: avoid_print
  print('EMU: F-$id | ${ok ? 'PASS' : 'FAIL'} | ${detail.replaceAll('\n', ' / ')}');
}

Future<File> pagePng(String name) async {
  final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 40))
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: 40))
    ..addText('Page $name Thank you for your order. ' * 14);
  final ui.Paragraph para = b.build()..layout(const ui.ParagraphConstraints(width: 800));
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec);
  c.drawRect(const ui.Rect.fromLTWH(0, 0, 900, 1200), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  c.drawParagraph(para, const ui.Offset(50, 50));
  final ui.Image im = await rec.endRecording().toImage(900, 1200);
  final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
  final Directory dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'flow_pages'))..createSync(recursive: true);
  final File f = File(p.join(dir.path, '$name.png'));
  await f.writeAsBytes(bd!.buffer.asUint8List());
  return f;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('F1 what carries between detail, full screen and export', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    final LocalStorageService seed = LocalStorageService();
    await seed.initialize();
    final List<File> pages = <File>[await pagePng('one'), await pagePng('two'), await pagePng('three')];
    final img.Image ink = img.Image(width: 200, height: 70, numChannels: 4);
    img.fill(ink, color: img.ColorRgba8(0, 0, 200, 255));
    final Uint8List inkBytes = Uint8List.fromList(img.encodePng(ink));
    final DateTime now = DateTime.now();
    final ScanDocument doc = ScanDocument(
      id: 'flow_doc',
      title: 'Flow document',
      pageCount: 3,
      pagePaths: pages.map((File f) => f.path).toList(),
      createdAt: now,
      updatedAt: now,
      ocrText: 'Page one',
      thumbnailPath: pages.first.path,
      signatureInks: <SignatureInk>[SignatureInk(id: 'ink1', bytes: inkBytes, label: 'Signer 1', aspect: 200 / 70)],
      signatureLayers: const <SignatureLayer>[SignatureLayer(pageIndex: 0, placement: SignaturePlacement(pctX: 0.5, pctY: 0.75), inkId: 'ink1')],
      // Page 2 is cropped to its left half: a narrow page.
      pageTransforms: <int, PageTransform>{1: const PageTransform(cropRect: Rect.fromLTWH(0, 0, 450, 1200))},
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
    final ScanProvider scan = Provider.of<ScanProvider>(ctx, listen: false);

    String pageText(int n) => l10n.pageIndicator(n, 3);

    try {
      // --- Detail: swipe to page 2; the tab must stay on the page view.
      router.push('/scan/flow_doc');
      await pumpFor(2500);
      final TabBar bar = tester.widget<TabBar>(find.byType(TabBar));
      final Finder pv = find.byType(PageView).first;
      await tester.fling(pv, const Offset(-400, 0), 1500);
      await pumpFor(1200);
      final bool onTwo = find.text(pageText(2)).evaluate().isNotEmpty;
      row('swipe-page', onTwo && bar.controller!.index == 0, 'page 2 shown=$onTwo, tab index=${bar.controller!.index}');

      // --- Detail to full screen keeps the page.
      await tester.tap(find.byIcon(Icons.open_in_full).first);
      await pumpFor(2500);
      final bool fullOnTwo = find.text(pageText(2)).evaluate().isNotEmpty;
      row('page-to-fullscreen', fullOnTwo, 'full screen shows page 2=$fullOnTwo');

      // --- Swipe in full screen to page 3, add a signature placement there (what signing saves), go back.
      await tester.fling(find.byType(PageView).first, const Offset(-400, 0), 1500);
      await pumpFor(1200);
      final bool fullOnThree = find.text(pageText(3)).evaluate().isNotEmpty;
      row('swipe-fullscreen', fullOnThree, 'full screen shows page 3=$fullOnThree');
      final ScanDocument now1 = scan.documents.value.firstWhere((ScanDocument d) => d.id == 'flow_doc');
      await scan.setSignatureState(
        'flow_doc',
        now1.signatureInks,
        <SignatureLayer>[...now1.signatureLayers, const SignatureLayer(pageIndex: 2, placement: SignaturePlacement(pctX: 0.4, pctY: 0.4), inkId: 'ink1')],
      );
      await pumpFor(500);
      await tester.tap(find.byKey(const ValueKey<String>('fullClose')));
      await pumpFor(2500);
      final String where = router.routerDelegate.currentConfiguration.uri.toString();
      row('after-close', find.byType(ScanPreviewCard).evaluate().isNotEmpty, 'route=$where, detail card present=${find.byType(ScanPreviewCard).evaluate().isNotEmpty}');

      // --- Back on detail: page 3 shown, and its signature controller knows the new placement.
      final bool backOnThree = find.text(pageText(3)).evaluate().isNotEmpty;
      row('page-back-to-detail', backOnThree, 'detail shows page 3=$backOnThree');
      final Finder cardFinder = find.byType(ScanPreviewCard);
      final bool knows = cardFinder.evaluate().isNotEmpty && (tester.widget<ScanPreviewCard>(cardFinder).inkController?.inkPlacements['ink1']?.containsKey(2) ?? false);
      row('signature-back-to-detail', knows, 'detail controller has the page-3 placement=$knows');

      // --- Undo on detail.
      final Finder undo = find.byKey(const ValueKey<String>('detailUndo'));
      final bool undoThere = undo.evaluate().isNotEmpty;
      if (undoThere) {
        await scan.addWatermarkLayer('flow_doc', const WatermarkLayer(pageIndex: 0, text: 'UNDOME', placement: SignaturePlacement(pctX: 0.5, pctY: 0.5)));
        await pumpFor(800);
        final bool enabled = tester.widget<IconButton>(undo).onPressed != null;
        await tester.tap(undo);
        await pumpFor(1000);
        final bool gone = scan.documents.value.firstWhere((ScanDocument d) => d.id == 'flow_doc').watermarkLayers.every((WatermarkLayer w) => w.text != 'UNDOME');
        row('detail-undo', enabled && gone, 'undo enabled after an edit=$enabled, edit undone=$gone');
      } else {
        row('detail-undo', false, 'undo button not found on the detail screen');
      }

      // --- Export opens on the viewed page and shows the cropped page cropped.
      await tester.fling(find.byType(PageView).first, const Offset(400, 0), 1500);
      await pumpFor(1000);
      router.push('/export', extra: <String>['flow_doc']);
      await pumpFor(3500);
      final int viewed = scan.viewedPageFor('flow_doc');
      final bool exportShows = find.text(l10n.pageIndicator(viewed + 1, 3)).evaluate().isNotEmpty;
      row('page-to-export', exportShows, 'viewed page ${viewed + 1}, export shows it=$exportShows');
      // Go to page 2 (the cropped one) and measure the picture.
      final Finder next = find.byIcon(Icons.chevron_right);
      while (!find.text(pageText(2)).evaluate().isNotEmpty) {
        final bool wasAfter = find.text(pageText(3)).evaluate().isNotEmpty;
        await tester.tap(wasAfter ? find.byIcon(Icons.chevron_left).first : next.first);
        await pumpFor(1500);
        if (find.text(pageText(2)).evaluate().isNotEmpty) break;
      }
      await pumpFor(2500);
      final Iterable<Element> memImgs = find.byWidgetPredicate((Widget w) => w is Image && w.image is MemoryImage).evaluate();
      if (memImgs.isEmpty) {
        row('export-cropped-preview', false, 'no preview picture found');
      } else {
        final RenderBox rb = memImgs.first.renderObject! as RenderBox;
        final double aspect = rb.size.width / rb.size.height;
        // Raw page is 0.75; cropped to its left half it is 0.375.
        row('export-cropped-preview', aspect < 0.5, 'preview shape width/height=${aspect.toStringAsFixed(3)} (cropped page 0.375, raw 0.75)');
      }
    } catch (e, st) {
      row('error', false, '$e ${st.toString().split('\n').take(5).join(' / ')}');
    }
    row('done', true, 'finished');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
