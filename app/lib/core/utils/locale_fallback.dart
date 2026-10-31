// Flutter's own widgets (dialogs, date pickers, text-field menus) have strings for
// Norwegian Bokmål (`nb`, `no`) but none for Nynorsk (`nn`). Without them the whole
// app fails for Nynorsk ("No MaterialLocalizations found"). This wrapper gives Nynorsk
// the Norwegian strings for those widgets; the app's own text stays Nynorsk.
import 'package:flutter/widgets.dart';

class FallbackLocalizationsDelegate<T> extends LocalizationsDelegate<T> {
  const FallbackLocalizationsDelegate(this.inner);

  final LocalizationsDelegate<T> inner;

  static Locale mapLocale(Locale l) => l.languageCode == 'nn' ? const Locale('no') : l;

  @override
  bool isSupported(Locale locale) => inner.isSupported(mapLocale(locale));

  @override
  Future<T> load(Locale locale) => inner.load(mapLocale(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) => false;
}
