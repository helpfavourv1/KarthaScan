// integration_test/emulator_suite_test.dart
//
// Runs on a real Android emulator in CI (job "android-emulator-tests").
// Unlike the unit tests this uses the device's real text engine and fonts,
// real sqlite, the real network (font and language-file downloads), ML Kit
// and Tesseract. Every test prints one line "EMU: <id> | <status> | <detail>"
// that the workflow turns into a report.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/models/export_job.dart';
import 'package:katharscan/core/models/ocr_block.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/models/signature_placement.dart';
import 'package:katharscan/core/providers/scan_provider.dart';
import 'package:katharscan/core/providers/settings_provider.dart';
import 'package:katharscan/core/services/csv_to_pdf_service.dart';
import 'package:katharscan/core/services/doc_scanner_service.dart';
import 'package:katharscan/core/services/export_service.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:katharscan/core/services/remote_fonts.dart';
import 'package:katharscan/core/services/tess_data.dart';
import 'package:katharscan/core/services/txt_to_pdf_service.dart';
import 'package:katharscan/l10n/app_localizations.dart';
import 'package:katharscan/main.dart' as app;
import 'package:katharscan/widgets/edit_tray.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- helpers

void note(String id, String status, String detail) {
  // ignore: avoid_print
  print('EMU: $id | $status | ${detail.replaceAll('\n', ' / ')}');
}

/// Page text for each script: a title line and a paragraph, as on the sample pages.
const Map<String, String> kTexts = <String, String>{
  'latin': 'Invoice No. 2026-0417 Thank you for your order. Your parcel will arrive on 18 October 2026. Total amount due: 1,284.50 dollars. Please keep this receipt for your records.',
  'arabic': 'فاتورة رقم 2026-0417 شكراً لطلبكم. سيصل طردكم بتاريخ 18 أكتوبر 2026. المبلغ الإجمالي المستحق: 1284.50 دولار. يرجى الاحتفاظ بهذا الإيصال لسجلاتكم.',
  'russian': 'Счёт № 2026-0417 Благодарим за заказ. Ваша посылка прибудет 18 октября 2026 года. Общая сумма к оплате: 1 284,50 рублей. Пожалуйста, сохраните этот чек для своих записей.',
  'ukrainian': 'Рахунок № 2026-0417 Дякуємо за замовлення. Вашу посилку буде доставлено 18 жовтня 2026 року. Загальна сума до сплати: 1 284,50 гривень. Будь ласка, збережіть цей чек для своїх записів.',
  'greek': 'Τιμολόγιο αρ. 2026-0417 Ευχαριστούμε για την παραγγελία σας. Το δέμα σας θα φτάσει στις 18 Οκτωβρίου 2026. Συνολικό ποσό πληρωμής: 1.284,50 ευρώ. Παρακαλούμε φυλάξτε αυτήν την απόδειξη.',
  'hebrew': 'חשבונית מספר 2026-0417 תודה על הזמנתכם. החבילה שלכם תגיע ב-18 באוקטובר 2026. הסכום הכולל לתשלום: 1,284.50 שקלים. אנא שמרו קבלה זו לרשומותיכם.',
  'thai': 'ใบแจ้งหนี้เลขที่ 2026-0417 ขอบคุณสำหรับคำสั่งซื้อของคุณ พัสดุจะมาถึงในวันที่ 18 ตุลาคม 2569 ยอดเงินรวมที่ต้องชำระ 1,284.50 บาท กรุณาเก็บใบเสร็จนี้ไว้เป็นหลักฐาน',
  'bengali': 'চালান নম্বর ২০২৬-০৪১৭ আপনার অর্ডারের জন্য ধন্যবাদ। আপনার পার্সেলটি ১৮ অক্টোবর ২০২৬ তারিখে পৌঁছাবে। মোট প্রদেয় পরিমাণ: ১,২৮৪.৫০ টাকা। অনুগ্রহ করে এই রসিদটি সংরক্ষণ করুন।',
  'hindi': 'चालान संख्या 2026-0417 आपके ऑर्डर के लिए धन्यवाद। आपका पार्सल 18 अक्टूबर 2026 को पहुँचेगा। कुल देय राशि: ₹1,284.50। कृपया इस रसीद को अपने रिकॉर्ड के लिए सुरक्षित रखें।',
  'chinese': '发票编号 2026-0417 感谢您的订购。您的包裹将于2026年10月18日送达。应付总额：1,284.50元。请保留此收据以备记录。',
  'japanese': '請求書番号 2026-0417 ご注文ありがとうございます。お荷物は2026年10月18日に到着予定です。お支払い合計金額：1,284.50円。この領収書は記録のため保管してください。',
  'korean': '청구서 번호 2026-0417 주문해 주셔서 감사합니다. 택배는 2026년 10월 18일에 도착할 예정입니다. 총 결제 금액: 1,284.50원. 기록을 위해 이 영수증을 보관해 주세요.',
};

