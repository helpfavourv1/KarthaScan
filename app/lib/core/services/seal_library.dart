import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/seal_design.dart';

class SavedSeal {
  const SavedSeal({required this.id, required this.design});
  final String id;
  final SealDesign design;
}

/// Seals the person saved for reuse (a company stamp, a notary seal) so they do
/// not have to be rebuilt for every document. Kept on the device.
class SealLibrary {
  static const String _key = 'saved_seals_v1';

  /// Oldest are dropped beyond this many, so storage stays small.
  static const int maxSeals = 12;

  Future<List<SavedSeal>> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return <SavedSeal>[];
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final List<SavedSeal> out = <SavedSeal>[];
      for (final dynamic e in list) {
        try {
          final Map<String, dynamic> m = e as Map<String, dynamic>;
          out.add(SavedSeal(id: m['id'] as String, design: SealDesign.fromJson(m['design'] as Map<String, dynamic>)));
        } catch (_) {
          // One damaged entry must not hide the others.
        }
      }
      return out;
    } catch (_) {
      return <SavedSeal>[];
    }
  }

  Future<void> _write(List<SavedSeal> seals) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(<Map<String, dynamic>>[for (final SavedSeal s in seals) <String, dynamic>{'id': s.id, 'design': s.design.toJson()}]),
    );
  }

  /// Saves a design. An identical one already saved is moved to the front instead
  /// of being added again. Returns the new list, newest first.
  Future<List<SavedSeal>> save(SealDesign design) async {
    final List<SavedSeal> current = await load();
    current.removeWhere((SavedSeal s) => s.design.sameLookAs(design));
    current.insert(0, SavedSeal(id: 'seal_${DateTime.now().microsecondsSinceEpoch}', design: design));
    while (current.length > maxSeals) {
      current.removeLast();
    }
    await _write(current);
    return current;
  }

  Future<List<SavedSeal>> delete(String id) async {
    final List<SavedSeal> current = await load();
    current.removeWhere((SavedSeal s) => s.id == id);
    await _write(current);
    return current;
  }
}
