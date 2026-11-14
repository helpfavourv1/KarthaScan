// Runs on the emulator in three separate app processes (the workflow force-stops the
// app between them, and changes the phone language before the last):
//   PHASE=A  fresh install: follows the phone; then a manual language is chosen and saved.
//   PHASE=B  after a real force-stop: the manual choice is still there; then
//            "System default" is chosen.
//   PHASE=C  after the phone language changed and another force-stop: the app follows it.
// Prints "EMU: F-R-... | PASS|FAIL|INFO | detail" rows.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/providers/settings_provider.dart';
import 'package:katharscan/core/utils/constants.dart';
import 'package:katharscan/main.dart' as app;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kPhase = String.fromEnvironment('PHASE', defaultValue: 'A');

void row(String id, String verdict, String detail) {
  // ignore: avoid_print
  print('EMU: F-R-$id | $verdict | ${detail.replaceAll('\n', ' / ')}');
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('R restart and system language', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (kPhase == 'A') {
      await prefs.clear();
      await prefs.setBool('hasSeenOnboarding', true);
    }
    final ui.Locale sys = ui.PlatformDispatcher.instance.locale;
    final String phone = AppLocales.fromDevice(sys);

    await app.main();
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final BuildContext ctx = tester.element(find.byType(Scaffold).first);
    final SettingsProvider settings = Provider.of<SettingsProvider>(ctx, listen: false);
    ui.Locale shown() => Localizations.localeOf(tester.element(find.byType(Scaffold).first));
    Future<void> settle() async {
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    if (kPhase == 'A') {
      row('A-follows-phone', shown() == AppLocales.toLocale(phone) ? 'PASS' : 'FAIL', 'phone=$sys expected=$phone shown=${shown()}');
      await settings.setLanguage('es');
      await settle();
      row('A-manual', shown().languageCode == 'es' ? 'PASS' : 'FAIL', 'chose es, shown=${shown()}');
      await prefs.setString('restart_marker', 'A');
    } else if (kPhase == 'B') {
      await prefs.reload();
      if (prefs.getString('restart_marker') != 'A') {
        row('B-restart', 'INFO', 'inconclusive: the saved data was wiped between the runs, so a restart cannot be proven this way');
        return;
      }
      final bool kept = shown().languageCode == 'es' && !settings.settings.value.followSystemLanguage;
      row('B-manual-kept', kept ? 'PASS' : 'FAIL', 'after a force-stop: shown=${shown()} follow=${settings.settings.value.followSystemLanguage}');
      await settings.setLanguage(AppLocales.systemLanguage);
      await settle();
      row('B-system-chosen', shown() == AppLocales.toLocale(phone) ? 'PASS' : 'FAIL', 'chose System default, phone=$sys expected=$phone shown=${shown()}');
    } else {
      await prefs.reload();
      if (prefs.getString('restart_marker') != 'A') {
        row('C-restart', 'INFO', 'inconclusive: the saved data was wiped between the runs');
        return;
      }
      row('C-follow-kept', settings.settings.value.followSystemLanguage ? 'PASS' : 'FAIL', 'System default still chosen after a force-stop');
      row('C-follows-change', shown() == AppLocales.toLocale(phone) && phone != 'de' ? 'PASS' : 'FAIL', 'phone is now $sys expected=$phone shown=${shown()}');
    }
  });
}
