// lib/core/services/debug_log_service.dart
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;

class DebugLogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;

  const DebugLogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
  });
}

/// Singleton in-memory logger. Every subsystem writes here; the Debug Logs
/// screen in Settings reads it. No persistence — logs survive for the
/// current session only, which is exactly what we need for debugging.
class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<DebugLogEntry> _logs = <DebugLogEntry>[];
  final ValueNotifier<List<DebugLogEntry>> logs =
      ValueNotifier<List<DebugLogEntry>>(const <DebugLogEntry>[]);

  void log(String tag, String message) {
    final DebugLogEntry entry = DebugLogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
    );
    _logs.add(entry);
    logs.value = List<DebugLogEntry>.unmodifiable(_logs);
    debugPrint('[$tag] $message');
  }

  void clear() {
    _logs.clear();
    logs.value = const <DebugLogEntry>[];
  }

  int get count => _logs.length;
}
