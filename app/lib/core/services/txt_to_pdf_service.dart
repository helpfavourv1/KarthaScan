import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'debug_log_service.dart';

class TxtToPdfService {
  final DebugLogService _log = DebugLogService();

  Future<String> convertToPdf(String txtPath, {void Function(double, String)? onProgress}) async {
    _log.log('TXT_TO_PDF', 'Starting: $txtPath');
    onProgress?.call(0.2, 'Reading…');
    final text = await File(txtPath).readAsString();
    onProgress?.call(0.5, 'Parsing…');
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => text
            .split('\n')
            .map((line) => pw.Paragraph(
                  text: line,
                  style: const pw.TextStyle(fontSize: 12),
                ))
            .toList(),
      ),
    );

    onProgress?.call(0.8, 'Building PDF…');
    final appDir = await getApplicationDocumentsDirectory();
    final outPath = p.join(appDir.path, 'txt_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await File(outPath).writeAsBytes(await pdf.save());
    onProgress?.call(1.0, 'Saving…');
    _log.log('TXT_TO_PDF', 'Done: $outPath');
    return outPath;
  }
}
