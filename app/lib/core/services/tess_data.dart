import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'debug_log_service.dart';

/// One Tesseract language file (tessdata_fast, Apache-2.0).
class TessPack {
  const TessPack(this.fileName, this.bytes, this.sha256Hex);
  final String fileName;
  final int bytes;
  final String sha256Hex;
}

/// Language files for the scripts Google's on-device OCR does not cover
/// (Arabic, Cyrillic, Greek, Hebrew, Thai, Bengali). They are 1-4 MB each, so
/// they are not part of the app: each is downloaded from the app website the
/// first time it is used, checked against a fixed checksum, and then works
/// offline from the app's private folder.
class TessData {
  TessData._();

  static const List<String> baseUrls = <String>[
    'https://katharscan.helpfavourv1.workers.dev/tessdata/',
    'https://raw.githubusercontent.com/helpfavourv1/KarthaScan/main/website/tessdata/',
  ];

  static const Map<String, TessPack> packs = <String, TessPack>{
    'ara': TessPack('ara.traineddata', 1432056, 'e3206d3dc87fd50c24a0fb9f01838615911d25168f4e64415244b67d2bb3e729'),
    'ben': TessPack('ben.traineddata', 855841, '31163084c279aaebd376216f0c3d5c17ad4b5fee8db49dae79c20000b5de5964'),
    'ell': TessPack('ell.traineddata', 1419514, '4fba8a0b461038d51f1c20d043d4f2ac38c4e778f1b90830847f7bd8fa3ba726'),
    'heb': TessPack('heb.traineddata', 961404, '11f9e43ab227f786352a50f75c94c2e9906f1baba86d93276da19da7ce0904db'),
    'rus': TessPack('rus.traineddata', 3861738, 'e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225'),
    'tha': TessPack('tha.traineddata', 1072600, '294227cc2d1292b0acb28d61d4115c88252b96d466ca90b417cf4cf0c67bf07c'),
    'ukr': TessPack('ukr.traineddata', 3825102, 'd59e53e2bded32f4445f124b4b00240fcac7e8044c003ab822ccb94f0b3db59b'),
  };

  /// Tests point this at a folder that already holds the files.
  static Directory? directoryOverride;

  static final Map<String, DateTime> _failedAt = <String, DateTime>{};

  /// Folder that contains `tessdata/` (what Tesseract's init expects).
  static Future<Directory> root() async {
    final Directory? o = directoryOverride;
    if (o != null) return o;
    final Directory base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'tess'));
  }

  static Future<File> _file(TessPack pack) async =>
      File(p.join((await root()).path, 'tessdata', pack.fileName));

  static Future<bool> isInstalled(String code) async {
    final TessPack? pack = packs[code];
    if (pack == null) return false;
    final File f = await _file(pack);
    return await f.exists() && await f.length() == pack.bytes;
  }

  /// Downloads the pack if needed. Returns false when it cannot be had
  /// (offline, bad checksum).
  static Future<bool> ensure(String code, {bool download = true}) async {
    final TessPack? pack = packs[code];
    if (pack == null) return false;
    try {
      if (await isInstalled(code)) return true;
      if (!download) return false;
      final DateTime? failed = _failedAt[code];
      if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 2)) return false;

      final File file = await _file(pack);
      await file.parent.create(recursive: true);
      final File part = File('${file.path}.part');
      Object? lastError;
      bool ok = false;
      for (final String base in baseUrls) {
        final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
        try {
          final HttpClientRequest req = await client.getUrl(Uri.parse('$base${pack.fileName}'));
          final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
          final IOSink sink = part.openWrite();
          await res.timeout(const Duration(seconds: 90)).pipe(sink);
          final String hash = sha256.convert(await part.readAsBytes()).toString();
          if (hash != pack.sha256Hex) throw const FormatException('language file checksum mismatch');
          ok = true;
          break;
        } catch (error) {
          lastError = error;
          if (await part.exists()) await part.delete();
        } finally {
          client.close(force: true);
        }
      }
      if (!ok) throw lastError ?? const HttpException('download failed');
      await part.rename(file.path);
      return true;
    } catch (error) {
      _failedAt[code] = DateTime.now();
      DebugLogService().log('TESS', 'Could not get $code: $error');
      return false;
    }
  }
}
