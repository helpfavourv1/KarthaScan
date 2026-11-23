import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/edit_tray.dart';

void main() {
  Widget tray({required List<String> log, bool compact = true}) {
    void rec(String n) => log.add(n);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: EditTray(
            compact: compact,
            onMarkup: () => rec('markup'),
            onSign: () => rec('sign'),
            onWatermark: () => rec('watermark'),
            onOcr: () => rec('ocr'),
            onConvert: () => rec('convert'),
            onCompress: () => rec('compress'),
            onRotate: () => rec('rotate'),
            onResize: () => rec('resize'),
            onPages: () => rec('pages'),
            onFilter: () => rec('filter'),
            onCrop: () => rec('crop'),
            onText: () => rec('text'),
            onNote: () => rec('note'),
            onDate: () => rec('date'),
            onCheckbox: () => rec('checkbox'),
            onSeal: () => rec('seal'),
            onPrint: () => rec('print'),
            onEmail: () => rec('email'),
            onErase: () => rec('erase'),
            onRevert: () => rec('revert'),
            onFill: () => rec('fill'),
          ),
        ),
      ),
    );
  }

  testWidgets('All tools button lists every tool and runs the chosen one', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(822, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final List<String> log = <String>[];
    await tester.pumpWidget(tray(log: log));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('trayAllTools')), findsOneWidget);
    // The button is at least 48 x 48 to tap.
    final Size sz = tester.getSize(find.byKey(const ValueKey<String>('trayAllTools')));
    expect(sz.width, greaterThanOrEqualTo(48));
    expect(sz.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const ValueKey<String>('trayAllTools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('allToolsGrid')), findsOneWidget);
    final int tiles = find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('allTools:')).evaluate().length;
    expect(tiles, 21, reason: 'every one of the 21 tools is listed');
    await tester.ensureVisible(find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('allTools:')).first);
    await tester.tap(find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('allTools:')).first);
    await tester.pumpAndSettle();
    expect(log, <String>['markup']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more-tools cue shows while tools are off the right edge', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(tray(log: <String>[]));
    await tester.pumpAndSettle();
    final Finder cue = find.byKey(const ValueKey<String>('trayMoreCue'));
    expect(cue, findsOneWidget);
    double opacity() => tester.widget<AnimatedOpacity>(find.ancestor(of: cue, matching: find.byType(AnimatedOpacity))).opacity;
    expect(opacity(), 1.0);
    // Scroll to the end: the cue goes away.
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(-3000, 0));
    await tester.pumpAndSettle();
    expect(opacity(), 0.0);
  });
}