const Set<String> kRtl = <String>{'arabic', 'hebrew'};

Future<Uint8List> renderText(String text, {double size = 44, bool rtl = false, double width = 1100}) async {
  final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(
    textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
    fontSize: size,
  ))
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: size))
    ..addText(text);
  final ui.Paragraph para = b.build()..layout(ui.ParagraphConstraints(width: width - 120));
  final int h = (para.height + 120).ceil();
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, width, h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  c.drawParagraph(para, const ui.Offset(60, 60));
  final ui.Image im = await rec.endRecording().toImage(width.toInt(), h);
  final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

Future<File> writePng(String name, Uint8List bytes) async {
  final Directory dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'emu_pages'));
  await dir.create(recursive: true);
  final File f = File(p.join(dir.path, '$name.png'));
  await f.writeAsBytes(bytes);
  return f;
}

String _strip(String w) => w.replaceAll(RegExp(r'[\.,:;!?()"\-–—।।]'), '');

/// Share of the expected words that appear in what was read.
double hitRate(String expected, String got) {
  final List<String> words =
      expected.split(RegExp(r'\s+')).map(_strip).where((String w) => w.length > 1).toList();
  if (words.isEmpty) return 1;
  final String g = got.replaceAll(RegExp(r'\s+'), ' ');
  int hit = 0;
  for (final String w in words) {
    if (g.contains(w)) hit++;
  }
  return hit / words.length;
}

