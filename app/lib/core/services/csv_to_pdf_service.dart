import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/csv_utils.dart';
import 'complex_script_text.dart';
import 'debug_log_service.dart';
import 'pdf_fonts.dart';

class CsvToPdfService {
  final DebugLogService _log = DebugLogService();

  Future<String> convertToPdf(String csvPath, {void Function(double, String)? onProgress, String? outDir}) async {
    _log.log('CSV_TO_PDF', 'Starting: $csvPath');
    onProgress?.call(0.2, 'Reading…');
    final text = await File(csvPath).readAsString();
    onProgress?.call(0.4, 'Parsing rows…');
    final List<List<String>> rows = parseCsv(text);

    final List<String> headers = rows.isNotEmpty ? rows.first : <String>[];
    final List<List<String>> dataRows = rows.length > 1 ? rows.skip(1).toList() : <List<String>>[];
    const int chunkSize = 40;
    final List<pw.Widget> tables = <pw.Widget>[];
    for (int i = 0; i < dataRows.length; i += chunkSize) {
      final int end = i + chunkSize > dataRows.length ? dataRows.length : i + chunkSize;
      tables.add(pw.TableHelper.fromTextArray(
        headers: headers,
        data: dataRows.sublist(i, end),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 9),
        border: pw.TableBorder.all(),
      ));
      tables.add(pw.SizedBox(height: 12));
    }
    if (tables.isEmpty) {
      tables.add(pw.TableHelper.fromTextArray(
        headers: headers,
        data: <List<String>>[],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 9),
        border: pw.TableBorder.all(),
      ));
    }

    if (ComplexScriptText.hasComplex(text)) {
      // Joined scripts are drawn as pictures, so build the table by hand.
      tables.clear();
      final int cols = rows.fold<int>(1, (int m, List<String> r) => r.length > m ? r.length : m);
      final double cellWidth = ComplexScriptText.a4TextWidth / cols - 8;
      final List<pw.TableRow> tableRows = <pw.TableRow>[];
      for (int r = 0; r < rows.length; r++) {
        final List<pw.Widget> cells = <pw.Widget>[];
        for (int c = 0; c < cols; c++) {
          final String cell = c < rows[r].length ? rows[r][c] : '';
          final double size = r == 0 ? 10 : 9;
          final pw.Widget? picture = ComplexScriptText.hasComplex(cell)
              ? await ComplexScriptText.render(cell, fontSize: size, maxWidth: cellWidth)
              : null;
          cells.add(pw.Padding(
            padding: const pw.EdgeInsets.all(3),
            child: picture ?? pw.Text(cell, style: pw.TextStyle(fontSize: size, fontWeight: r == 0 ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ));
        }
        tableRows.add(pw.TableRow(children: cells));
      }
      tables.add(pw.Table(border: pw.TableBorder.all(), children: tableRows));
    }

    onProgress?.call(0.7, 'Building tables…');
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        theme: await PdfFonts.theme(text: text),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => tables,
      ),
    );

    onProgress?.call(0.9, 'Saving…');
    final String dirPath = outDir ?? (await getApplicationDocumentsDirectory()).path;
    final outPath = p.join(dirPath, 'csv_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await File(outPath).writeAsBytes(await pdf.save());
    onProgress?.call(1.0, 'Done');
    _log.log('CSV_TO_PDF', 'Done: $outPath');
    return outPath;
  }
}
