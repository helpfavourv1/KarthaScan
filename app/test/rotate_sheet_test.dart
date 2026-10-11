// The tray's rotate sheet must start from the page's current orientation
// and still return only the new turns.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/widgets/rotate_resize_sheet.dart';

void main() {
  testWidgets('rotate sheet starts at the saved rotation and returns the delta', (WidgetTester tester) async {
    final Directory tmp = Directory.systemTemp.createTempSync('rot_sheet_');
    final File f = File('${tmp.path}/p.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 20)));

    int? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async {
            result = await showModalBottomSheet<int>(
              context: context,
              isScrollControlled: true,
              builder: (_) => RotateResizeSheet(
                mode: RotateResizeMode.rotate,
                imagePath: f.path,
                initialTurns: 1,
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Starts at the page's current 90 degrees, not at 0.
    expect(find.text('90°'), findsOneWidget);
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);

    await tester.tap(find.byIcon(Icons.rotate_90_degrees_ccw));
    await tester.pump();
    expect(find.text('180°'), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(result, 1, reason: 'only the new turn is returned, the caller adds it');
  });
}
