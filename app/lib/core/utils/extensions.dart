// lib/core/utils/extensions.dart
//
// String formatters, file size helpers, DateTime math (Section 16, file
// #7). Pure Dart only — no dart:io, no plugin imports (Section 4). File
// size helpers deliberately operate on raw `int` byte counts rather than
// `dart:io File` objects so this stays platform-independent; callers in
// platform/ or services/ read the byte length themselves and pass it in.

extension StringFormatting on String {
  /// Capitalizes the first letter only, leaving the rest untouched.
  /// `''.capitalize()` returns `''`.
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }

  /// Truncates to [maxLength] characters, appending an ellipsis if
  /// anything was cut. Never throws on strings shorter than [maxLength].
  String truncate(int maxLength, {String ellipsis = '…'}) {
    if (length <= maxLength) return this;
    if (maxLength <= 0) return '';
    return substring(0, maxLength) + ellipsis;
  }

  /// True for empty strings and strings containing only whitespace.
  bool get isBlank => trim().isEmpty;

  /// True for non-empty strings containing at least one non-whitespace
  /// character.
  bool get isNotBlank => !isBlank;
}

extension FileSizeFormatting on int {
  /// Formats a byte count as a short human-readable string, e.g.
  /// `1536` -> `"1.5 KB"`, `2097152` -> `"2.0 MB"`. Used for scan/export
  /// size display without pulling `dart:io` into core/ — callers pass the
  /// already-known byte length.
  String toHumanFileSize({int decimals = 1}) {
    if (this <= 0) return '0 B';

    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double size = toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final String formatted =
        unitIndex == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(decimals);
    return '$formatted ${units[unitIndex]}';
  }
}

extension DateTimeMath on DateTime {
  /// True if [other] falls on the same calendar day (year/month/day),
  /// ignoring time-of-day. Used for grouping scans by day in home_screen.
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  /// Midnight at the start of this date, in the same time zone context as
  /// the receiver (local vs. UTC is preserved).
  DateTime get startOfDay => DateTime(year, month, day);

  /// The last representable instant of this date (23:59:59.999999).
  DateTime get endOfDay =>
      DateTime(year, month, day, 23, 59, 59, 999, 999);

  /// Whole-day difference between calendar dates (not 24h periods) —
  /// `DateTime(2026,1,2)` minus `DateTime(2026,1,1)` is 1, regardless of
  /// the actual time-of-day on either value.
  int daysBetween(DateTime other) {
    final DateTime a = startOfDay;
    final DateTime b = other.startOfDay;
    return a.difference(b).inDays.abs();
  }

  /// True if this date is today, per [now] (defaults to DateTime.now()).
  bool isToday({DateTime? now}) => isSameDay(now ?? DateTime.now());

  /// True if this date is the calendar day immediately before [now]
  /// (defaults to DateTime.now()).
  bool isYesterday({DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime yesterday =
        DateTime(reference.year, reference.month, reference.day - 1);
    return isSameDay(yesterday);
  }
}
