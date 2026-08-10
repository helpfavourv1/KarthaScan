// lib/core/models/export_job.dart
//
// Immutable model per Section 16 (file #11): id, format, status, filePath,
// createdAt. `format` and `status` are typed enums rather than raw strings
// so export_service.dart / export_dialog.dart (file #30) can't drift into
// an invalid combination silently.
//
// ExportFormat covers exactly the 5 formats listed in file #30's format
// selector: PDF / JPG / PNG / TXT / DOCX. DOCX generation is backed by the
// `archive` package rather than a dedicated docx dependency — see the note
// in pubspec.yaml.
import 'package:flutter/foundation.dart' show immutable;

enum ExportFormat { pdf, jpg, png, txt, docx }

enum ExportStatus { pending, inProgress, completed, failed }

@immutable
class ExportJob {
  const ExportJob({
    required this.id,
    required this.format,
    required this.status,
    required this.filePath,
    required this.createdAt,
    this.errorMessage,
  });

  final String id;
  final ExportFormat format;
  final ExportStatus status;

  /// Populated once [status] is [ExportStatus.completed]; null while
  /// pending/in progress, and typically null (but not required to be) on
  /// failure.
  final String? filePath;

  final DateTime createdAt;

  /// Human-readable failure reason, set when [status] is
  /// [ExportStatus.failed]. Surfaced by export_screen.dart per Section 15's
  /// "every save/delete/share shows explicit success/error feedback" and
  /// Section 14's graceful-degradation requirement — export failures must
  /// explain themselves, not fail silently.
  final String? errorMessage;

  /// Sentinels used by [copyWith] to distinguish "not passed" from
  /// "explicitly set to null" for the two nullable fields — needed so a
  /// retry can clear a stale [errorMessage] or [filePath] rather than
  /// being stuck with whatever the last attempt left behind.
  static const Object _unset = Object();

  ExportJob copyWith({
    String? id,
    ExportFormat? format,
    ExportStatus? status,
    Object? filePath = _unset,
    DateTime? createdAt,
    Object? errorMessage = _unset,
  }) {
    return ExportJob(
      id: id ?? this.id,
      format: format ?? this.format,
      status: status ?? this.status,
      filePath:
          identical(filePath, _unset) ? this.filePath : filePath as String?,
      createdAt: createdAt ?? this.createdAt,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'format': format.name,
      'status': status.name,
      'filePath': filePath,
      'createdAt': createdAt.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }

  factory ExportJob.fromJson(Map<String, dynamic> json) {
    return ExportJob(
      id: json['id'] as String,
      format: ExportFormat.values.byName(json['format'] as String),
      status: ExportStatus.values.byName(json['status'] as String),
      filePath: json['filePath'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      errorMessage: json['errorMessage'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExportJob &&
        other.id == id &&
        other.format == format &&
        other.status == status &&
        other.filePath == filePath &&
        other.createdAt == createdAt &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        id,
        format,
        status,
        filePath,
        createdAt,
        errorMessage,
      );

  @override
  String toString() =>
      'ExportJob(id: $id, format: ${format.name}, status: ${status.name})';
}
