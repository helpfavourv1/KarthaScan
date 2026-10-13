import 'package:image/image.dart' as img;
import 'export_service.dart' show FilterType;

abstract final class FilterService {
  static img.Image applyToImage(img.Image source, FilterType filter, {double intensity = 1.0}) {
    img.Image filtered;
    // The image package edits pictures in place. When the result is blended
    // with the original (intensity below 1), the filter must work on a copy,
    // otherwise "original" and "filtered" are the same picture and the
    // slider does nothing.
    final img.Image work = intensity == 1.0 ? source : source.clone();
    switch (filter) {
      case FilterType.none:
        return source;
      case FilterType.grayscale:
        filtered = img.grayscale(work);
        break;
      case FilterType.blackAndWhite:
        final gray = img.grayscale(work);
        final c = 1.0 + (3.0 - 1.0) * intensity;
        final b = 1.0 + (1.05 - 1.0) * intensity;
        filtered = img.adjustColor(gray, contrast: c, brightness: b);
        break;
      case FilterType.colorEnhance:
        final c = 1.0 + (1.15 - 1.0) * intensity;
        final s = 1.0 + (1.2 - 1.0) * intensity;
        final b = 1.0 + (1.05 - 1.0) * intensity;
        filtered = img.adjustColor(work, contrast: c, saturation: s, brightness: b);
        break;
      case FilterType.shadowRemoval:
        final c = 1.0 + (1.2 - 1.0) * intensity;
        final b = 1.0 + (1.15 - 1.0) * intensity;
        final g = 1.0 + (0.9 - 1.0) * intensity;
        filtered = img.adjustColor(work, contrast: c, brightness: b, gamma: g);
        break;
    }
    if (intensity == 1.0) return filtered;
    final out = img.Image(width: source.width, height: source.height);
    for (int y = 0; y < source.height; y++) {
      for (int x = 0; x < source.width; x++) {
        final bp = source.getPixel(x, y);
        final fp = filtered.getPixel(x, y);
        final r = (bp.r.toInt() + (fp.r.toInt() - bp.r.toInt()) * intensity).clamp(0, 255).round();
        final g = (bp.g.toInt() + (fp.g.toInt() - bp.g.toInt()) * intensity).clamp(0, 255).round();
        final b = (bp.b.toInt() + (fp.b.toInt() - bp.b.toInt()) * intensity).clamp(0, 255).round();
        final a = (bp.a.toInt() + (fp.a.toInt() - bp.a.toInt()) * intensity).clamp(0, 255).round();
        out.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return out;
  }
}
