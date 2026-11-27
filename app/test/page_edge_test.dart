import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/widgets/page_edge.dart';

void main() {
  testWidgets('edge overlay paints, ignores touches and follows zoom', (tester) async {
    final TransformationController c = TransformationController();
    int taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.white))),
          PageEdgeOverlay(pageSize: const Size(200, 300), controller: c),
        ]),
      ),
    ));
    expect(find.byKey(const ValueKey<String>('pageEdge')), findsOneWidget);
    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1, reason: 'the edge must not swallow touches');
    c.value = Matrix4.identity()..scale(2.0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('backdrop is darker than a white page in both themes', () {
    expect(pageBackdropColor(false).computeLuminance(), lessThan(0.8));
    expect(pageBackdropColor(true).computeLuminance(), lessThan(0.1));
  });

  test('print, export and share code never use the screen edge', () {
    for (final String f in <String>[
      'lib/core/services/export_service.dart',
      'lib/core/services/print_service.dart',
    ]) {
      final File file = File(f);
      if (file.existsSync()) {
        expect(file.readAsStringSync().contains('page_edge'), isFalse, reason: f);
      }
    }
  });
}
