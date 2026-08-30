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
    this.inkId = 'default',
  });

  final int pageIndex;
  final SignaturePlacement placement;
  final String inkId;

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'inkId': inkId,
    'pctX': placement.pctX,
    'pctY': placement.pctY,
    'rotationDegrees': placement.rotationDegrees,
    'scale': placement.scale,
  };

  factory SignatureLayer.fromJson(Map<String, dynamic> json) {
    return SignatureLayer(
      pageIndex: json['pageIndex'] as int,
      inkId: json['inkId'] as String? ?? 'default',
      placement: SignaturePlacement(
        pctX: (json['pctX'] as num).toDouble(),
        pctY: (json['pctY'] as num).toDouble(),
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      ),
    );
  }

  SignatureLayer copyWith({int? pageIndex, SignaturePlacement? placement, String? inkId}) {
    return SignatureLayer(
      pageIndex: pageIndex ?? this.pageIndex,
      placement: placement ?? this.placement,
      inkId: inkId ?? this.inkId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SignatureLayer &&
        other.pageIndex == pageIndex &&
        other.placement == placement &&
        other.inkId == inkId;
  }

  @override
  int get hashCode => Object.hash(pageIndex, placement, inkId);
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
@immutable
class WatermarkLayer {
  const WatermarkLayer({
    required this.pageIndex,
    required this.text,
    required this.placement,
    this.opacity = 0.15,
    this.fontSize = 48,
    this.color = 0xFF8E8E93,
    this.fontFamily = 'sans-serif',
    this.bold = true,
    this.italic = false,
    this.underline = false,
    this.outlineColor,
    this.outlineWidth = 0,
    this.shadowOffsetX = 0,
    this.shadowOffsetY = 0,
    this.shadowColor,
    this.align = 'center',
  });

  final int pageIndex;
  final String text;
  final SignaturePlacement placement;
  final double opacity;
  final double fontSize;
  final int color;
  final String fontFamily;
  final bool bold;
  final bool italic;
  final bool underline;
  final int? outlineColor;
  final double outlineWidth;
  final double shadowOffsetX;
  final double shadowOffsetY;
  final int? shadowColor;
  final String align;

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'text': text,
    'pctX': placement.pctX,
    'pctY': placement.pctY,
    'rotationDegrees': placement.rotationDegrees,
    'scale': placement.scale,
    'opacity': opacity,
    'fontSize': fontSize,
    'color': color,
    'fontFamily': fontFamily,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'outlineColor': outlineColor,
    'outlineWidth': outlineWidth,
    'shadowOffsetX': shadowOffsetX,
    'shadowOffsetY': shadowOffsetY,
    'shadowColor': shadowColor,
    'align': align,
  };

  factory WatermarkLayer.fromJson(Map<String, dynamic> json) {
    return WatermarkLayer(
      pageIndex: json['pageIndex'] as int,
      text: json['text'] as String,
      placement: SignaturePlacement(
        pctX: (json['pctX'] as num).toDouble(),
        pctY: (json['pctY'] as num).toDouble(),
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      ),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.15,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 48,
      color: json['color'] as int? ?? 0xFF8E8E93,
      fontFamily: json['fontFamily'] as String? ?? 'sans-serif',
      bold: json['bold'] as bool? ?? true,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      outlineColor: json['outlineColor'] as int?,
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0,
      shadowOffsetX: (json['shadowOffsetX'] as num?)?.toDouble() ?? 0,
      shadowOffsetY: (json['shadowOffsetY'] as num?)?.toDouble() ?? 0,
      shadowColor: json['shadowColor'] as int?,
      align: json['align'] as String? ?? 'center',
    );
  }

  WatermarkLayer copyWith({
    int? pageIndex,
    String? text,
    SignaturePlacement? placement,
    double? opacity,
    double? fontSize,
    int? color,
    String? fontFamily,
    bool? bold,
    bool? italic,
    bool? underline,
    int? outlineColor,
    double? outlineWidth,
    double? shadowOffsetX,
    double? shadowOffsetY,
    int? shadowColor,
    String? align,
  }) {
    return WatermarkLayer(
      pageIndex: pageIndex ?? this.pageIndex,
      text: text ?? this.text,
      placement: placement ?? this.placement,
      opacity: opacity ?? this.opacity,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      outlineColor: outlineColor ?? this.outlineColor,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      shadowOffsetX: shadowOffsetX ?? this.shadowOffsetX,
      shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
      shadowColor: shadowColor ?? this.shadowColor,
      align: align ?? this.align,
    );
  }
}

