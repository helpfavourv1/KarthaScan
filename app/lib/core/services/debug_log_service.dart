// lib/core/services/debug_log_service.dart
import 'dart:io' show Directory, File, FileMode;
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class DebugLogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;

  const DebugLogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
  });

  String toLine() => '${timestamp.toIso8601String()} [$tag] $message';

  static DebugLogEntry? fromLine(String line) {
    final int tagStart = line.indexOf(' [');
    final int tagEnd = line.indexOf('] ', tagStart);
    if (tagStart == -1 || tagEnd == -1) return null;
    final String iso = line.substring(0, tagStart);
    final String tag = line.substring(tagStart + 2, tagEnd);
    final String message = line.substring(tagEnd + 2);
    final DateTime? ts = DateTime.tryParse(iso);
    if (ts == null) return null;
    return DebugLogEntry(timestamp: ts, tag: tag, message: message);
  }
}

class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal() {
    _init();
  }

  final List<DebugLogEntry> _logs = <DebugLogEntry>[];
  final ValueNotifier<List<DebugLogEntry>> logs =
      ValueNotifier<List<DebugLogEntry>>(const <DebugLogEntry>[]);
  File? _logFile;
  static const int _maxLines = 500;

  Future<void> _init() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(dir.path, 'katharscan_debug.log'));
      if (_logFile!.existsSync()) {
        final List<String> lines = await _logFile!.readAsLines();
        for (final String line in lines) {
          final DebugLogEntry? entry = DebugLogEntry.fromLine(line);
          if (entry != null) _logs.add(entry);
        }
        logs.value = List<DebugLogEntry>.unmodifiable(_logs);
      }
    } catch (e) {
      debugPrint('DebugLogService init error: $e');
    }
  }

  void log(String tag, String message) {
    final DebugLogEntry entry = DebugLogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
    );
    _logs.add(entry);
    logs.value = List<DebugLogEntry>.unmodifiable(_logs);
    debugPrint('[$tag] $message');
    _persist(entry);
  }

  Future<void> _persist(DebugLogEntry entry) async {
    try {
      if (_logFile == null) return;
      final sink = _logFile!.openWrite(mode: FileMode.append);
      sink.writeln(entry.toLine());
      await sink.close();

      final List<String> lines = await _logFile!.readAsLines();
      if (lines.length > _maxLines) {
        final trimmed = lines.sublist(lines.length - _maxLines);
        await _logFile!.writeAsString('${trimmed.join('\n')}\n');
      }
    } catch (e) {
      debugPrint('DebugLogService persist error: $e');
    }
  }

  void clear() {
    _logs.clear();
    logs.value = const <DebugLogEntry>[];
    try {
      _logFile?.deleteSync();
    } catch (_) {}
  }

  int get count => _logs.length;
}
