import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/pdf_to_images_service.dart';

void main() {
  test('A4 renders at 2x', () {
    final (int w, int h) = PdfToImagesService.targetSize(595, 842);
    expect((w, h), (1190, 1684));
  });

  test('a poster page is capped at 3000 px on its longest side, aspect ratio kept', () {
    final (int w, int h) = PdfToImagesService.targetSize(2384, 3370); // A0
    expect(h, 3000);
    expect((w / h - 2384 / 3370).abs() < 0.002, isTrue);
    expect(w * h * 4, lessThan(40 * 1024 * 1024), reason: 'one page must stay under 40 MB');
  });

  test('landscape pages are capped on the width', () {
    final (int w, int h) = PdfToImagesService.targetSize(5000, 1000);
    expect(w, 3000);
    expect(h, 600);
  });

  test('degenerate sizes never return zero', () {
    final (int w, int h) = PdfToImagesService.targetSize(0.1, 0.1);
    expect(w, greaterThanOrEqualTo(1));
    expect(h, greaterThanOrEqualTo(1));
  });
}
