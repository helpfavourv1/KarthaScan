import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// Reads the text a PDF already contains (not OCR). Kept separate from the page
/// renderer so the two PDF libraries never meet in one file.
class PdfTextReader {
  PdfTextReader._(this._doc);
  final pdfrx.PdfDocument _doc;

  static bool _initialised = false;

  /// Returns null when the file cannot be opened; callers then fall back to OCR.
  static Future<PdfTextReader?> open(String path) async {
    try {
      if (!_initialised) {
        pdfrx.pdfrxFlutterInitialize();
        _initialised = true;
      }
      return PdfTextReader._(await pdfrx.PdfDocument.openFile(path));
    } catch (_) {
      return null;
    }
  }

  int get pageCount => _doc.pages.length;

  /// Text of page [pageNumber] (1-based), or null when it cannot be read.
  Future<String?> pageText(int pageNumber) async {
    try {
      if (pageNumber < 1 || pageNumber > _doc.pages.length) return null;
      final dynamic t = await _doc.pages[pageNumber - 1].loadText();
      final dynamic full = t?.fullText;
      return full is String ? full : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    try {
      await _doc.dispose();
    } catch (_) {}
  }
}