/// 1 - edit distance / length, ignoring spaces (for scripts written without spaces).
double charSimilarity(String a, String b) {
  final String x = a.replaceAll(RegExp(r'\s+'), '');
  final String y = b.replaceAll(RegExp(r'\s+'), '');
  if (x.isEmpty && y.isEmpty) return 1;
  List<int> prev = List<int>.generate(y.length + 1, (int i) => i);
  for (int i = 1; i <= x.length; i++) {
    final List<int> cur = List<int>.filled(y.length + 1, 0);
    cur[0] = i;
    for (int j = 1; j <= y.length; j++) {
      final int cost = x.codeUnitAt(i - 1) == y.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = <int>[cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((int m, int v) => v < m ? v : m);
    }
    prev = cur;
  }
  final int longest = x.length > y.length ? x.length : y.length;
  return 1 - prev[y.length] / longest;
}

/// PDF pages come back with a transparent background; put them on white as a viewer does.
Uint8List flattenOnWhite(Uint8List png) {
  final img.Image src = img.decodePng(png)!;
  final img.Image out = img.Image(width: src.width, height: src.height);
  for (final img.Pixel px in src) {
    final double a = px.a / px.maxChannelValue;
    int mix(num c) => (c * a + 255 * (1 - a)).round().clamp(0, 255);
    out.setPixelRgb(px.x, px.y, mix(px.r), mix(px.g), mix(px.b));
  }
  return Uint8List.fromList(img.encodePng(out));
}

Future<Uint8List?> firstPdfPagePng(String pdfPath, {double dpi = 200}) async {
  final Uint8List bytes = await File(pdfPath).readAsBytes();
  await for (final PdfRaster r in Printing.raster(bytes, pages: <int>[0], dpi: dpi)) {
    return flattenOnWhite(await r.toPng());
  }
  return null;
}

OcrScript scriptOf(String name) => OcrScript.values.firstWhere((OcrScript s) => s.name == name);

// ------------------------------------------------------------------ tests

void main() {
  final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const Timeout long = Timeout(Duration(minutes: 12));

  // ---- G1: fonts download from the website (or the repository spare)
  for (final MapEntry<String, RemoteFont> e in <String, RemoteFont>{
    'sc': RemoteFonts.sc,
    'jp': RemoteFonts.jp,
    'kr': RemoteFonts.kr,
  }.entries) {
    testWidgets('G1 font download ${e.key}', (WidgetTester tester) async {
      final File? f = await tester.runAsync<File?>(() => RemoteFonts.ensure(e.value));
      note('G1-${e.key}', f != null ? 'PASS' : 'FAIL', f != null ? '${f.lengthSync()} bytes' : 'download or checksum failed');
      expect(f, isNotNull, reason: 'font ${e.value.fileName} could not be downloaded');
      expect(f!.lengthSync(), e.value.bytes);
    }, timeout: long);
  }

  // ---- G2/G3: text in generated PDFs is really drawn (PDF -> picture -> OCR)
  Future<void> pdfShowsText(WidgetTester tester, String id, List<String> scripts, {required bool csv}) async {
    final Directory tmp = await getTemporaryDirectory();
    final String text = scripts.map((String s) => kTexts[s]!).join('\n\n');
    final File src = File(p.join(tmp.path, 'src_$id.${csv ? 'csv' : 'txt'}'));
    await src.writeAsString(text);
    final String pdf = await tester.runAsync(() => csv
            ? CsvToPdfService().convertToPdf(src.path)
            : TxtToPdfService().convertToPdf(src.path)) ??
        '';
    expect(File(pdf).existsSync(), isTrue);
    expect(File(pdf).lengthSync(), greaterThan(1000));
    final Uint8List? png = await tester.runAsync<Uint8List?>(() => firstPdfPagePng(pdf));
    expect(png, isNotNull, reason: 'PDF page could not be drawn');
    final img.Image? decoded = img.decodePng(png!);
    int dark = 0;
    for (final img.Pixel px in decoded!) {
      if (px.r < 100 && px.g < 100 && px.b < 100) dark++;
    }
    note('$id-ink', 'INFO', '$dark dark pixels on page 1');
    expect(dark, greaterThan(500), reason: 'PDF page is blank');
    final File picture = await writePng('pdfpage_$id', png);
    final StringBuffer report = StringBuffer();
    bool ok = true;
    for (final String s in scripts) {
      final OcrScript script = scriptOf(s);
      String got = '';
      String how = '';
      try {
        final OcrResult r = await tester.runAsync(() => OcrService().recognizeText(imagePath: picture.path, script: script)) ??
            const OcrResult(fullText: '', blocks: <OcrBlock>[]);
        got = r.fullText;
        how = script.usesTesseract ? 'tesseract' : 'mlkit';
      } on OcrUnavailableException catch (error) {
        report.write('$s: OCR unavailable (${error.message}); ');
        continue;
      }
      final double score = hitRate(kTexts[s]!, got);
      final double sim = charSimilarity(kTexts[s]!, got);
      report.write('$s: words ${(score * 100).round()}% chars ${(sim * 100).round()}% ($how) read: ${got.replaceAll('\n', ' ')}; ');
      if (score < 0.4 && sim < 0.5) ok = false;
    }
    note(id, ok ? 'PASS' : 'FAIL', report.toString());
    expect(ok, isTrue, reason: report.toString());
  }

  testWidgets('G2 Latin text PDF draws', (WidgetTester tester) async {
    await pdfShowsText(tester, 'G2-latin-pdf', <String>['latin'], csv: false);
  }, timeout: long);

  testWidgets('G3 Cyrillic and Greek text PDF draws', (WidgetTester tester) async {
    await pdfShowsText(tester, 'G3-cyrillic-greek-pdf', <String>['russian', 'greek'], csv: false);
  }, timeout: long);

  testWidgets('G4 Arabic and Hebrew text PDF draws (right to left)', (WidgetTester tester) async {
    await pdfShowsText(tester, 'G4-rtl-pdf', <String>['arabic', 'hebrew'], csv: false);
  }, timeout: long);

  testWidgets('G5 Hindi, Bengali and Thai text PDF draws (picture route)', (WidgetTester tester) async {
    await pdfShowsText(tester, 'G5-indic-thai-pdf', <String>['bengali', 'thai'], csv: false);
  }, timeout: long);

  testWidgets('G6 Chinese, Japanese and Korean text PDF draws (downloaded fonts)', (WidgetTester tester) async {
    // ML Kit's CJK packs cannot be installed on a CI emulator, so the glyphs are checked by ink only.
    final Directory tmp = await getTemporaryDirectory();
    final File src = File(p.join(tmp.path, 'src_g6.txt'));
    await src.writeAsString(<String>[kTexts['chinese']!, kTexts['japanese']!, kTexts['korean']!].join('\n\n'));
    final String pdf = await tester.runAsync<String>(() => TxtToPdfService().convertToPdf(src.path)) ?? '';
    final Uint8List? png = await tester.runAsync<Uint8List?>(() => firstPdfPagePng(pdf));
    final img.Image im = img.decodePng(png!)!;
    int dark = 0;
    for (final img.Pixel px in im) {
      if (px.r < 100) dark++;
    }
    note('G6-cjk-pdf', dark > 5000 ? 'PARTIAL' : 'FAIL', 'text drawn ($dark dark pixels, PDF ${File(pdf).lengthSync()} bytes); glyph shapes not OCR-checked: no ML Kit CJK packs on emulator');
    expect(dark, greaterThan(5000));
  }, timeout: long);

  testWidgets('G7 Hindi CSV table PDF draws', (WidgetTester tester) async {
    final Directory tmp = await getTemporaryDirectory();
    final File csv = File(p.join(tmp.path, 'hindi_table.csv'));
    await csv.writeAsString('नाम,शहर,राशि\nराहुल,दिल्ली,1284.50\nप्रिया,मुंबई,560.00\nअमित,पुणे,92.25\n');
    final String pdf = await tester.runAsync(() => CsvToPdfService().convertToPdf(csv.path)) ?? '';
    final Uint8List? png = await tester.runAsync<Uint8List?>(() => firstPdfPagePng(pdf));
    expect(png, isNotNull);
    final img.Image decoded = img.decodePng(png!)!;
    int dark = 0;
    for (final img.Pixel px in decoded) {
      if (px.r < 100) dark++;
    }
    note('G7-hindi-csv', dark > 300 ? 'PASS' : 'FAIL', '$dark dark pixels');
    expect(dark, greaterThan(300));
  }, timeout: long);

  // ---- OCR: Latin (built in)
  testWidgets('OCR Latin page', (WidgetTester tester) async {
    final File page = await writePng('ocr_latin', await renderText(kTexts['latin']!));
    final OcrResult? r = await tester.runAsync(() => OcrService().recognizeText(imagePath: page.path, script: OcrScript.latin));
    final double score = hitRate(kTexts['latin']!, r!.fullText);
    note('OCR-latin', score >= 0.7 ? 'PASS' : 'FAIL', 'words ${(score * 100).round()}% | ${r.fullText}');
    expect(score, greaterThanOrEqualTo(0.7), reason: r.fullText);
  }, timeout: long);

  // ---- OCR: Tesseract languages (download from the website or the repository, then read)
  const Map<String, double> tessMinimum = <String, double>{
    'arabic': 0.4, 'russian': 0.7, 'ukrainian': 0.7, 'greek': 0.7, 'hebrew': 0.7, 'thai': 0.5, 'bengali': 0.6,
  };
  for (final MapEntry<String, double> e in tessMinimum.entries) {
    testWidgets('OCR Tesseract ${e.key}', (WidgetTester tester) async {
      final String name = e.key;
      final File page = await writePng('ocr_$name', await renderText(kTexts[name]!, rtl: kRtl.contains(name)));
      OcrResult? r;
      try {
        r = await tester.runAsync(() => OcrService().recognizeText(imagePath: page.path, script: scriptOf(name)));
      } on OcrUnavailableException catch (error) {
        note('OCR-$name', 'FAIL', 'unavailable: ${error.message}');
        fail('OCR for $name failed: ${error.message}');
      }
      final double words = hitRate(kTexts[name]!, r!.fullText);
      final double chars = charSimilarity(kTexts[name]!, r.fullText);
      final double score = words > chars ? words : chars;
      final bool ok = score >= e.value;
      note('OCR-$name', ok ? 'PASS' : 'FAIL', 'words ${(words * 100).round()}% chars ${(chars * 100).round()}% (need ${(e.value * 100).round()}%) | ${r.fullText}');
      expect(ok, isTrue, reason: 'read: ${r.fullText}');
      expect(await TessData.isInstalled(scriptOf(name).tessCode!), isTrue, reason: 'language file not kept after download');
    }, timeout: long);
  }

  testWidgets('OCR automatic fallback reads an installed Russian pack without being asked', (WidgetTester tester) async {
    final File page = await writePng('ocr_auto_ru', await renderText(kTexts['russian']!));
    final OcrResult? r = await tester.runAsync(() => OcrService().recognizeTextAuto(imagePath: page.path));
    final double score = hitRate(kTexts['russian']!, r!.fullText);
    note('OCR-auto-russian', score >= 0.5 ? 'PASS' : 'FAIL', 'words ${(score * 100).round()}% | ${r.fullText}');
    expect(score, greaterThanOrEqualTo(0.5), reason: r.fullText);
  }, timeout: long);

  // ---- OCR: Google Play services packs (need a Play-services emulator image)
  for (final String name in <String>['chinese', 'japanese', 'korean', 'devanagari']) {
    testWidgets('OCR ML Kit pack $name', (WidgetTester tester) async {
      final OcrScript script = scriptOf(name);
      final bool ready = await tester.runAsync(() => OcrModels.download(script, timeout: const Duration(minutes: 5))) ?? false;
      if (!ready) {
        note('OCR-$name', 'SKIP', 'Play services did not deliver the pack on this emulator: ${OcrModels.lastError[script] ?? 'no error text'}');
        markTestSkipped('pack not available on emulator');
        return;
      }
      final String key = name == 'devanagari' ? 'hindi' : name;
      final File page = await writePng('ocr_$name', await renderText(kTexts[key]!));
      final OcrResult? r = await tester.runAsync(() => OcrService().recognizeText(imagePath: page.path, script: script));
      final double words = hitRate(kTexts[key]!, r!.fullText);
      final double chars = charSimilarity(kTexts[key]!, r.fullText);
      final bool ok = chars >= 0.6 || words >= 0.6;
      note('OCR-$name', ok ? 'PASS' : 'FAIL', 'words ${(words * 100).round()}% chars ${(chars * 100).round()}% | ${r.fullText}');
      expect(ok, isTrue, reason: 'read: ${r.fullText}');
    }, timeout: long);
  }

  // ---- A/B/E/F: edits, export, pages, search on the real engine and database
  late LocalStorageService storage;
  late ScanProvider scan;

  Future<ScanDocument> seedDoc(String id, List<File> pages) async {
    final DateTime now = DateTime.now();
    final ScanDocument d = ScanDocument(
      id: id,
      title: 'Emu $id',
      pageCount: pages.length,
      pagePaths: pages.map((File f) => f.path).toList(),
      createdAt: now,
      updatedAt: now,
      ocrText: '',
      thumbnailPath: pages.first.path,
    );
    await storage.saveDocument(d);
    return d;
  }

  Future<void> bootProvider() async {
    storage = LocalStorageService();
    await storage.initialize();
    scan = ScanProvider(storage: storage, docScanner: DocScannerService(), ocr: OcrService(), settings: SettingsProvider(storage));
    for (int i = 0; i < 100 && scan.isLoading.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  testWidgets('A1 stamp, watermark, rotate and filter reach the exported PDF, PNG and share files', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await bootProvider();
      final File page = await writePng('edit_page', await renderText('Plain page for editing', width: 800));
      await seedDoc('emu_a1', <File>[page]);
      await scan.refresh();
      await scan.addStampLayer('emu_a1', const StampLayer(id: 's1', pageIndex: 0, kind: 'text', placement: SignaturePlacement(pctX: 0.5, pctY: 0.8), text: 'APPROVED', fontSize: 96, color: 0xFFCC0000));
      await scan.addWatermarkLayer('emu_a1', const WatermarkLayer(pageIndex: 0, text: 'CONFIDENTIAL', placement: SignaturePlacement(pctX: 0.5, pctY: 0.4), opacity: 0.6, color: 0xFF0000AA));
      await scan.updatePageTransform('emu_a1', 0, const PageTransform(rotationTurns: 1));
      final ScanDocument doc = scan.documents.value.firstWhere((ScanDocument d) => d.id == 'emu_a1');

      final Uint8List base = await File(doc.pagePaths.first).readAsBytes();
      final Uint8List out = await ExportService().renderPageForOutput(doc, 0);
      final img.Image a = img.decodePng(base)!;
      final img.Image b = img.decodePng(out)!;
      int red = 0, blue = 0;
      for (final img.Pixel px in b) {
        if (px.r > 150 && px.g < 80 && px.b < 80) red++;
        if (px.b > px.r + 40 && px.b > px.g + 40) blue++;
      }
      note('A1-render', (red > 200 && blue > 100) ? 'PASS' : 'FAIL',
          'rotated ${a.width}x${a.height} -> ${b.width}x${b.height}; red stamp pixels $red, blue watermark pixels $blue');
      expect(b.width, a.height, reason: 'page was not rotated');
      expect(red, greaterThan(200), reason: 'stamp text not drawn on device');
      expect(blue, greaterThan(100), reason: 'watermark text not drawn on device');

      final Directory outDir = Directory(p.join((await getTemporaryDirectory()).path, 'emu_out'))..createSync(recursive: true);
      for (final ExportFormat f in <ExportFormat>[ExportFormat.pdf, ExportFormat.png, ExportFormat.jpg, ExportFormat.docx]) {
        final List<String> files = await ExportService().export(
          document: doc, format: f, outputDirectoryPath: outDir.path, docxMode: ExportDocxMode.imageEmbedded);
        expect(File(files.first).lengthSync(), greaterThan(500), reason: f.name);
      }
      final List<String> shared = await ExportService().renderPagesForShare(doc);
      expect(File(shared.first).lengthSync(), greaterThan(500));
      note('A1-export', 'PASS', 'pdf, png, jpg, docx and share files written');
    });
  }, timeout: long);

  testWidgets('A2 PDF compression makes the file smaller and filter strength changes the result', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await bootProvider();
      // A photo-like page: noise compresses badly as PNG, well as JPG.
      final img.Image noise = img.Image(width: 1500, height: 2000);
      int seed = 7;
      for (final img.Pixel px in noise) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        px.r = 100 + (seed & 0x3f);
        px.g = 100 + ((seed >> 6) & 0x3f);
        px.b = 100 + ((seed >> 12) & 0x3f);
      }
      final File page = await writePng('noise_page', Uint8List.fromList(img.encodePng(noise)));
      final ScanDocument doc = await seedDoc('emu_a2', <File>[page]);
      final Directory out = Directory(p.join((await getTemporaryDirectory()).path, 'emu_comp'))..createSync(recursive: true);
      final Map<CompressionTier, int> sizes = <CompressionTier, int>{};
      for (final CompressionTier t in CompressionTier.values) {
        final List<String> f = await ExportService().export(document: doc, format: ExportFormat.pdf, outputDirectoryPath: out.path, compression: t);
        sizes[t] = File(f.first).lengthSync();
      }
      note('A2-compress', (sizes[CompressionTier.small]! < sizes[CompressionTier.original]!) ? 'PASS' : 'FAIL',
          sizes.entries.map((MapEntry<CompressionTier, int> e) => '${e.key.name}=${(e.value / 1024).round()}KB').join(' '));
      expect(sizes[CompressionTier.small]!, lessThan(sizes[CompressionTier.original]!));
      expect(sizes[CompressionTier.medium]!, lessThan(sizes[CompressionTier.original]!));
    });
  }, timeout: long);

  testWidgets('B1 pages: reorder, delete, extract keep edits; new page text becomes searchable; tags searchable', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await bootProvider();
      final File p1 = await writePng('b1_one', await renderText('First page apple', width: 800));
      final File p2 = await writePng('b1_two', await renderText('Second page banana', width: 800));
      final File p3 = await writePng('b1_three', await renderText('Third page cherry', width: 800));
      await seedDoc('emu_b1', <File>[p1, p2]);
      await scan.refresh();
      await scan.addWatermarkLayer('emu_b1', const WatermarkLayer(pageIndex: 1, text: 'MOVED', placement: SignaturePlacement(pctX: 0.5, pctY: 0.5)));
      await scan.updateDocumentPages('emu_b1', <String>[p2.path, p1.path]);
      ScanDocument d = scan.documents.value.firstWhere((ScanDocument x) => x.id == 'emu_b1');
      final bool followed = d.watermarkLayers.single.pageIndex == 0;
      await scan.insertPageAt('emu_b1', 2, p3.path);
      // Text of the new page is read in the background.
      bool found = false;
      for (int i = 0; i < 40 && !found; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        found = (await storage.searchDocuments('cherry')).any((ScanDocument x) => x.id == 'emu_b1');
      }
      await scan.updateTags('emu_b1', <String>['invoicetag']);
      final bool tagFound = (await storage.searchDocuments('invoicetag')).any((ScanDocument x) => x.id == 'emu_b1');
      final ScanDocument? part = await scan.extractToNewDocument('emu_b1', <int>[0], 'Extract');
      d = scan.documents.value.firstWhere((ScanDocument x) => x.id == 'emu_b1');
      final bool ok = followed && found && tagFound && part != null && part.watermarkLayers.isNotEmpty && d.pageCount == 3;
      note('B1-pages', ok ? 'PASS' : 'FAIL', 'layer followed page=$followed, new page searchable=$found, tag searchable=$tagFound, extract kept layer=${part?.watermarkLayers.isNotEmpty}, pages=${d.pageCount}');
      expect(followed, isTrue);
      expect(found, isTrue, reason: 'text of the added page was not found by search within 40 s');
      expect(tagFound, isTrue);
      expect(part, isNotNull);
      expect(part!.watermarkLayers, isNotEmpty);
    });
  }, timeout: long);

  testWidgets('D1 a 20-page edited document: how long export blocks the screen thread', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await bootProvider();
      final List<File> pages = <File>[];
      for (int i = 0; i < 20; i++) {
        pages.add(await writePng('d1_$i', await renderText('Page $i of the long document. ' * 12, width: 1400)));
      }
      await seedDoc('emu_d1', pages);
      await scan.refresh();
      for (int i = 0; i < 20; i++) {
        await scan.addStampLayer('emu_d1', StampLayer(id: 'd$i', pageIndex: i, kind: 'text', placement: const SignaturePlacement(pctX: 0.5, pctY: 0.9), text: 'Page $i'));
        await scan.updatePageTransform('emu_d1', i, PageTransform(rotationTurns: i % 4, filter: FilterType.colorEnhance));
      }
      final ScanDocument doc = scan.documents.value.firstWhere((ScanDocument x) => x.id == 'emu_d1');
      final Directory out = Directory(p.join((await getTemporaryDirectory()).path, 'emu_d1'))..createSync(recursive: true);

      int maxGap = 0;
      DateTime last = DateTime.now();
      final Timer beat = Timer.periodic(const Duration(milliseconds: 16), (Timer _) {
        final DateTime now = DateTime.now();
        final int gap = now.difference(last).inMilliseconds;
        if (gap > maxGap) maxGap = gap;
        last = now;
      });
      final Stopwatch sw = Stopwatch()..start();
      final List<String> files = await ExportService().export(document: doc, format: ExportFormat.pdf, outputDirectoryPath: out.path);
      sw.stop();
      beat.cancel();
      note('D1-export20', 'INFO', 'export took ${sw.elapsed.inSeconds}s, longest screen-thread freeze ${maxGap}ms, pdf ${(File(files.first).lengthSync() / 1024).round()}KB');
      expect(File(files.first).lengthSync(), greaterThan(1000));
      expect(sw.elapsed.inMinutes, lessThan(5), reason: 'export of 20 pages took ${sw.elapsed.inSeconds}s');
    });
  }, timeout: long);

  // ---- C: walk through every tray tool on the real app and catch any exception
  testWidgets('C1 every tray tool opens and closes without an error', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    final LocalStorageService seedStorage = LocalStorageService();
    await seedStorage.initialize();
    final List<File> pages = <File>[];
    for (int i = 0; i < 3; i++) {
      pages.add(await writePng('ui_$i', await renderText('Walk page $i. ${kTexts['latin']}', width: 800)));
    }
    final DateTime now = DateTime.now();
    await seedStorage.saveDocument(ScanDocument(
      id: 'emu_ui', title: 'Emu UI walk', pageCount: 3, pagePaths: pages.map((File f) => f.path).toList(),
      createdAt: now, updatedAt: now, ocrText: 'walk', thumbnailPath: pages.first.path,
    ));

    final List<String> errors = <String>[];
    final List<String> everything = <String>[];
    final void Function(FlutterErrorDetails)? old = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      everything.add('${d.exceptionAsString().split('\n').first} @ ${(d.stack?.toString() ?? '').split('\n').take(6).join(' <- ')}');
      errors.add('${d.exceptionAsString().split('\n').first} @ ${(d.stack?.toString() ?? '').split('\n').where((String l) => l.contains('katharscan')).take(3).join(' <- ')}');
      old?.call(d);
    };

    Future<void> pumpFor(int ms) async {
      final int steps = ms ~/ 100;
      for (int i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await app.main();
    await pumpFor(4000);
    final GoRouter router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/scan/emu_ui');
    await pumpFor(4000);
    expect(find.byType(EditTray), findsOneWidget, reason: 'document screen did not show the tray');
    final AppLocalizations l10n = AppLocalizations.of(tester.element(find.byType(EditTray)));
    final Map<String, String> tools = <String, String>{
      'annotate': l10n.annotateTitle,
      'sign': l10n.signatureTitle,
      'watermark': l10n.watermarkLabel,
      'ocr': l10n.ocrSectionLabel,
      'convert': l10n.commonConvert,
      'compress': l10n.compressLabel,
      'rotate': l10n.rotateLabel,
      'resize': l10n.resizeTitle,
      'pages': l10n.pagesLabel,
      'filter': l10n.filterTitle,
      'crop': l10n.cropLabel,
      'text': l10n.textLabel,
      'note': l10n.noteLabel,
      'date': l10n.dateLabel,
      'check': l10n.checkLabel,
      'seal': l10n.sealCustom,
      'erase': l10n.eraserTitle,
    };
    final List<String> failures = <String>[];
    for (final MapEntry<String, String> t in tools.entries) {
      errors.clear();
      final Finder target = find.byKey(ValueKey<String>('trayTarget:${t.value}'));
      String status = 'ok';
      try {
        await tester.ensureVisible(target);
        await pumpFor(300);
        await tester.tap(target);
        await pumpFor(1500);
        // Close whatever opened: back until the tray shows again (never leave the document).
        for (int i = 0; i < 3 && find.byType(EditTray).evaluate().isEmpty; i++) {
          await tester.binding.handlePopRoute();
          await pumpFor(600);
        }
        if (find.byType(EditTray).evaluate().isEmpty) {
          router.go('/scan/emu_ui');
          await pumpFor(2500);
          status = 'needed reset';
        }
        // Tools that act at once leave a mode on; close it with one back press when the tray is still there.
      } catch (error) {
        errors.add('test driver: $error');
      }
      final bool bad = errors.isNotEmpty;
      note('C1-${t.key}', bad ? 'FAIL' : 'PASS', bad ? errors.take(2).join(' || ') : status);
      if (bad) failures.add('${t.key}: ${errors.first}');
      // Re-open the document so the next tool starts from the same screen.
      if (bad) {
        router.go('/scan/emu_ui');
        await pumpFor(2500);
      }
    }
    FlutterError.onError = old;
    note('C1-all-errors', everything.isEmpty ? 'PASS' : 'FAIL', everything.isEmpty ? 'none' : '${everything.length} errors: ${everything.take(4).join(' ## ')}');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 15)));
}
