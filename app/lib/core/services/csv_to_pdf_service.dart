import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'debug_log_service.dart';

class CsvToPdfService {
  final DebugLogService _log = DebugLogService();

  Future<String> convertToPdf(String csvPath) async {
    _log.log('CSV_TO_PDF', 'Starting: $csvPath');
    final text = await File(csvPath).readAsString();
    final rows = text.split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.split(','))
        .toList();
        
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.TableHelper.fromTextArray(
            headers: rows.isNotEmpty ? rows.first : <String>[],
            data: rows.length > 1 ? rows.skip(1).toList() : <List<String>>[],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            border: pw.TableBorder.all(),
          ),
        ],
      ),
    );
    
    final appDir = await getApplicationDocumentsDirectory();
    final outPath = p.join(appDir.path, 'csv_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await File(outPath).writeAsBytes(await pdf.save());
    _log.log('CSV_TO_PDF', 'Done: $outPath');
    return outPath;
  }
}
