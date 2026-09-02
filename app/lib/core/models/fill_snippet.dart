import 'package:flutter/foundation.dart' show immutable;

@immutable
class FillSnippet {
  const FillSnippet({required this.id, required this.label, required this.text});
  final String id;
  final String label;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'text': text};

  factory FillSnippet.fromJson(Map<String, dynamic> json) {
    return FillSnippet(
      id: json['id'] as String,
      label: json['label'] as String,
      text: json['text'] as String,
    );
  }
}
