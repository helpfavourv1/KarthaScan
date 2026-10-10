import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/utils/csv_utils.dart';

void main() {
  group('csvCell', () {
    test('quotes and doubles inner quotes', () {
      expect(csvCell('a "b", c'), '"a ""b"", c"');
    });
    test('neutralises spreadsheet formulas', () {
      expect(csvCell('=SUM(A1:A9)'), '"\'=SUM(A1:A9)"');
      expect(csvCell('+44 20'), '"\'+44 20"');
      expect(csvCell('-5'), '"\'-5"');
      expect(csvCell('@cmd'), '"\'@cmd"');
      expect(csvCell('total = 5'), '"total = 5"');
    });
  });

  group('csvFromText', () {
    test('one row per non-empty line, with a BOM', () {
      final String csv = csvFromText('Line 1\n\nLine 2\r\nLine 3');
      expect(csv, '﻿"Line 1"\r\n"Line 2"\r\n"Line 3"');
    });
    test('blank text still yields one empty row', () {
      expect(csvFromText('  \n '), '﻿""');
    });
  });

  group('parseCsv', () {
    test('plain rows', () {
      expect(parseCsv('a,b\n1,2\n'), <List<String>>[
        <String>['a', 'b'],
        <String>['1', '2'],
      ]);
    });
    test('quoted commas, doubled quotes and line breaks inside quotes', () {
      expect(parseCsv('"x, y","he said ""hi""","two\nlines"\r\nz,,'), <List<String>>[
        <String>['x, y', 'he said "hi"', 'two\nlines'],
        <String>['z', '', ''],
      ]);
    });
    test('BOM is ignored and a file written by csvFromText round trips', () {
      final List<List<String>> rows = parseCsv(csvFromText('one "q"\ntwo, three'));
      expect(rows, <List<String>>[
        <String>['one "q"'],
        <String>['two, three'],
      ]);
    });
  });
}
