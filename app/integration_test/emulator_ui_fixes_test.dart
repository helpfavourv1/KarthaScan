// Drives the real app on the emulator for the screen fixes: the "Cleared N" snackbar
// disappearing by itself, the crop presets reshaping the band, the export undo/redo
// arrows (and no overflow on a narrow phone), and the real gap above the ad banner.
// Prints "EMU: <id> | PASS|FAIL|INFO | detail" like the other suites.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/providers/scan_provider.dart';
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
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  c.drawRect(const ui.Rect.fromLTWH(80, 80, 300, 40), ui.Paint()..color = const ui.Color(0xFF000000));
  final ui.Image im = await rec.endRecording().toImage(w, h);
  final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
  final Directory dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'uifix_pages'))..createSync(recursive: true);
  final File f = File(p.join(dir.path, '$name.png'));
  await f.writeAsBytes(bd!.buffer.asUint8List());
  return f;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('U ui fixes: snackbar, crop presets, export undo/redo, banner gaps', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    final LocalStorageService seed = LocalStorageService();
    await seed.initialize();
    final List<File> pages = <File>[for (int i = 0; i < 2; i++) await pagePng('u$i')];
    final DateTime now = DateTime.now();
    await seed.saveDocument(ScanDocument(
      id: 'ui_doc', title: 'UI document', pageCount: 2,
      pagePaths: pages.map((File f) => f.path).toList(),
      createdAt: now, updatedAt: now, ocrText: 'x', thumbnailPath: pages.first.path,
      watermarkLayers: <WatermarkLayer>[
        for (int i = 0; i < 2; i++) WatermarkLayer(id: 'wm$i', pageIndex: i, text: 'CONFIDENTIAL', placement: const SignaturePlacement(pctX: 0.5, pctY: 0.5), opacity: 0.8),
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
    ScanDocument doc() => scan.documents.value.firstWhere((ScanDocument d) => d.id == 'ui_doc');
    void check(String id, bool ok, String detail) => note(id, ok ? 'PASS' : 'FAIL', detail);

    Future<void> section(String id, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, st) {
        note(id, 'FAIL', 'exception: $e / ${st.toString().split('\n').take(3).join(' / ')}');
      }
    }

    Rect? rectOf(String typeName) {
      final Iterable<Element> found = find.byWidgetPredicate((Widget w) => w.runtimeType.toString() == typeName).evaluate();
      if (found.isEmpty) return null;
      final RenderObject? ro = found.first.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
      return ro.localToGlobal(Offset.zero) & ro.size;
    }

    Future<void> tapTray(String label) async {
      final Finder f = find.byKey(ValueKey<String>('trayTarget:$label'));
      if (f.evaluate().isEmpty) throw StateError('tray item "$label" not found');
      await tester.ensureVisible(f);
      await pumpFor(300);
      await tester.tap(f, warnIfMissed: false);
      await pumpFor(1500);
    }

    Future<void> restoreAll() async {
      for (int i = 0; i < 10 && scan.undoManager.canUndo; i++) {
        await scan.undoManager.undo();
      }
      await pumpFor(500);
    }

    // ---- U1: the Cleared snackbar goes away by itself, and does not follow you to other pages ----
    await section('U1-snackbar', () async {
      router.go('/');
      await pumpFor(500);
      router.push('/edit/ui_doc');
      await pumpFor(3000);
      await restoreAll();
      await tester.tap(find.text('CONFIDENTIAL').first, warnIfMissed: false);
      await pumpFor(900);
      await tester.tap(find.text(l10n.clearThis).first, warnIfMissed: false);
      await pumpFor(700);
      final Finder bar = find.byType(SnackBar);
      check('U1-shown', bar.evaluate().isNotEmpty, 'snackbar visible right after Clear this');
      final bool named = find.textContaining(l10n.watermarkLabel).evaluate().isNotEmpty;
      check('U1-names-item', named, 'message names the item type "${l10n.watermarkLabel}"');
      await pumpFor(5500);
      check('U1-auto-dismiss', find.byType(SnackBar).evaluate().isEmpty, 'snackbar gone about 6 s after it appeared (4 s duration)');
      // Clear again and leave: it must not reappear on home.
      await restoreAll();
      await tester.tap(find.text('CONFIDENTIAL').first, warnIfMissed: false);
      await pumpFor(900);
      await tester.tap(find.text(l10n.clearThis).first, warnIfMissed: false);
      await pumpFor(500);
      router.go('/');
      await pumpFor(6000);
      check('U1-not-on-home', find.byType(SnackBar).evaluate().isEmpty, 'no snackbar left on the home screen');
    });

    // ---- U2: every crop preset reshapes the band ----
    await section('U2-crop-presets', () async {
      router.go('/');
      await pumpFor(500);
      router.push('/edit/ui_doc');
      await pumpFor(3000);
      await tapTray(l10n.cropLabel);
      check('U2-open', find.byKey(const Key('cropArea')).evaluate().isNotEmpty, 'crop sheet opened');
      final Map<String, double> want = <String, double>{'a4': 210 / 297, 'letter': 8.5 / 11, 'id': 54 / 85.6, 'square': 1.0};
      for (final MapEntry<String, double> e in want.entries) {
        final Finder chip = find.byKey(Key('cropAspect:${e.key}'));
        for (int i = 0; i < 5 && chip.evaluate().isEmpty; i++) {
          final Finder anchor = find.byKey(const Key('cropAspect:a4'));
          if (anchor.evaluate().isEmpty) break;
          await tester.drag(anchor, const Offset(-250, 0), warnIfMissed: false);
          await pumpFor(300);
        }
        if (chip.evaluate().isEmpty) {
          check('U2-${e.key}', false, 'chip not found');
          continue;
        }
        await tester.ensureVisible(chip);
        await tester.tap(chip, warnIfMissed: false);
        await pumpFor(600);
        // Apply it; the stored crop tells us the band's shape on the 900x1200 page.
        await tester.tap(find.byKey(const Key('cropConfirm')), warnIfMissed: false);
        await pumpFor(1800);
        final PageTransform? t = doc().pageTransforms[0];
        final Rect? box = t?.cropRect;
        if (box == null) {
          check('U2-${e.key}', false, 'no crop stored after confirm');
        } else {
          final double ratio = box.width / box.height;
          check('U2-${e.key}', (ratio - e.value).abs() < 0.03 || (t?.cropAspect != null && (t!.cropAspect! - e.value).abs() < 0.03),
              'band ${box.width.round()}x${box.height.round()} ratio ${ratio.toStringAsFixed(3)} want ${e.value.toStringAsFixed(3)}, aspect stored ${t?.cropAspect}');
        }
        // Reopen for the next preset.
        await tapTray(l10n.cropLabel);
      }
      // Close the sheet.
      if (find.byKey(const Key('cropArea')).evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(5, 40));
        await pumpFor(600);
      }
    });

    // ---- U3: export undo/redo arrows, on the normal screen and a narrow phone ----
    Future<void> exportRun(String tag) async {
      router.go('/');
      await pumpFor(500);
      router.push('/export', extra: <String, dynamic>{'ids': <String>['ui_doc'], 'format': 'pdf'});
      await pumpFor(3500);
      final Size sz = tester.view.physicalSize / tester.view.devicePixelRatio;
      final Finder undo = find.byKey(const ValueKey<String>('exportUndo'));
      final Finder redo = find.byKey(const ValueKey<String>('exportRedo'));
      check('U3-$tag-present', undo.evaluate().isNotEmpty && redo.evaluate().isNotEmpty, 'undo and redo arrows on the export page row at ${sz.width.round()}x${sz.height.round()}dp');
      final Object? ex = tester.takeException();
      check('U3-$tag-no-overflow', ex == null, 'no layout exception: ${ex ?? 'none'}');
      if (undo.evaluate().isNotEmpty) {
        final Rect r = tester.getRect(undo.first);
        check('U3-$tag-on-screen', r.right <= sz.width && r.left >= 0, 'undo arrow at x=${r.left.round()}..${r.right.round()} inside width ${sz.width.round()}');
      }
    }

    await section('U3-export-normal', () => exportRun('normal'));
    await section('U3-export-narrow', () async {
      tester.view.physicalSize = const Size(320 * 2.625, 640 * 2.625);
      await pumpFor(800);
      await exportRun('narrow320');
      tester.view.resetPhysicalSize();
      await pumpFor(800);
    });
    await section('U3-export-undo-works', () async {
      router.go('/');
      await pumpFor(500);
      router.push('/edit/ui_doc');
      await pumpFor(3000);
      await restoreAll();
      final int before = doc().watermarkLayers.length;
      await tester.tap(find.text('CONFIDENTIAL').first, warnIfMissed: false);
      await pumpFor(900);
      await tester.tap(find.text(l10n.clearThis).first, warnIfMissed: false);
      await pumpFor(900);
      final int after = doc().watermarkLayers.length;
      router.go('/');
      await pumpFor(400);
      router.push('/export', extra: <String, dynamic>{'ids': <String>['ui_doc'], 'format': 'pdf'});
      await pumpFor(3500);
      final Finder undo = find.byKey(const ValueKey<String>('exportUndo'));
      if (undo.evaluate().isEmpty) {
        check('U3-undo-works', false, 'undo arrow missing');
        return;
      }
      await tester.tap(undo.first, warnIfMissed: false);
      await pumpFor(1500);
      check('U3-undo-works', after == before - 1 && doc().watermarkLayers.length == before, 'watermarks before $before, after clear $after, after export-undo ${doc().watermarkLayers.length}');
    });

    // ---- U4: the real gap between the tray (or buttons) and the banner ----
    Future<void> gap(String id, String route, {Object? extra, String? above}) async {
      router.go('/');
      await pumpFor(500);
      router.push(route, extra: extra);
      await pumpFor(3500);
      final Rect? banner = rectOf('ConditionalBanner');
      final Rect? ref = above == null ? null : rectOf(above);
      if (banner == null) {
        note('U4-$id', 'INFO', 'no banner on screen (ads not loaded on this emulator)');
        return;
      }
      final String bn = 'banner y=${banner.top.round()}..${banner.bottom.round()}';
      if (ref == null) {
        note('U4-$id', 'INFO', '$bn, reference widget $above not found');
        return;
      }
      final double g = banner.top - ref.bottom;
      note('U4-$id', 'INFO', '$bn, $above bottom ${ref.bottom.round()}, gap ${g.toStringAsFixed(1)} dp');
      return;
    }

    await section('U4-detail', () => gap('detail', '/scan/ui_doc', above: 'EditTray'));
    await section('U4-fullscreen', () => gap('fullscreen', '/edit/ui_doc', above: 'EditTray'));
    await section('U4-export', () => gap('export', '/export', extra: <String, dynamic>{'ids': <String>['ui_doc'], 'format': 'pdf'}, above: 'ExportScreen'));

    note('U-done', 'INFO', 'finished');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
