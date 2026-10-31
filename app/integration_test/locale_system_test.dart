// Runs on the emulator once per system language (the workflow sets the phone's
// language, then runs this with --dart-define=EXPECT=<app language>). Checks that
// a fresh install starts in the phone's language, that a manual choice replaces it,
// and that the manual choice is read back from storage the way a restart would.
// Prints "EMU: F-<name> | PASS|FAIL | detail" rows.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/providers/settings_provider.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/core/utils/constants.dart';
import 'package:katharscan/main.dart' as app;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kExpect = String.fromEnvironment('EXPECT', defaultValue: 'en');

void row(String id, bool ok, String detail) {
  // ignore: avoid_print
  print('EMU: F-$id | ${ok ? 'PASS' : 'FAIL'} | ${detail.replaceAll('\n', ' / ')}');
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('L1 system language, manual choice, stored choice', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('hasSeenOnboarding', true);
    final ui.Locale sys = ui.PlatformDispatcher.instance.locale;
    final String tag = '$sys';

    await app.main();
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final BuildContext ctx = tester.element(find.byType(Scaffold).first);
    final SettingsProvider settings = Provider.of<SettingsProvider>(ctx, listen: false);

    final String first = settings.settings.value.language;
    final ui.Locale shown = Localizations.localeOf(ctx);
    final ui.Locale want = AppLocales.toLocale(kExpect);
    row('L-$kExpect-first', first == kExpect && shown == want, 'phone=$tag expected=$kExpect app=$first shown=$shown');

    final String manual = kExpect == 'de' ? 'fr' : 'de';
    await settings.setLanguage(manual);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final ui.Locale shown2 = Localizations.localeOf(tester.element(find.byType(Scaffold).first));
    row('L-$kExpect-manual', shown2 == AppLocales.toLocale(manual), 'chose $manual, shown=$shown2');

    await prefs.reload();
    final String stored = (await LocalStorageService().loadSettings()).language;
    row('L-$kExpect-stored', stored == manual, 'a new start reads $stored (chose $manual)');
  });
}
