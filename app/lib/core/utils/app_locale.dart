import 'dart:ui' show PlatformDispatcher;
import '../../l10n/app_localizations.dart';
import 'constants.dart' show AppLocales;

/// Provides localized strings in contexts without BuildContext (services,
/// providers). Resolves to the device locale, falling back to the first
/// supported locale if no match exists.
abstract final class AppLocale {
  static AppLocalizations get l10n {
    return lookupAppLocalizations(AppLocales.toLocale(AppLocales.fromDevice(PlatformDispatcher.instance.locale)));
  }

  AppLocale._();
}