@immutable
class StampLayer {
  const StampLayer({
    required this.id,
    required this.pageIndex,
    required this.kind,
    required this.placement,
    this.opacity = 1.0,
    this.text = '',
    this.fontSize = 72,
    this.color = 0xFF111111,
    this.fontFamily = 'sans-serif',
    this.fontWeight = 700,
    this.align = 'left',
    this.halo = false,
    this.noteBgColor,
    this.dateFormat,
    this.customDateMillis,
    this.checked,
    this.checkShape,
    this.boxColor,
    this.tickColor,
    this.sealShape = 'round',
    this.sealSubtext = '',
    this.sealCenter = 'star',
  });

  final String id;
  final int pageIndex;
  final String kind;
  final SignaturePlacement placement;
  final double opacity;
  final String text;
  final double fontSize;
  final int color;
  final String fontFamily;
  final int fontWeight;
  final String align;
  final bool halo;
  final int? noteBgColor;
  final String? dateFormat;
  final int? customDateMillis;
  final bool? checked;
  final String? checkShape;
  final int? boxColor;
  final int? tickColor;
  final String sealShape;
  final String sealSubtext;
  final String sealCenter;

  Map<String, dynamic> toJson() => {
    'id': id, 'pageIndex': pageIndex, 'kind': kind,
    'pctX': placement.pctX, 'pctY': placement.pctY,
    'rotationDegrees': placement.rotationDegrees, 'scale': placement.scale,
    'opacity': opacity, 'text': text, 'fontSize': fontSize, 'color': color,
    'fontFamily': fontFamily, 'fontWeight': fontWeight, 'align': align, 'halo': halo,
    'noteBgColor': noteBgColor, 'dateFormat': dateFormat, 'customDateMillis': customDateMillis,
    'checked': checked, 'checkShape': checkShape, 'boxColor': boxColor, 'tickColor': tickColor,
    'sealShape': sealShape, 'sealSubtext': sealSubtext, 'sealCenter': sealCenter,
  };

  factory StampLayer.fromJson(Map<String, dynamic> json) {
    return StampLayer(
      id: json['id'] as String,
      pageIndex: json['pageIndex'] as int,
      kind: json['kind'] as String,
      placement: SignaturePlacement(
        pctX: (json['pctX'] as num).toDouble(),
        pctY: (json['pctY'] as num).toDouble(),
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      ),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 72,
      color: json['color'] as int? ?? 0xFF111111,
      fontFamily: json['fontFamily'] as String? ?? 'sans-serif',
      fontWeight: json['fontWeight'] as int? ?? 700,
      align: json['align'] as String? ?? 'left',
      halo: json['halo'] as bool? ?? false,
      noteBgColor: json['noteBgColor'] as int?,
      dateFormat: json['dateFormat'] as String?,
      customDateMillis: json['customDateMillis'] as int?,
      checked: json['checked'] as bool?,
      checkShape: json['checkShape'] as String?,
      boxColor: json['boxColor'] as int?,
      tickColor: json['tickColor'] as int?,
      sealShape: json['sealShape'] as String? ?? 'round',
      sealSubtext: json['sealSubtext'] as String? ?? '',
      sealCenter: json['sealCenter'] as String? ?? 'star',
    );
  }

