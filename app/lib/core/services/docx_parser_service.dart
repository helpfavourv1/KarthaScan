import 'dart:convert' show utf8;
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'complex_script_text.dart';
import 'debug_log_service.dart';
import 'pdf_fonts.dart';

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
    final xml = utf8.decode(docXml.content as List<int>, allowMalformed: true);
    
    final paragraphs = <String>[];
        final pRegex = RegExp(r'<w:p[^>]*>(.*?)</w:p>', dotAll: true);
    final tRegex = RegExp(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', dotAll: true);

    for (final pMatch in pRegex.allMatches(xml)) {
      final pContent = pMatch.group(1) ?? '';
      final texts = tRegex.allMatches(pContent).map((m) => _decodeXmlEntities(m.group(1) ?? '')).toList();
      if (texts.isNotEmpty) paragraphs.add(texts.join(''));
    }

    final pdf = pw.Document();
    final List<pw.Widget> paragraphWidgets = <pw.Widget>[];
    for (final String para in paragraphs) {
      paragraphWidgets.add(await ComplexScriptText.paragraph(para, maxWidth: ComplexScriptText.a4TextWidth));
    }
    pdf.addPage(
      pw.MultiPage(
        theme: await PdfFonts.theme(text: paragraphs.join('\n')),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => paragraphWidgets,
      ),
    );
    
    final appDir = await getApplicationDocumentsDirectory();
    final outPath = p.join(appDir.path, 'docx_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await File(outPath).writeAsBytes(await pdf.save());
    _log.log('DOCX_PARSER', 'Done: $outPath (${paragraphs.length} paragraphs)');
    return outPath;
  }

  Future<String> convertToTxt(String docxPath) async {
    _log.log('DOCX_PARSER', 'Starting txt: $docxPath');
    final bytes = await File(docxPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final docXml = archive.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('document.xml missing'),
    );
    final xml = utf8.decode(docXml.content as List<int>, allowMalformed: true);

    final paragraphs = <String>[];
    final pRegex = RegExp(r'<w:p[^>]*>(.*?)</w:p>', dotAll: true);
    final tRegex = RegExp(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', dotAll: true);

    for (final pMatch in pRegex.allMatches(xml)) {
      final pContent = pMatch.group(1) ?? '';
      final texts = tRegex.allMatches(pContent).map((m) => _decodeXmlEntities(m.group(1) ?? '')).toList();
      if (texts.isNotEmpty) paragraphs.add(texts.join(''));
    }

    final appDir = await getApplicationDocumentsDirectory();
    final outPath = p.join(appDir.path, 'docx_${DateTime.now().microsecondsSinceEpoch}.txt');
    await File(outPath).writeAsString(paragraphs.join('\n'));
    _log.log('DOCX_PARSER', 'Done txt: $outPath (${paragraphs.length} paragraphs)');
    return outPath;
  }

  String _decodeXmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  }
}
