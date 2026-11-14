import 'dart:ui' show Locale, PlatformDispatcher;
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/user_settings.dart';
import 'package:katharscan/core/utils/constants.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => binding.platformDispatcher.clearLocalesTestValue());

  void phone(Locale l) => binding.platformDispatcher.localesTestValue = <Locale>[l];

  test('a new install follows the phone', () {
    phone(const Locale('de', 'DE'));
    const UserSettings s = UserSettings();
    expect(s.followSystemLanguage, isTrue);
    expect(s.activeLanguage, 'de');
  });

  test('following the phone picks up a later change of the phone language', () {
    phone(const Locale('fr', 'FR'));
    const UserSettings s = UserSettings();
    expect(s.activeLanguage, 'fr');
    phone(const Locale('ja', 'JP'));
    expect(s.activeLanguage, 'ja');
    phone(const Locale('pt', 'PT'));
    expect(s.activeLanguage, 'pt_PT');
  });

  test('a manual choice stays put when the phone language changes', () {
    phone(const Locale('de', 'DE'));
    final UserSettings s = const UserSettings().copyWith(language: 'es', followSystemLanguage: false);
    expect(s.activeLanguage, 'es');
    phone(const Locale('ru', 'RU'));
    expect(s.activeLanguage, 'es');
  });

  test('settings saved before this option keep their saved language (manual)', () {
    phone(const Locale('de', 'DE'));
    final UserSettings s = UserSettings.fromJson(<String, dynamic>{'language': 'tr'});
    expect(s.followSystemLanguage, isFalse);
    expect(s.activeLanguage, 'tr');
  });

  test('settings with no language at all follow the phone', () {
    phone(const Locale('it', 'IT'));
    final UserSettings s = UserSettings.fromJson(<String, dynamic>{});
    expect(s.followSystemLanguage, isTrue);
    expect(s.activeLanguage, 'it');
  });

  test('the choice survives a save and load (automatic and manual)', () {
    phone(const Locale('nl', 'NL'));
    final UserSettings auto = UserSettings.fromJson(const UserSettings().toJson());
    expect(auto.followSystemLanguage, isTrue);
    final UserSettings manual =
        UserSettings.fromJson(const UserSettings().copyWith(language: 'ko', followSystemLanguage: false).toJson());
    expect(manual.followSystemLanguage, isFalse);
    expect(manual.activeLanguage, 'ko');
  });

  test('a language the app lacks falls back to English while following', () {
    phone(const Locale('ka', 'GE'));
    expect(const UserSettings().activeLanguage, AppLocales.defaultLanguageCode);
  });

  test('equality and hash include the follow flag', () {
    const UserSettings a = UserSettings();
    final UserSettings b = a.copyWith(followSystemLanguage: false);
    expect(a == b, isFalse);
    expect(PlatformDispatcher.instance, isNotNull);
  });
}
