import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// One saved signature: its picture and the file it lives in.
class SavedSignature {
  const SavedSignature(this.id, this.bytes);
  final String id;
  final Uint8List bytes;
}

/// Keeps up to [maxSaved] signatures in a folder, newest first, so a person who
/// signs as themselves, with initials, or for a company can pick the right one.
class SignatureLibrary {
  SignatureLibrary(this.dir);

  static const int maxSaved = 6;
  final Directory dir;

  static final RegExp _name = RegExp(r'^sig_\d+\.png$');

  Future<List<File>> _files() async {
    if (!await dir.exists()) return <File>[];
    final List<File> files = <File>[];
    await for (final FileSystemEntity e in dir.list()) {
      if (e is File && _name.hasMatch(p.basename(e.path))) files.add(e);
    }
    // Names carry a microsecond clock, so name order is age order.
    files.sort((File a, File b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  Future<List<SavedSignature>> list() async {
    final List<SavedSignature> out = <SavedSignature>[];
    for (final File f in await _files()) {
      try {
        out.add(SavedSignature(p.basename(f.path), await f.readAsBytes()));
      } catch (_) {
        // An unreadable file is skipped, not fatal.
      }
    }
    return out;
  }

  /// Saves [bytes] as the newest signature. The same picture is not saved twice
  /// (it just moves to the front); the oldest is dropped past [maxSaved].
  Future<void> add(Uint8List bytes) async {
    await dir.create(recursive: true);
    for (final SavedSignature s in await list()) {
      if (_same(s.bytes, bytes)) await remove(s.id);
    }
    final String name = 'sig_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(p.join(dir.path, name)).writeAsBytes(bytes, flush: true);
    final List<File> files = await _files();
    for (int i = maxSaved; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }

  Future<void> remove(String id) async {
    if (!_name.hasMatch(id)) return;
    final File f = File(p.join(dir.path, id));
    if (await f.exists()) await f.delete();
  }

  /// A signature saved by an older version (one file) joins the library once,
  /// the first time the library is empty and has never been filled.
  Future<void> importLegacy(Uint8List? legacy) async {
    if (legacy == null) return;
    final File marker = File(p.join(dir.path, '.legacy_done'));
    if (await marker.exists()) return;
    await dir.create(recursive: true);
    await marker.writeAsString('1');
    if ((await _files()).isEmpty) await add(legacy);
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
