import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'debug_log_service.dart';

/// Chinese, Japanese and Korean fonts are 6-11 MB each, so they are not part of
/// the app. They are downloaded once, from this project's GitHub repository,
/// the first time a PDF needs them, checked against a fixed checksum and kept
/// in the app's private folder.
class RemoteFont {
  const RemoteFont(this.fileName, this.bytes, this.sha256Hex);
  final String fileName;
  final int bytes;
  final String sha256Hex;
}

class RemoteFonts {
  RemoteFonts._();

  static const String baseUrl =
      'https://raw.githubusercontent.com/helpfavourv1/KarthaScan/main/fonts_remote/';

  static const RemoteFont sc = RemoteFont('NotoSansSC-Regular.ttf', 10595892,
      'd50b2d4242ed2c21a0c31210c404773763e69541f637506a014bbda9d2fedcd6');
  static const RemoteFont jp = RemoteFont('NotoSansJP-Regular.ttf', 5766844,
      '4d597e5647bab3bcb7bf5454aa82ce49de3109416b2ac714e85fcbf79a816771');
  static const RemoteFont kr = RemoteFont('NotoSansKR-Regular.ttf', 6224828,
      'c7d62df831b864f93ea74ecd40a0ef78c358521bb971348766952f4b05733210');

  /// Tests point this at a folder that already holds the fonts.
  static Directory? directoryOverride;

  /// A failed download is not retried for a few minutes, so a many-page PDF made
  /// offline does not wait on the network for every page.
  static final Map<String, DateTime> _failedAt = <String, DateTime>{};

  static bool _isHangul(int c) =>
      (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F);
  static bool _isKana(int c) => (c >= 0x3040 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF);
  static bool _isHan(int c) =>
      (c >= 0x4E00 && c <= 0x9FFF) ||
      (c >= 0x3400 && c <= 0x4DBF) ||
      (c >= 0x3000 && c <= 0x303F) ||
      (c >= 0xFF00 && c <= 0xFFEF) ||
      (c >= 0xF900 && c <= 0xFAFF) ||
      (c >= 0x20000 && c <= 0x2A6DF);

  /// The fonts [text] needs, best match first. Korean text needs the Korean
  /// font, Japanese kana the Japanese one, any other Han text the Chinese one.
  static List<RemoteFont> neededFor(String text) {
    bool hangul = false, kana = false, han = false;
    for (final int c in text.runes) {
      if (c < 0x1100) continue;
      if (_isHangul(c)) {
        hangul = true;
      } else if (_isKana(c)) {
        kana = true;
      } else if (_isHan(c)) {
        han = true;
      }
    }
    return <RemoteFont>[
      if (hangul) kr,
      if (kana) jp,
      if (han && !hangul && !kana) sc,
    ];
  }

  static Future<Directory> _dir() async {
    final Directory? o = directoryOverride;
    if (o != null) return o;
    final Directory base = await getApplicationSupportDirectory();
    final Directory d = Directory(p.join(base.path, 'fonts'));
    await d.create(recursive: true);
    return d;
  }

  /// The font file, downloading it first if needed. Null when it cannot be
  /// had (offline, bad checksum); the PDF is then made without it.
  static Future<File?> ensure(RemoteFont font) async {
    try {
      final File file = File(p.join((await _dir()).path, font.fileName));
      if (await file.exists() && await file.length() == font.bytes) return file;
      final DateTime? failed = _failedAt[font.fileName];
      if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 5)) return null;

      final File part = File('${file.path}.part');
      final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      try {
        final HttpClientRequest req = await client.getUrl(Uri.parse('$baseUrl${font.fileName}'));
        final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
        final IOSink sink = part.openWrite();
        await res.timeout(const Duration(seconds: 60)).pipe(sink);
      } finally {
        client.close(force: true);
      }
      final String hash = sha256.convert(await part.readAsBytes()).toString();
      if (hash != font.sha256Hex) {
        await part.delete();
        throw const FormatException('font checksum mismatch');
      }
      return await part.rename(file.path);
    } catch (error) {
      _failedAt[font.fileName] = DateTime.now();
      DebugLogService().log('REMOTE_FONT', 'Could not get ${font.fileName}: $error');
      return null;
    }
  }
}
