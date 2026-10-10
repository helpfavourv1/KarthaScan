// lib/core/utils/csv_utils.dart
//
// CSV helpers shared by export, convert and CSV-to-PDF.

/// Escapes one CSV cell. Cells that start with = + - or @ would be run as a
/// formula by Excel/Sheets, so they get a leading apostrophe.
String csvCell(String value) {
  String cell = value;
  if (cell.isNotEmpty && '=+-@\t\r'.contains(cell[0])) {
    cell = "'$cell";
  }
  return '"${cell.replaceAll('"', '""')}"';
}

/// Builds CSV text with one row per non-empty line, in a single column, and a
/// leading BOM so Excel opens it as UTF-8. Blank lines are skipped, unless the
/// whole text is blank (then one empty row, so the file is never empty).
String csvFromText(String text) {
  final List<String> lines = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((String l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) lines.add('');
  return '﻿${lines.map(csvCell).join('\r\n')}';
}

/// Parses CSV text (RFC 4180): quoted fields, doubled quotes, commas and line
/// breaks inside quotes, CRLF or LF rows, optional BOM. Empty rows are skipped.
List<List<String>> parseCsv(String input) {
  final String text = input.startsWith('﻿') ? input.substring(1) : input;
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool inQuotes = false;
  bool fieldStarted = false;

  void endField() {
    row.add(field.toString());
    field.clear();
    fieldStarted = false;
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
  }

  for (int i = 0; i < text.length; i++) {
    final String c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && !fieldStarted) {
      inQuotes = true;
      fieldStarted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
      fieldStarted = true;
    }
  }
  if (fieldStarted || field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