  StampLayer copyWith({
    String? id, int? pageIndex, String? kind, SignaturePlacement? placement,
    double? opacity, String? text, double? fontSize, int? color, String? fontFamily,
    int? fontWeight, String? align, bool? halo, int? noteBgColor, String? dateFormat,
    int? customDateMillis, bool? checked, String? checkShape, int? boxColor, int? tickColor,
    String? sealShape, String? sealSubtext, String? sealCenter,
  }) {
    return StampLayer(
      id: id ?? this.id, pageIndex: pageIndex ?? this.pageIndex, kind: kind ?? this.kind,
      placement: placement ?? this.placement, opacity: opacity ?? this.opacity,
      text: text ?? this.text, fontSize: fontSize ?? this.fontSize, color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily, fontWeight: fontWeight ?? this.fontWeight,
      align: align ?? this.align, halo: halo ?? this.halo, noteBgColor: noteBgColor ?? this.noteBgColor,
      dateFormat: dateFormat ?? this.dateFormat, customDateMillis: customDateMillis ?? this.customDateMillis,
      checked: checked ?? this.checked, checkShape: checkShape ?? this.checkShape,
      boxColor: boxColor ?? this.boxColor, tickColor: tickColor ?? this.tickColor,
      sealShape: sealShape ?? this.sealShape, sealSubtext: sealSubtext ?? this.sealSubtext, sealCenter: sealCenter ?? this.sealCenter,
    );
  }
}

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
    this.signatureInks = const <SignatureInk>[],
    this.signatureLayers = const <SignatureLayer>[],
    this.annotateLayers = const <AnnotateLayer>[],
    this.watermarkLayers = const <WatermarkLayer>[],
    this.stampLayers = const <StampLayer>[],
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

  /// Signature inks (bytes + metadata) for this document.
  final List<SignatureInk> signatureInks;

  /// Non-destructive signature placements per page (references inkId).
  final List<SignatureLayer> signatureLayers;

  /// Non-destructive annotate placements per page (each with own PNG).
  final List<AnnotateLayer> annotateLayers;
  final List<WatermarkLayer> watermarkLayers;
  final List<StampLayer> stampLayers;

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
    List<SignatureInk>? signatureInks,
    List<SignatureLayer>? signatureLayers,
    List<AnnotateLayer>? annotateLayers,
    List<WatermarkLayer>? watermarkLayers,
    List<StampLayer>? stampLayers,
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
      signatureInks: signatureInks ?? this.signatureInks,
      signatureLayers: signatureLayers ?? this.signatureLayers,
      annotateLayers: annotateLayers ?? this.annotateLayers,
      watermarkLayers: watermarkLayers ?? this.watermarkLayers,
      stampLayers: stampLayers ?? this.stampLayers,
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
      'signatureInks': signatureInks.map((i) => i.toJson()).toList(),
      'signatureLayers': signatureLayers.map((l) => l.toJson()).toList(),
      'annotateLayers': annotateLayers.map((l) => l.toJson()).toList(),
      'watermarkLayers': watermarkLayers.map((l) => l.toJson()).toList(),
      'stampLayers': stampLayers.map((l) => l.toJson()).toList(),
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
      signatureInks: (json['signatureInks'] as List<dynamic>?)
          ?.map((e) => SignatureInk.fromJson(e as Map<String, dynamic>))
          .toList() ?? const <SignatureInk>[],
      signatureLayers: (json['signatureLayers'] as List<dynamic>?)
          ?.map((e) => SignatureLayer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const <SignatureLayer>[],
      annotateLayers: (json['annotateLayers'] as List<dynamic>?)
          ?.map((e) => AnnotateLayer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const <AnnotateLayer>[],
      watermarkLayers: (json['watermarkLayers'] as List<dynamic>?)
          ?.map((e) => WatermarkLayer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const <WatermarkLayer>[],
      stampLayers: (json['stampLayers'] as List<dynamic>?)
          ?.map((e) => StampLayer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const <StampLayer>[],
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
        listEquals(other.signatureInks, signatureInks) &&
        listEquals(other.signatureLayers, signatureLayers) &&
        listEquals(other.annotateLayers, annotateLayers) &&
        listEquals(other.watermarkLayers, watermarkLayers) &&
        listEquals(other.stampLayers, stampLayers);
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
      Object.hashAll(signatureInks),
      Object.hashAll(signatureLayers),
      Object.hashAll(annotateLayers),
      Object.hashAll(watermarkLayers),
      Object.hashAll(stampLayers),
    );
  }

  @override
  String toString() =>
      'ScanDocument(id: $id, title: $title, pageCount: $pageCount, isFavorite: $isFavorite)';
}
