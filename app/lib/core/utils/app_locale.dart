import 'dart:ui' show PlatformDispatcher;
import '../../l10n/app_localizations.dart';

/// Provides localized strings in contexts without BuildContext (services,
/// providers). Resolves to the device locale, falling back to the first
/// supported locale if no match exists.
abstract final class AppLocale {
  static AppLocalizations get l10n {
    final deviceLocale = PlatformDispatcher.instance.locale;
    final match = AppLocalizations.supportedLocales.firstWhere(
      (l) => l.languageCode == deviceLocale.languageCode,
      orElse: () => AppLocalizations.supportedLocales.first,
    );
    return lookupAppLocalizations(match);
  }

  AppLocale._();
}
