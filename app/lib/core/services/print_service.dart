import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'filter_service.dart' show FilterService;
import 'export_service.dart' show FilterType;
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

/// Paper sizes offered when printing.
enum PrintPaper { a4, a5, letter, legal }

/// Empty border kept around the page content.
enum PrintMargin { none, narrow, normal }

/// How a scan sits on the paper: whole page visible, or filling the area.
enum PrintFit { fit, fill }

extension PrintPaperFormat on PrintPaper {
  PdfPageFormat get format => switch (this) {
        PrintPaper.a4 => PdfPageFormat.a4,
        PrintPaper.a5 => PdfPageFormat.a5,
        PrintPaper.letter => PdfPageFormat.letter,
        PrintPaper.legal => const PdfPageFormat(8.5 * PdfPageFormat.inch, 14 * PdfPageFormat.inch),
      };
}

extension PrintMarginSize on PrintMargin {
  /// Margin in PDF points (1 pt = 1/72 inch).
  double get points => switch (this) {
        PrintMargin.none => 0,
        PrintMargin.narrow => 10 * PdfPageFormat.mm,
        PrintMargin.normal => 20 * PdfPageFormat.mm,
      };
}

/// Sheet layout for [perSheet] scans on one sheet of paper: columns and rows,
/// and whether the sheet is turned sideways. Only 1, 2 and 4 are offered.
({int cols, int rows, bool landscape}) sheetGrid(int perSheet) => switch (perSheet) {
      2 => (cols: 2, rows: 1, landscape: true),
      4 => (cols: 2, rows: 2, landscape: false),
      _ => (cols: 1, rows: 1, landscape: false),
    };

abstract final class PrintService {
  static Future<Uint8List> buildPdfBytes(
    List<String> pagePaths, {
    List<int>? pageIndices,
    FilterType filter = FilterType.none,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    PrintMargin margin = PrintMargin.none,
    PrintFit fit = PrintFit.fit,
    int perSheet = 1,
    Future<Uint8List> Function(int index)? pageBytes,
  }) async {
    final pdf = pw.Document(creator: 'KatharScan');
    final indices = pageIndices ?? List<int>.generate(pagePaths.length, (i) => i);
    final grid = sheetGrid(perSheet);
    final int perPage = grid.cols * grid.rows;
    final List<pw.MemoryImage> images = <pw.MemoryImage>[];
    final List<bool> wide = <bool>[];

    for (final idx in indices) {
      if (idx < 0 || idx >= pagePaths.length) continue;
      Uint8List bytes;
      if (pageBytes != null) {
        // Fully processed page (edits included), supplied by the export pipeline.
        // A page that cannot be rendered with its edits must stop the print,
        // not be left out of the paper copy.
        bytes = await pageBytes(idx);
      } else {
        final file = File(pagePaths[idx]);
        if (!await file.exists()) continue;
        bytes = await file.readAsBytes();
      }
      if (pageBytes == null && filter != FilterType.none) {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final filtered = FilterService.applyToImage(decoded, filter);
            bytes = Uint8List.fromList(img.encodeJpg(filtered, quality: 92));
          }
        } catch (_) {}
      }
      bool isWide = false;
      try {
        final img.DecodeInfo? info = img.findDecoderForData(bytes)?.startDecode(bytes);
        if (info != null && info.width > info.height) isWide = true;
      } catch (_) {}
      images.add(pw.MemoryImage(bytes));
      wide.add(isWide);
    }

    final double m = margin.points;
    for (int start = 0; start < images.length; start += perPage) {
      final int end = (start + perPage) < images.length ? start + perPage : images.length;
      final List<pw.MemoryImage> group = images.sublist(start, end);
      PdfPageFormat fmt = pageFormat;
      if (perPage == 1) {
        if (wide[start]) fmt = pageFormat.landscape;
      } else {
        fmt = grid.landscape ? pageFormat.landscape : pageFormat.portrait;
      }
      final double areaW = fmt.width - 2 * m;
      final double areaH = fmt.height - 2 * m;
      final double cellW = areaW / grid.cols;
      final double cellH = areaH / grid.rows;
      // A gap between scans on a shared sheet keeps neighbours from touching.
      final double gap = perPage == 1 ? 0 : 4;
      final pw.BoxFit boxFit = fit == PrintFit.fill ? pw.BoxFit.cover : pw.BoxFit.contain;

      pw.Widget cell(pw.MemoryImage image) => pw.Container(
            width: cellW,
            height: cellH,
            padding: pw.EdgeInsets.all(gap / 2),
            child: pw.ClipRect(
              child: pw.Image(image, fit: boxFit, width: cellW - gap, height: cellH - gap),
            ),
          );

      final List<pw.Widget> rows = <pw.Widget>[];
      for (int r = 0; r < grid.rows; r++) {
        final List<pw.Widget> cells = <pw.Widget>[];
        for (int c = 0; c < grid.cols; c++) {
          final int i = r * grid.cols + c;
          cells.add(i < group.length ? cell(group[i]) : pw.SizedBox(width: cellW, height: cellH));
        }
        rows.add(pw.Row(children: cells));
      }
      pdf.addPage(
        pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.all(m),
          build: (context) => pw.Column(children: rows),
        ),
      );
    }
    return await pdf.save();
  }
}
