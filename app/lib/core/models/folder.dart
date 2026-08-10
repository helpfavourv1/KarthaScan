// lib/core/models/folder.dart
//
// Immutable model per Section 16 (file #10): id, name, documentIds[],
// createdAt. Folder owns the list of document IDs assigned to it (rather
// than ScanDocument owning a folderId) — this is the data-ownership
// direction the blueprint's manifest cells specify, kept as-is for
// consistency with folder_provider.dart (file #22) and folder_screen.dart
// (file #36).
import 'package:flutter/foundation.dart' show immutable, listEquals;

@immutable
class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.documentIds,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<String> documentIds;
  final DateTime createdAt;

  Folder copyWith({
    String? id,
    String? name,
    List<String>? documentIds,
    DateTime? createdAt,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      documentIds: documentIds ?? this.documentIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Convenience for folder_provider.dart's document-assignment operations
  /// — returns a new Folder with [documentId] appended if not already
  /// present, leaving this instance untouched.
  Folder withDocumentAdded(String documentId) {
    if (documentIds.contains(documentId)) return this;
    return copyWith(documentIds: <String>[...documentIds, documentId]);
  }

  /// Convenience for folder_provider.dart — returns a new Folder with
  /// [documentId] removed, leaving this instance untouched. No-op if the
  /// document wasn't assigned to this folder.
  Folder withDocumentRemoved(String documentId) {
    if (!documentIds.contains(documentId)) return this;
    return copyWith(
      documentIds: documentIds.where((String id) => id != documentId).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'documentIds': documentIds,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] as String,
      name: json['name'] as String,
      documentIds: List<String>.from(
        json['documentIds'] as List<dynamic>? ?? const <dynamic>[],
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Folder &&
        other.id == id &&
        other.name == name &&
        listEquals(other.documentIds, documentIds) &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAll(documentIds), createdAt);

  @override
  String toString() =>
      'Folder(id: $id, name: $name, documentCount: ${documentIds.length})';
}
