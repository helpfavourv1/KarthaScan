import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/scan_preview_card.dart';

/// The detail screen's row above the page must show "Fullscreen" and the page
/// label at their normal size on a normal phone, in every language.
void main() {
  Widget leading() => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        IconButton(icon: const Icon(Icons.undo, size: 20), onPressed: () {}),
        IconButton(icon: const Icon(Icons.redo, size: 20), onPressed: null),
      ]);

  Future<Map<String, double>> measure(WidgetTester tester, Locale locale, double width, {bool done = false}) async {
    tester.view.physicalSize = Size(width * 2, 800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PreviewHeaderRow(
          leading: leading(),
          current: 0,
          total: 3,
          onPrev: null,
          onNext: () {},
          onFullscreen: () {},
          onDone: done ? () {} : null,
          accent: Colors.blue,
          textSecondary: Colors.grey,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    double scale(Finder f) => tester.renderObject<RenderBox>(f).getTransformTo(null).getMaxScaleOnAxis();
    return <String, double>{
      'label': scale(find.byKey(const ValueKey<String>('detailPageLabel'))),
      'chip': scale(find.descendant(of: find.byKey(const ValueKey<String>('detailFullscreen')), matching: find.byType(RichText)).first),
    };
  }

  for (final Locale l in <Locale>[const Locale('en'), const Locale('de'), const Locale('ru'), const Locale('pt'), const Locale('es')]) {
    testWidgets('${l.languageCode}: 411dp phone shows Fullscreen and page label at full size', (WidgetTester tester) async {
      final Map<String, double> m = await measure(tester, l, 411);
      // ignore: avoid_print
      print('MEASURE ${l.languageCode} 411: $m');
      expect(m['chip'], closeTo(1.0, 0.01), reason: 'Fullscreen chip scaled: $m');
      expect(m['label'], closeTo(1.0, 0.01), reason: 'page label scaled: $m');
      expect(tester.takeException(), isNull);
    });

    testWidgets('${l.languageCode}: 360dp phone scales the row together, no overflow, still readable', (WidgetTester tester) async {
      final Map<String, double> m = await measure(tester, l, 360);
      // ignore: avoid_print
      print('MEASURE ${l.languageCode} 360: $m');
      expect(m['chip'], greaterThan(0.8), reason: '360dp scale $m');
      expect(tester.takeException(), isNull);
    });
  }
}
