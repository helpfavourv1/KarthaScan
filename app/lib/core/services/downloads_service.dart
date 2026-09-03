import 'package:flutter/services.dart';

class DownloadsService {
  static const MethodChannel _channel = MethodChannel('com.zdmgold.katharscan/downloads');

  Future<String> saveToDownloads({
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) async {
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
}
