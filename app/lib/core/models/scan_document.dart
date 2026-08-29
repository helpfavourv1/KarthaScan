// lib/core/models/scan_document.dart
//
// Immutable model per Section 16 (file #8) and Section 15's Data Layer
// Rules: final fields, copyWith(), toJson(), fromJson(), ==/hashCode.
//
// Added `isFavorite` to support the Favorites filter chip.

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'signature_placement.dart';

@immutable
class SignatureLayer {
  const SignatureLayer({
    required this.pageIndex,
    required this.placement,
  });

  final int pageIndex;
  final SignaturePlacement placement;

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'pctX': placement.pctX,
    'pctY': placement.pctY,
    'rotationDegrees': placement.rotationDegrees,
    'scale': placement.scale,
  };

  factory SignatureLayer.fromJson(Map<String, dynamic> json) {
    return SignatureLayer(
      pageIndex: json['pageIndex'] as int,
      placement: SignaturePlacement(
        pctX: (json['pctX'] as num).toDouble(),
        pctY: (json['pctY'] as num).toDouble(),
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      ),
    );
  }

  SignatureLayer copyWith({int? pageIndex, SignaturePlacement? placement}) {
    return SignatureLayer(
      pageIndex: pageIndex ?? this.pageIndex,
      placement: placement ?? this.placement,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SignatureLayer &&
        other.pageIndex == pageIndex &&
        other.placement == placement;
  }

  @override
  int get hashCode => Object.hash(pageIndex, placement);
}

@immutable
class AnnotateLayer {
  const AnnotateLayer({
    required this.pageIndex,
    required this.bytesPath,
    required this.placement,
  });

  final int pageIndex;
  final String bytesPath;  // Path to PNG file
  final SignaturePlacement placement;

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'bytesPath': bytesPath,
    'pctX': placement.pctX,
    'pctY': placement.pctY,
    'rotationDegrees': placement.rotationDegrees,
    'scale': placement.scale,
  };

  factory AnnotateLayer.fromJson(Map<String, dynamic> json) {
    return AnnotateLayer(
      pageIndex: json['pageIndex'] as int,
      bytesPath: json['bytesPath'] as String,
      placement: SignaturePlacement(
        pctX: (json['pctX'] as num).toDouble(),
        pctY: (json['pctY'] as num).toDouble(),
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      ),
    );
  }

  AnnotateLayer copyWith({int? pageIndex, String? bytesPath, SignaturePlacement? placement}) {
    return AnnotateLayer(
      pageIndex: pageIndex ?? this.pageIndex,
      bytesPath: bytesPath ?? this.bytesPath,
      placement: placement ?? this.placement,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnnotateLayer &&
        other.pageIndex == pageIndex &&
        other.bytesPath == bytesPath &&
        other.placement == placement;
  }

  @override
  int get hashCode => Object.hash(pageIndex, bytesPath, placement);
}

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
    this.signatureLayers = const <SignatureLayer>[],
    this.annotateLayers = const <AnnotateLayer>[],
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

  /// Non-destructive signature placements per page.
  final List<SignatureLayer> signatureLayers;

  /// Non-destructive annotate placements per page (each with own PNG).
  final List<AnnotateLayer> annotateLayers;

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
    List<SignatureLayer>? signatureLayers,
    List<AnnotateLayer>? annotateLayers,
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
      signatureLayers: signatureLayers ?? this.signatureLayers,
      annotateLayers: annotateLayers ?? this.annotateLayers,
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
      'signatureLayers': signatureLayers.map((l) => l.toJson()).toList(),
      'annotateLayers': annotateLayers.map((l) => l.toJson()).toList(),
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
      signatureLayers: (json['signatureLayers'] as List<dynamic>?)
          ?.map((e) => SignatureLayer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const <SignatureLayer>[],
      annotateLayers: (json['annotateLayers'] as List<dynamic>?)
          ?.map((e) => AnnotateLayer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const <AnnotateLayer>[],
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
        other.isFavorite == isFavorite &&
        listEquals(other.signatureLayers, signatureLayers) &&
        listEquals(other.annotateLayers, annotateLayers);
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
      Object.hashAll(signatureLayers),
      Object.hashAll(annotateLayers),
    );
  }

  @override
  String toString() =>
      'ScanDocument(id: $id, title: $title, pageCount: $pageCount, isFavorite: $isFavorite)';
}
