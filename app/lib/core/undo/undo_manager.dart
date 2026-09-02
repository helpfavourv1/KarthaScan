import 'package:flutter/foundation.dart' show ValueNotifier;

/// A single reversible operation. [undo] restores prior state, [redo]
/// re-applies it. [coalesceKey] lets rapid successive ops on the same
/// target (e.g. a drag gesture) merge into one undo step.
class UndoCommand {
  UndoCommand({required this.undo, required this.redo, this.coalesceKey});
  final Future<void> Function() undo;
  final Future<void> Function() redo;
  final String? coalesceKey;
}

class UndoManager {
  static const int _maxDepth = 50;
  static const Duration _coalesceWindow = Duration(milliseconds: 800);

  final ValueNotifier<int> version = ValueNotifier<int>(0);
  final List<UndoCommand> _undoStack = <UndoCommand>[];
  final List<UndoCommand> _redoStack = <UndoCommand>[];
  DateTime _lastRecord = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void record(UndoCommand cmd) {
    final now = DateTime.now();
    final merge = cmd.coalesceKey != null &&
        _undoStack.isNotEmpty &&
        _undoStack.last.coalesceKey == cmd.coalesceKey &&
        now.difference(_lastRecord) < _coalesceWindow;
    if (merge) {
      final keep = _undoStack.removeLast();
      _undoStack.add(UndoCommand(
          undo: keep.undo, redo: cmd.redo, coalesceKey: cmd.coalesceKey));
    } else {
      _undoStack.add(cmd);
      if (_undoStack.length > _maxDepth) _undoStack.removeAt(0);
    }
    _lastRecord = now;
    _redoStack.clear();
    version.value++;
  }

  Future<void> undo() async {
    if (_busy || _undoStack.isEmpty) return;
    _busy = true;
    try {
      final cmd = _undoStack.removeLast();
      await cmd.undo();
      _redoStack.add(cmd);
    } finally {
      _busy = false;
      version.value++;
    }
  }

  Future<void> redo() async {
    if (_busy || _redoStack.isEmpty) return;
    _busy = true;
    try {
      final cmd = _redoStack.removeLast();
      await cmd.redo();
      _undoStack.add(cmd);
    } finally {
      _busy = false;
      version.value++;
    }
  }

  void clear() {
    if (_undoStack.isEmpty && _redoStack.isEmpty) return;
    _undoStack.clear();
    _redoStack.clear();
    version.value++;
  }
}
