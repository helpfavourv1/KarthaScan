import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'debug_log_service.dart';

class TxtToPdfService {
  final DebugLogService _log = DebugLogService();

  Future<String> convertToPdf(String txtPath) async {
    _log.log('TXT_TO_PDF', 'Starting: $txtPath');
    final text = await File(txtPath).readAsString();
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: text.split('\n').map((line) => pw.Paragraph(
              text: line, 
              style: const pw.TextStyle(fontSize: 12),
            )).toList(),
          ),
        ],
      ),
    );
    
    final appDir = await getApplicationDocumentsDirectory();
    final outPath = p.join(appDir.path, 'txt_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await File(outPath).writeAsBytes(await pdf.save());
    _log.log('TXT_TO_PDF', 'Done: $outPath');
    return outPath;
  }
}
