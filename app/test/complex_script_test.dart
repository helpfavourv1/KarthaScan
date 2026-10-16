// Hindi, Hebrew and Thai lines are drawn as pictures; other text stays text.
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/complex_script_text.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detects joined and right-to-left scripts only', () {
    expect(ComplexScriptText.hasComplex('नमस्ते दुनिया'), isTrue);
    expect(ComplexScriptText.hasComplex('שלום עולם'), isTrue);
    expect(ComplexScriptText.hasComplex('สวัสดี'), isTrue);
    expect(ComplexScriptText.hasComplex('Hello Привет مرحبا 你好'), isFalse);
  });

  testWidgets('a Hindi line becomes a picture, an English line stays text', (WidgetTester tester) async {
    final pw.Widget? picture = await tester.runAsync(
        () => ComplexScriptText.render('नमस्ते दुनिया', fontSize: 12, maxWidth: 400));
    expect(picture, isA<pw.Image>());
    final pw.Widget text = (await tester.runAsync(() => ComplexScriptText.paragraph('Hello')))!;
    expect(text, isA<pw.Paragraph>());
    final pw.Widget hindi = (await tester.runAsync(() => ComplexScriptText.paragraph('नमस्ते')))!;
    expect(hindi, isNot(isA<pw.Paragraph>()));
  });
}
