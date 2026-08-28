import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'debug_log_service.dart';

class CsvToPdfService {
  final DebugLogService _log = DebugLogService();

  Future<String> convertToPdf(String csvPath, {void Function(double, String)? onProgress}) async {
    _log.log('CSV_TO_PDF', 'Starting: $csvPath');
    onProgress?.call(0.2, 'Reading…');
    final text = await File(csvPath).readAsString();
    onProgress?.call(0.4, 'Parsing rows…');
    final rows = text.split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.split(','))
        .toList();

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

    onProgress?.call(0.7, 'Building tables…');
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => tables,
      ),
    );

    onProgress?.call(0.9, 'Saving…');
    final appDir = await getApplicationDocumentsDirectory();
    final outPath = p.join(appDir.path, 'csv_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await File(outPath).writeAsBytes(await pdf.save());
    onProgress?.call(1.0, 'Done');
    _log.log('CSV_TO_PDF', 'Done: $outPath');
    return outPath;
  }
}
