import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_render_plus/pdf_render.dart';
import 'package:image/image.dart' as img;
import 'debug_log_service.dart';

class PdfToImagesService {
  final DebugLogService _log = DebugLogService();

  Future<List<String>> convertToImages(String pdfPath) async {
    _log.log('PDF_TO_IMAGES', 'Starting: $pdfPath');
    final doc = await PdfDocument.openFile(pdfPath);
    final appDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(appDir.path, 'converted_images'));
    await outDir.create(recursive: true);
    
    final List<String> paths = [];
    for (int i = 1; i <= doc.pageCount; i++) {
      final page = await doc.getPage(i);
      final rendered = await page.render(
        width: (page.width * 2).round(), 
        height: (page.height * 2).round(),
      );
      final pngImage = img.Image.fromBytes(
        width: rendered.width, 
        height: rendered.height,
        bytes: rendered.pixels.buffer, 
        numChannels: 4,
      );
      final outPath = p.join(outDir.path, 'pdf_${DateTime.now().microsecondsSinceEpoch}_$i.png');
      await File(outPath).writeAsBytes(img.encodePng(pngImage));
      paths.add(outPath);
    }
    doc.dispose();
    _log.log('PDF_TO_IMAGES', 'Done: ${paths.length} pages');
    return paths;
  }
}
