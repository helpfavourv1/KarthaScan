// lib/core/models/scan_document.dart
//
// Immutable model per Section 16 (file #8) and Section 15's Data Layer
// Rules: final fields, copyWith(), toJson(), fromJson(), ==/hashCode.
//
// Added `isFavorite` to support the Favorites filter chip.

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
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final int pageCount;

  /// Ordered file paths for each scanned page, front-to-back.
  final List<String> pagePaths;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Combined, searchable OCR text across all pages.
  final String ocrText;

  final String thumbnailPath;

  /// Free-form user tags, e.g. "Receipt", "Contract".
  final List<String> tags;

  /// Whether the user has marked this document as favorite.
  final bool isFavorite;

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
    bool? isFavorite,
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
      isFavorite: isFavorite ?? this.isFavorite,
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
      'isFavorite': isFavorite,
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
      isFavorite: json['isFavorite'] as bool? ?? false,
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
        listEquals(other.tags, tags) &&
        other.isFavorite == isFavorite;
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
      isFavorite,
    );
  }

  @override
  String toString() =>
      'ScanDocument(id: $id, title: $title, pageCount: $pageCount, isFavorite: $isFavorite)';
}
