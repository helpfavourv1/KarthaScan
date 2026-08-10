// lib/core/providers/folder_provider.dart
//
// ValueNotifier<List<Folder>> + activeFolder + document assignment
// (Section 16 file #22).
//
// REACTIVITY: ValueNotifier + ListenableBuilder only, per the MANDATORY
// constraint in constants.dart.
import 'dart:async' show unawaited;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../models/folder.dart';
import '../services/local_storage.dart';

class FolderProvider {
  FolderProvider(this._storage) {
    unawaited(_loadAll());
  }

  final LocalStorageService _storage;
  final Random _random = Random();

  final ValueNotifier<List<Folder>> folders =
      ValueNotifier<List<Folder>>(const <Folder>[]);
  final ValueNotifier<Folder?> activeFolder = ValueNotifier<Folder?>(null);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  Future<void> _loadAll() async {
    isLoading.value = true;
    try {
      folders.value = await _storage.getAllFolders();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refresh() async {
    folders.value = await _storage.getAllFolders();
  }

  Future<Folder?> createFolder(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      lastError.value = 'Folder name cannot be empty.';
      return null;
    }
    final Folder folder = Folder(
      id: _generateId(),
      name: trimmed,
      documentIds: const <String>[],
      createdAt: DateTime.now(),
    );
    final bool success = await _storage.saveFolder(folder);
    if (!success) {
      lastError.value = 'Could not create the folder.';
      return null;
    }
    folders.value = <Folder>[...folders.value, folder];
    return folder;
  }

  Future<bool> renameFolder(String id, String newName) async {
    final Folder? existing = _findById(id);
    if (existing == null) return false;
    final Folder updated = existing.copyWith(name: newName.trim());
    return _replaceAndSave(updated);
  }

  Future<bool> deleteFolder(String id) async {
    final bool success = await _storage.deleteFolder(id);
    if (success) {
      folders.value = folders.value.where((Folder f) => f.id != id).toList();
      if (activeFolder.value?.id == id) {
        activeFolder.value = null;
      }
    } else {
      lastError.value = 'Could not delete the folder.';
    }
    return success;
  }

  /// Adds [documentId] to [folderId]. A document can belong to more than
  /// one folder — Folder owns the document-list side of this relationship
  /// (Section 16 file #10), and ScanDocument doesn't carry a folderId, so
  /// multi-folder membership falls out naturally rather than needing
  /// special support.
  Future<bool> addDocumentToFolder(String folderId, String documentId) async {
    final Folder? existing = _findById(folderId);
    if (existing == null) return false;
    return _replaceAndSave(existing.withDocumentAdded(documentId));
  }

  Future<bool> removeDocumentFromFolder(
    String folderId,
    String documentId,
  ) async {
    final Folder? existing = _findById(folderId);
    if (existing == null) return false;
    return _replaceAndSave(existing.withDocumentRemoved(documentId));
  }

  /// Called by whatever deletes a document (scan_provider.dart) so it's
  /// cleaned out of every folder's documentIds rather than leaving a
  /// dangling reference behind.
  Future<void> removeDocumentFromAllFolders(String documentId) async {
    for (final Folder folder in folders.value) {
      if (folder.documentIds.contains(documentId)) {
        await _replaceAndSave(folder.withDocumentRemoved(documentId));
      }
    }
  }

  void setActiveFolder(String? id) {
    activeFolder.value = id == null ? null : _findById(id);
  }

  Folder? _findById(String id) {
    for (final Folder folder in folders.value) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  Future<bool> _replaceAndSave(Folder updated) async {
    final bool success = await _storage.saveFolder(updated);
    if (success) {
      folders.value = folders.value
          .map((Folder f) => f.id == updated.id ? updated : f)
          .toList();
      if (activeFolder.value?.id == updated.id) {
        activeFolder.value = updated;
      }
    } else {
      lastError.value = 'Could not save changes to this folder.';
    }
    return success;
  }

  String _generateId() {
    final int ts = DateTime.now().microsecondsSinceEpoch;
    final int rand = _random.nextInt(0x7fffffff);
    return '$ts-$rand';
  }

  void dispose() {
    folders.dispose();
    activeFolder.dispose();
    isLoading.dispose();
    lastError.dispose();
  }
}
