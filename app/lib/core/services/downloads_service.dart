import 'dart:io' show Platform;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Cross-platform "save to device" bridge.
/// Android: native MediaStore Downloads via the MainActivity.kt channel.
/// iOS: native UIDocumentPickerViewController via file_saver, allowing the
/// user to save the file to their "Files" app (including the Downloads folder).
class DownloadsService {
  static const MethodChannel _channel =
      MethodChannel('com.zdmgold.katharscan/downloads');

  Future<String> saveToDownloads({
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('saveToDownloads', {
          'fileName': fileName,
          'bytes': bytes,
          'mimeType': mimeType,
        });
        if (result == null) throw Exception('Native save returned null');
        return result;
      } on PlatformException catch (e) {
        throw Exception('Save failed: ${e.message}');
      }
    }

    // iOS fallback: Invokes the native document picker.
    final int dot = fileName.lastIndexOf('.');
    final String base = dot == -1 ? fileName : fileName.substring(0, dot);
    final String ext = dot == -1 ? 'bin' : fileName.substring(dot + 1);
    
    try {
      final String savedPath = await FileSaver.instance.saveFile(
        name: base,
        bytes: Uint8List.fromList(bytes),
        ext: ext,
        mimeType: _mapMime(mimeType),
      );
      return savedPath;
    } catch (e) {
      debugPrint('[DownloadsService] iOS document-picker save failed: $e');
      throw Exception('Save failed: $e');
    }
  }

  MimeType _mapMime(String mimeType) {
    switch (mimeType) {
      case 'application/pdf':
        return MimeType.pdf;
      case 'image/png':
        return MimeType.png;
      case 'image/jpeg':
        return MimeType.jpeg;
      default:
        return MimeType.other;
    }
  }
}
