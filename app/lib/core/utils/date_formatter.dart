// lib/core/utils/date_formatter.dart
//
// Locale-aware date/time formatting via `intl` (Section 15: "Date/number
// formatting via intl with locale-aware patterns"). Pure Dart — no dart:io,
// no plugin imports, fully unit-testable without a device (Section 4).
import 'package:intl/intl.dart';

/// Formats [DateTime] values for display, honoring the app's active locale
/// rather than assuming a fixed pattern. Every method takes an explicit
/// [localeCode] (e.g. from `UserSettings.language`) so this stays pure and
/// context-free — no reliance on `Localizations.localeOf(context)`, which
/// would pull a BuildContext into core/.
abstract final class AppDateFormatter {
  /// Format names to try for an app language, best first. Traditional Chinese
  /// (`zh_Hant`) may be known to the date data as `zh_TW`; a language the date data
  /// does not know falls back to its base language, then English, instead of failing.
  static List<String> _tags(String code) => <String>[
        code,
        if (code == 'zh_Hant') 'zh_TW',
        if (code.contains('_')) code.split('_').first,
        'en',
      ];

  static String _format(String code, DateFormat Function(String tag) make, DateTime date) {
    for (final String tag in _tags(code)) {
      try {
        return make(tag).format(date);
      } catch (_) {
        // Try the next name.
      }
    }
    return date.toIso8601String();
  }

  /// Short numeric date, e.g. "8/9/26" (en) or locale-appropriate
  /// equivalent. Used in dense list rows (scan_list_tile.dart).
  static String formatShortDate(DateTime date, {required String localeCode}) {
    return _format(localeCode, (String tag) => DateFormat.yMd(tag), date);
  }

  /// Long date, e.g. "August 9, 2026". Used in scan_detail_screen.dart.
  static String formatLongDate(DateTime date, {required String localeCode}) {
    return _format(localeCode, (String tag) => DateFormat.yMMMMd(tag), date);
  }

  /// Time only, e.g. "3:45 PM", respecting the locale's 12h/24h convention.
  static String formatTime(DateTime date, {required String localeCode}) {
    return _format(localeCode, (String tag) => DateFormat.jm(tag), date);
  }

  /// Combined date + time, e.g. "Aug 9, 2026, 3:45 PM".
  static String formatDateTime(DateTime date, {required String localeCode}) {
    return _format(localeCode, (String tag) => DateFormat.yMMMd(tag).add_jm(), date);
  }

  /// "Smart" relative label for recent activity: "Today", "Yesterday", or a
  /// short date beyond that. Used in scan_list_tile.dart so recently
  /// scanned documents are easy to scan visually without reading a full
  /// date. Falls back to [formatShortDate] once the date is more than a
  /// day in the past, rather than open-ended relative strings like "3 days
  /// ago" — those don't localize as cleanly across all 11 supported
  /// languages, and precise-but-short is a safer default than clever.
  static String formatSmartDate(
    DateTime date, {
    required String localeCode,
    DateTime? now,
  }) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime today = DateTime(reference.year, reference.month, reference.day);
    final DateTime target = DateTime(date.year, date.month, date.day);
    final int dayDelta = today.difference(target).inDays;

    if (dayDelta == 0) {
      return _todayLabel(localeCode);
    }
    if (dayDelta == 1) {
      return _yesterdayLabel(localeCode);
    }
    return formatShortDate(date, localeCode: localeCode);
  }

  // "Today"/"Yesterday" are intentionally kept as a small internal lookup
  // rather than routed through AppLocalizations here, since core/ has no
  // BuildContext to resolve localized strings through. screens/ and
  // widgets/ that call this should prefer AppLocalizations.of(context) for
  // these two words directly where a BuildContext is available; this
  // fallback exists for the (rarer) case a core/ or provider/ caller needs
  // a fully-formed label without one.
  static String _todayLabel(String localeCode) {
    switch (localeCode) {
      case 'es':
        return 'Hoy';
      case 'fr':
        return "Aujourd'hui";
      case 'de':
        return 'Heute';
      case 'pt':
      case 'pt_PT':
        return 'Hoje';
      case 'ar':
        return 'اليوم';
      case 'hi':
        return 'आज';
      case 'ja':
        return '今日';
      case 'ko':
        return '오늘';
      case 'zh':
      case 'zh_Hant':
        return '今天';
      case 'no':
        return 'I dag';
      case 'nn':
        return 'I dag';
      case 'he':
        return 'היום';
      case 'en':
      default:
        return 'Today';
    }
  }

  static String _yesterdayLabel(String localeCode) {
    switch (localeCode) {
      case 'es':
        return 'Ayer';
      case 'fr':
        return 'Hier';
      case 'de':
        return 'Gestern';
      case 'pt':
      case 'pt_PT':
        return 'Ontem';
      case 'ar':
        return 'أمس';
      case 'hi':
        return 'कल';
      case 'ja':
        return '昨日';
      case 'ko':
        return '어제';
      case 'zh':
        return '昨天';
      case 'zh_Hant':
        return '昨天';
      case 'no':
        return 'I går';
      case 'nn':
        return 'I går';
      case 'he':
        return 'אתמול';
      case 'en':
      default:
        return 'Yesterday';
    }
  }

  AppDateFormatter._();
}
