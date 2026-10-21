// Runs on an iPhone simulator in CI: which of the Tesseract-only languages
// Apple's Vision framework can read on this iOS version, and how well.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:katharscan/core/services/ocr_service.dart';
import 'package:katharscan/core/services/tess_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void note(String id, String status, String detail) {
  // ignore: avoid_print
  print('EMU: $id | $status | ${detail.replaceAll('\n', ' / ')}');
}

const Map<String, String> kTexts = <String, String>{
  'arabic': 'فاتورة رقم 2026-0417 شكراً لطلبكم. سيصل طردكم بتاريخ 18 أكتوبر 2026. المبلغ الإجمالي المستحق: 1284.50 دولار.',
  'russian': 'Счёт № 2026-0417 Благодарим за заказ. Ваша посылка прибудет 18 октября 2026 года. Общая сумма к оплате: 1 284,50 рублей.',
  'ukrainian': 'Рахунок № 2026-0417 Дякуємо за замовлення. Вашу посилку буде доставлено 18 жовтня 2026 року. Загальна сума до сплати: 1 284,50 гривень.',
  'greek': 'Τιμολόγιο αρ. 2026-0417 Ευχαριστούμε για την παραγγελία σας. Το δέμα σας θα φτάσει στις 18 Οκτωβρίου 2026. Συνολικό ποσό πληρωμής: 1.284,50 ευρώ.',
  'hebrew': 'חשבונית מספר 2026-0417 תודה על הזמנתכם. החבילה שלכם תגיע ב-18 באוקטובר 2026. הסכום הכולל לתשלום: 1,284.50 שקלים.',
  'thai': 'ใบแจ้งหนี้เลขที่ 2026-0417 ขอบคุณสำหรับคำสั่งซื้อของคุณ พัสดุจะมาถึงในวันที่ 18 ตุลาคม 2569 ยอดเงินรวมที่ต้องชำระ 1,284.50 บาท',
  'bengali': 'চালান নম্বর ২০২৬-০৪১৭ আপনার অর্ডারের জন্য ধন্যবাদ। আপনার পার্সেলটি ১৮ অক্টোবর ২০২৬ তারিখে পৌঁছাবে। মোট প্রদেয় পরিমাণ: ১,২৮৪.৫০ টাকা।',
};

double sim(String a, String b) {
  final String x = a.replaceAll(RegExp(r'\s+'), '');
  final String y = b.replaceAll(RegExp(r'\s+'), '');
  if (x.isEmpty || y.isEmpty) return 0;
  List<int> prev = List<int>.generate(y.length + 1, (int i) => i);
  for (int i = 1; i <= x.length; i++) {
    final List<int> cur = List<int>.filled(y.length + 1, 0)..[0] = i;
    for (int j = 1; j <= y.length; j++) {
      final int c = x.codeUnitAt(i - 1) == y.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = <int>[cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + c].reduce((int m, int v) => v < m ? v : m);
    }
    prev = cur;
  }
  return 1 - prev[y.length] / (x.length > y.length ? x.length : y.length);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final MapEntry<String, String> e in kTexts.entries) {
    testWidgets('iOS Vision OCR ${e.key}', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final OcrScript script = OcrScript.values.firstWhere((OcrScript s) => s.name == e.key);
        final bool supported = await TessData.isInstalled(script.tessCode!);
        if (!supported) {
          note('iOS-${e.key}', 'UNSUPPORTED', 'this iOS version cannot read this language');
          return;
        }
        final bool rtl = e.key == 'arabic' || e.key == 'hebrew';
        final ui.ParagraphBuilder b = ui.ParagraphBuilder(ui.ParagraphStyle(
          textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr, fontSize: 44))
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: 44))
          ..addText(e.value);
        final ui.Paragraph para = b.build()..layout(const ui.ParagraphConstraints(width: 980));
        final int h = (para.height + 120).ceil();
        final ui.PictureRecorder rec = ui.PictureRecorder();
        final ui.Canvas c = ui.Canvas(rec);
        c.drawRect(ui.Rect.fromLTWH(0, 0, 1100, h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        c.drawParagraph(para, const ui.Offset(60, 60));
        final ui.Image im = await rec.endRecording().toImage(1100, h);
        final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
        final File f = File(p.join((await getTemporaryDirectory()).path, 'vision_${e.key}.png'));
        await f.writeAsBytes(bd!.buffer.asUint8List());
        final OcrResult r = await OcrService().recognizeText(imagePath: f.path, script: script);
        final double s = sim(e.value, r.fullText);
        note('iOS-${e.key}', s >= 0.6 ? 'PASS' : 'FAIL', 'similarity ${(s * 100).round()}% | ${r.fullText}');
        expect(s, greaterThanOrEqualTo(0.6), reason: r.fullText);
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
