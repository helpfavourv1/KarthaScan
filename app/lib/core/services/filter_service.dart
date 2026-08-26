import 'package:image/image.dart' as img;
import 'export_service.dart' show FilterType;

abstract final class FilterService {
  static img.Image applyToImage(img.Image source, FilterType filter) {
    switch (filter) {
      case FilterType.none:
        return source;
      case FilterType.grayscale:
        return img.grayscale(source);
      case FilterType.blackAndWhite:
        final gray = img.grayscale(source);
        return img.adjustColor(gray, contrast: 3.0, brightness: 1.05);
      case FilterType.colorEnhance:
        return img.adjustColor(source, contrast: 1.15, saturation: 1.2, brightness: 1.05);
      case FilterType.shadowRemoval:
        return img.adjustColor(source, contrast: 1.2, brightness: 1.15, gamma: 0.9);
    }
  }
}
