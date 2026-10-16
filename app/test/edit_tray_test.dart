// Every tray button must have a touch target of at least 48 x 48.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/edit_tray.dart';

void main() {
  for (final bool compact in <bool>[true, false]) {
    testWidgets('tray touch targets are at least 48 px (compact: $compact)', (WidgetTester tester) async {
      void noop() {}
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EditTray(
            compact: compact,
            onMarkup: noop, onSign: noop, onWatermark: noop, onOcr: noop, onConvert: noop,
            onCompress: noop, onRotate: noop, onResize: noop, onPages: noop, onFilter: noop,
            onCrop: noop, onText: noop, onNote: noop, onDate: noop, onCheckbox: noop,
            onSeal: noop, onPrint: noop, onEmail: noop, onErase: noop,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      final Finder targets = find.byWidgetPredicate((Widget w) =>
          w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('trayTarget:'));
      expect(targets, findsWidgets);
      for (final Element e in targets.evaluate()) {
        final Size size = e.size!;
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });
  }
}
