import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'debug_log_service.dart';

class DocxParserService {
  final DebugLogService _log = DebugLogService();

  Future<String> convertToPdf(String docxPath) async {
    _log.log('DOCX_PARSER', 'Starting: $docxPath');
    final bytes = await File(docxPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    final docXml = archive.firstWhere(
      (f) => f.name == 'word/document.xml', 
      orElse: () => throw Exception('document.xml missing'),
    );
    final xml = String.fromCharCodes(docXml.content as List<int>);
    
    final paragraphs = <String>[];
    final pRegex = RegExp(r'<w:p[^>]*>(.*?)</w:p>', dotAll: true);
    final tRegex = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
    
    for (final pMatch in pRegex.allMatches(xml)) {
      final pContent = pMatch.group(1) ?? '';
      final texts = tRegex.allMatches(pContent).map((m) => m.group(1) ?? '').toList();
      if (texts.isNotEmpty) paragraphs.add(texts.join(''));
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: paragraphs.map((para) => pw.Paragraph(
              text: para, 
              style: const pw.TextStyle(fontSize: 12),
            )).toList(),
          ),
        ],
      ),
    );
    
    final appDir = await getApplicationDocumentsDirectory();
    final outPath = p.join(appDir.path, 'docx_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await File(outPath).writeAsBytes(await pdf.save());
    _log.log('DOCX_PARSER', 'Done: $outPath (${paragraphs.length} paragraphs)');
    return outPath;
  }
}
