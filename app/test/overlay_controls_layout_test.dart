// test/overlay_controls_layout_test.dart
//
// The editing controls under the page must stay compact (page area is precious)
// and must not overflow at phone width, for every layer type and in a long language.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/ink_board.dart';

void main() {
  for (final Locale locale in const <Locale>[Locale('en'), Locale('de'), Locale('ru')]) {
    for (final double width in <double>[360, 411]) {
      for (final LayerType type in <LayerType>[LayerType.watermark, LayerType.annotate, LayerType.text, LayerType.signature]) {
        testWidgets('controls ${type.name} at ${width.toInt()}dp ${locale.languageCode}: compact, no overflow', (WidgetTester tester) async {
          void noop() {}
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: OverlayEditControls(
                  layerType: type,
                  rotationDegrees: -45,
                  scale: 1.5,
                  opacity: 1.0,
                  fontSize: 100,
                  onRotateLeft: noop, onRotateRight: noop, onScaleDown: noop, onScaleUp: noop,
                  onCopyAll: noop, onClearThis: noop, onRemove: noop, onClearAll: noop,
                  onOpacityDown: noop, onOpacityUp: noop, onFontSizeDown: noop, onFontSizeUp: noop,
                  onTools: noop, onDone: noop,
                  showClearThis: type == LayerType.signature,
                ),
              ),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'overflow or layout error');
          final Size size = tester.getSize(find.byType(OverlayEditControls));
          // One row of step buttons (40) + one row of actions (44) + padding.
          expect(size.height, lessThanOrEqualTo(96), reason: 'controls take ${size.height}dp');
        });
      }
    }
  }
}
