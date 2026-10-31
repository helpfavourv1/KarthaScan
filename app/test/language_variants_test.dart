// Chinese (Simplified / Traditional), Portuguese (Brazil / Portugal) and Norwegian
// (Bokmål / Nynorsk) are separate app languages. These tests check the translation
// files are complete and really are the variant they claim to be, and that choosing,
// storing and looking up each variant works.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/utils/constants.dart';
import 'package:katharscan/core/utils/date_formatter.dart';
import 'package:katharscan/core/utils/language_names.dart';
import 'package:katharscan/l10n/app_localizations.dart';

Map<String, String> arb(String code) {
  final Map<String, dynamic> raw = jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map<String, dynamic>;
  return <String, String>{
    for (final MapEntry<String, dynamic> e in raw.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
}

String locale(String code) => (jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map<String, dynamic>)['@@locale'] as String;

List<String> placeholders(String s) => RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}', unicode: false).allMatches(s).map((m) => m.group(1)!).toList()..sort();

void main() {
  final Map<String, String> en = arb('en');

  test('each variant file declares its own locale', () {
    expect(locale('zh_Hant'), 'zh_Hant');
    expect(locale('pt_PT'), 'pt_PT');
    expect(locale('nn'), 'nn');
    expect(locale('zh'), 'zh');
    expect(locale('pt'), 'pt');
    expect(locale('no'), 'no');
  });

  test('Traditional Chinese and Nynorsk translate every string; European Portuguese adds to Brazilian', () {
    for (final String code in <String>['zh_Hant', 'nn']) {
      final Map<String, String> t = arb(code);
      expect(en.keys.where((String k) => !t.containsKey(k)), isEmpty, reason: '$code is missing strings');
      expect(t.keys.where((String k) => !en.containsKey(k)), isEmpty, reason: '$code has strings the app does not use');
      expect(t.values.where((String v) => v.trim().isEmpty), isEmpty, reason: '$code has empty strings');
    }
    final Map<String, String> pt = arb('pt'), ptPt = arb('pt_PT');
    expect(ptPt.keys.where((String k) => !pt.containsKey(k)), isEmpty);
    expect(ptPt.length, greaterThan(100), reason: 'European Portuguese should override the words that differ');
  });

  test('placeholders such as {count} survive in every variant', () {
    for (final String code in <String>['zh_Hant', 'nn', 'pt_PT', 'pt']) {
      final Map<String, String> t = arb(code);
      for (final MapEntry<String, String> e in t.entries) {
        expect(placeholders(e.value), placeholders(en[e.key]!), reason: '$code ${e.key}');
      }
    }
  });

  test('the Chinese files use the right script', () {
    const List<String> simplifiedOnly = <String>['导出', '设置', '删除', '打印', '保存', '文档', '扫描', '设备', '应用'];
    final String hant = arb('zh_Hant').values.join('\n');
    final String hans = arb('zh').values.join('\n');
    for (final String w in simplifiedOnly) {
      expect(hant.contains(w), isFalse, reason: 'Traditional file contains Simplified "$w"');
    }
    expect(hans.contains('導出'), isFalse);
    expect(hans.contains('匯出'), isFalse);
    expect(arb('zh_Hant')['exportTitle'], '匯出');
    expect(arb('zh')['exportTitle'], '导出');
  });

  test('the Portuguese files use the right country\'s words', () {
    final Map<String, String> pt = arb('pt'), ptPt = arb('pt_PT');
    const List<String> europeanOnly = <String>['Guardar', 'Partilhar', 'Eliminar', 'ficheiro', 'ecrã', 'Definições', 'A exportar', 'telemóvel'];
    const List<String> brazilianOnly = <String>['Salvar', 'Compartilhar', 'Excluir', 'arquivo', 'tela ', 'Configurações', 'Exportando', 'celular'];
    final String brazil = pt.values.join('\n');
    final String europe = ptPt.values.join('\n');
    for (final String w in brazilianOnly) {
      expect(europe.contains(w), isFalse, reason: 'European file contains Brazilian "$w"');
    }
    for (final String w in europeanOnly) {
      expect(brazil.contains(w), isFalse, reason: 'Brazilian file contains European "$w"');
    }
    expect(ptPt['commonSave'], 'Guardar');
    expect(pt['commonSave'], 'Salvar');
  });

  test('Nynorsk is not Bokmål', () {
    final Map<String, String> nn = arb('nn'), no = arb('no');
    final String text = nn.values.join('\n');
    expect(RegExp(r'\bikke\b').hasMatch(text), isFalse, reason: 'Bokmål "ikke" in the Nynorsk file');
    expect(RegExp(r'\bnoe\b').hasMatch(text), isFalse);
    expect(nn['deleteScanMessage'], 'Dette kan ikkje angrast.');
    expect(no['deleteScanMessage'], 'Dette kan ikke angres.');
    expect(nn.entries.where((MapEntry<String, String> e) => e.value != no[e.key]).length, greaterThan(300));
  });

  test('every app language has a native name and an English name, with no duplicates', () {
    expect(AppLocales.supportedLanguageCodes.toSet().length, AppLocales.supportedLanguageCodes.length);
    for (final String c in AppLocales.supportedLanguageCodes) {
      expect(kLanguageNativeNames.containsKey(c), isTrue, reason: 'no native name for $c');
      expect(kLanguageEnglishNames.containsKey(c), isTrue, reason: 'no English name for $c');
    }
    expect(AppLocales.supportedLanguageCodes.length, 29);
  });

  test('each language resolves to a locale the app has translations for', () {
    for (final String c in AppLocales.supportedLanguageCodes) {
      final Locale l = AppLocales.toLocale(c);
      expect(AppLocalizations.supportedLocales.contains(l), isTrue, reason: '$c -> $l');
      expect(lookupAppLocalizations(l).commonCancel, isNotEmpty);
    }
  });

  test('the variants show their own words', () {
    expect(lookupAppLocalizations(AppLocales.toLocale('zh_Hant')).exportTitle, '匯出');
    expect(lookupAppLocalizations(AppLocales.toLocale('zh')).exportTitle, '导出');
    expect(lookupAppLocalizations(AppLocales.toLocale('pt_PT')).commonSave, 'Guardar');
    expect(lookupAppLocalizations(AppLocales.toLocale('pt')).commonSave, 'Salvar');
    // European Portuguese only lists what differs; the rest comes from Brazilian Portuguese.
    expect(lookupAppLocalizations(AppLocales.toLocale('pt_PT')).commonCancel, 'Cancelar');
    expect(lookupAppLocalizations(AppLocales.toLocale('nn')).deleteScanMessage, 'Dette kan ikkje angrast.');
    expect(lookupAppLocalizations(AppLocales.toLocale('no')).deleteScanMessage, 'Dette kan ikke angres.');
  });

  test('a phone\'s language setting picks the right variant', () {
    expect(AppLocales.fromDevice(const Locale('zh')), 'zh');
    expect(AppLocales.fromDevice(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')), 'zh');
    expect(AppLocales.fromDevice(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')), 'zh_Hant');
    expect(AppLocales.fromDevice(const Locale('zh', 'TW')), 'zh_Hant');
    expect(AppLocales.fromDevice(const Locale('zh', 'HK')), 'zh_Hant');
    expect(AppLocales.fromDevice(const Locale('pt', 'BR')), 'pt');
    expect(AppLocales.fromDevice(const Locale('pt')), 'pt');
    expect(AppLocales.fromDevice(const Locale('pt', 'PT')), 'pt_PT');
    expect(AppLocales.fromDevice(const Locale('nb', 'NO')), 'no');
    expect(AppLocales.fromDevice(const Locale('no')), 'no');
    expect(AppLocales.fromDevice(const Locale('nn', 'NO')), 'nn');
    expect(AppLocales.fromDevice(const Locale('de')), 'de');
    expect(AppLocales.fromDevice(const Locale('xx')), 'en');
  });

  test('language choice helpers', () {
    expect(AppLocales.baseLanguage('zh_Hant'), 'zh');
    expect(AppLocales.baseLanguage('pt_PT'), 'pt');
    expect(AppLocales.baseLanguage('en'), 'en');
    expect(AppLocales.isRtl('ar'), isTrue);
    expect(AppLocales.isRtl('zh_Hant'), isFalse);
    expect(AppLocales.intlTag('zh_Hant'), 'zh_TW');
    expect(AppLocales.intlTag('pt_PT'), 'pt_PT');
    expect(AppLocales.toLocale('zh_Hant').scriptCode, 'Hant');
    expect(AppLocales.toLocale('pt_PT').countryCode, 'PT');
  });

  test('dates do not fail for a language whose date data is not loaded', () {
    final DateTime d = DateTime(2026, 10, 31, 14, 5);
    for (final String c in AppLocales.supportedLanguageCodes) {
      expect(AppDateFormatter.formatShortDate(d, localeCode: c), isNotEmpty, reason: c);
      expect(AppDateFormatter.formatLongDate(d, localeCode: c), isNotEmpty, reason: c);
      expect(AppDateFormatter.formatTime(d, localeCode: c), isNotEmpty, reason: c);
      expect(AppDateFormatter.formatDateTime(d, localeCode: c), isNotEmpty, reason: c);
    }
    expect(AppDateFormatter.formatSmartDate(d, localeCode: 'zh_Hant', now: d), '今天');
    expect(AppDateFormatter.formatSmartDate(d, localeCode: 'nn', now: d), 'I dag');
    expect(AppDateFormatter.formatSmartDate(d, localeCode: 'pt_PT', now: d), 'Hoje');
  });
}
