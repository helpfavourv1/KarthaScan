// lib/core/models/scan_document.dart
//
// Immutable model per Section 16 (file #8) and Section 15's Data Layer
// Rules: final fields, copyWith(), toJson(), fromJson(), ==/hashCode.
//
// FIELD NOTE: the blueprint's manifest cell lists the defining fields as
// "id, title, pageCount, createdAt, updatedAt, ocrText, thumbnailPath".
// This implementation adds two fields beyond that minimum:
//   - `pagePaths`: the actual per-page image file paths. Without this a
//     multi-page document has a page *count* but nothing to render, export,
//     or re-run OCR against — thumbnailPath alone only covers one page.
//     This isn't optional for a working scanner; it's a gap in the summary
//     table, not a deviation from it.
//   - `tags`: supports the already-manifested tag_chip.dart (file #33) and
//     the Pro "custom tags" feature (Section 19). Defaulted to an empty
//     list so every existing call site stays valid; added now rather than
//     retrofitted later to avoid a breaking constructor change once
//     Phase 3/4 files start constructing ScanDocument instances.
import 'package:flutter/foundation.dart' show immutable, listEquals;

@immutable
class ScanDocument {
  const ScanDocument({
    required this.id,
    required this.title,
    required this.pageCount,
    required this.pagePaths,
    required this.createdAt,
    required this.updatedAt,
    required this.ocrText,
    required this.thumbnailPath,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final int pageCount;

  /// Ordered file paths for each scanned page, front-to-back. Length must
  /// equal [pageCount]; callers that mutate page order or count should go
  /// through [copyWith] with both fields together to avoid them drifting
  /// out of sync.
  final List<String> pagePaths;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Combined, searchable OCR text across all pages (Section 16 file #13:
  /// "FTS5 search index").
  final String ocrText;

  final String thumbnailPath;

  /// Free-form user tags, e.g. "Receipt", "Contract" (file #33). Pro-gated
  /// at the UI/feature level (Section 19), not enforced by the model.
  final List<String> tags;

  ScanDocument copyWith({
    String? id,
    String? title,
    int? pageCount,
    List<String>? pagePaths,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? ocrText,
    String? thumbnailPath,
    List<String>? tags,
  }) {
    return ScanDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      pageCount: pageCount ?? this.pageCount,
      pagePaths: pagePaths ?? this.pagePaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ocrText: ocrText ?? this.ocrText,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'pageCount': pageCount,
      'pagePaths': pagePaths,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'ocrText': ocrText,
      'thumbnailPath': thumbnailPath,
      'tags': tags,
    };
  }

  factory ScanDocument.fromJson(Map<String, dynamic> json) {
    return ScanDocument(
      id: json['id'] as String,
      title: json['title'] as String,
      pageCount: json['pageCount'] as int,
      pagePaths: List<String>.from(json['pagePaths'] as List<dynamic>? ?? const <dynamic>[]),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      ocrText: json['ocrText'] as String,
      thumbnailPath: json['thumbnailPath'] as String,
      tags: List<String>.from(json['tags'] as List<dynamic>? ?? const <dynamic>[]),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScanDocument &&
        other.id == id &&
        other.title == title &&
        other.pageCount == pageCount &&
        listEquals(other.pagePaths, pagePaths) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.ocrText == ocrText &&
        other.thumbnailPath == thumbnailPath &&
        listEquals(other.tags, tags);
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      pageCount,
      Object.hashAll(pagePaths),
      createdAt,
      updatedAt,
      ocrText,
      thumbnailPath,
      Object.hashAll(tags),
    );
  }

  @override
  String toString() =>
      'ScanDocument(id: $id, title: $title, pageCount: $pageCount)';
}
