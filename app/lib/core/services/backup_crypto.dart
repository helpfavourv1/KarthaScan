// lib/core/services/backup_crypto.dart
//
// Password lock for backup files.
//
// New backups (format "KSB2"):
//   magic "KSB2" | salt (16) | iv (16) | AES-256-CBC ciphertext | HMAC-SHA256 (32)
// The key comes from the password with PBKDF2-HMAC-SHA256 and a random salt,
// and the HMAC (over everything before it) detects a wrong password or a
// damaged/edited file before any decryption is attempted.
//
// Old backups (no magic): iv (16) | ciphertext, key = SHA-256(password).
// They can still be opened, but are never written any more.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show visibleForTesting;

class BackupDecryptException implements Exception {
  const BackupDecryptException(this.message);
  final String message;
  @override
  String toString() => 'BackupDecryptException: $message';
}

class BackupCrypto {
  const BackupCrypto._();

  static const List<int> _magic = <int>[0x4B, 0x53, 0x42, 0x32]; // "KSB2"
  static const int defaultIterations = 100000;
  static const int _saltLength = 16;
  static const int _ivLength = 16;
  static const int _macLength = 32;

  /// PBKDF2 with HMAC-SHA256 (RFC 8018).
  static Uint8List pbkdf2(String password, List<int> salt, int iterations, int length) {
    final crypto.Hmac hmac = crypto.Hmac(crypto.sha256, utf8.encode(password));
    final int blocks = (length + 31) ~/ 32;
    final BytesBuilder out = BytesBuilder();
    for (int i = 1; i <= blocks; i++) {
      List<int> u = hmac.convert(<int>[
        ...salt,
        (i >> 24) & 0xFF,
        (i >> 16) & 0xFF,
        (i >> 8) & 0xFF,
        i & 0xFF,
      ]).bytes;
      final List<int> t = List<int>.from(u);
      for (int j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (int k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      out.add(t);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  static bool _hasMagic(Uint8List data) {
    if (data.length < _magic.length) return false;
    for (int i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Locks [data] with [password] in the new format.
  static Uint8List encrypt(Uint8List data, String password, {int iterations = defaultIterations}) {
    final Uint8List salt = enc.IV.fromSecureRandom(_saltLength).bytes;
    final Uint8List keys = pbkdf2(password, salt, iterations, 64);
    final enc.Key aesKey = enc.Key(Uint8List.fromList(keys.sublist(0, 32)));
    final List<int> macKey = keys.sublist(32, 64);
    final enc.IV iv = enc.IV.fromSecureRandom(_ivLength);
    final Uint8List cipher = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.cbc))
        .encryptBytes(data, iv: iv)
        .bytes;
    final Uint8List body = Uint8List.fromList(<int>[..._magic, ...salt, ...iv.bytes, ...cipher]);
    final List<int> mac = crypto.Hmac(crypto.sha256, macKey).convert(body).bytes;
    return Uint8List.fromList(<int>[...body, ...mac]);
  }

  /// Unlocks a backup, new or old format. Throws [BackupDecryptException] for a
  /// wrong password or a damaged file.
  static Uint8List decrypt(Uint8List data, String password, {int iterations = defaultIterations}) {
    if (_hasMagic(data)) {
      const int headerLength = 4 + _saltLength + _ivLength;
      if (data.length < headerLength + _macLength + 16) {
        throw const BackupDecryptException('This backup file looks corrupted.');
      }
      final Uint8List salt = data.sublist(4, 4 + _saltLength);
      final Uint8List ivBytes = data.sublist(4 + _saltLength, headerLength);
      final Uint8List body = data.sublist(0, data.length - _macLength);
      final Uint8List mac = data.sublist(data.length - _macLength);
      final Uint8List keys = pbkdf2(password, salt, iterations, 64);
      final List<int> expected =
          crypto.Hmac(crypto.sha256, keys.sublist(32, 64)).convert(body).bytes;
      if (!_constantTimeEquals(mac, expected)) {
        throw const BackupDecryptException('Wrong password, or the backup file is damaged.');
      }
      try {
        final enc.Key aesKey = enc.Key(Uint8List.fromList(keys.sublist(0, 32)));
        final List<int> plain = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.cbc))
            .decryptBytes(enc.Encrypted(body.sublist(headerLength)), iv: enc.IV(ivBytes));
        return Uint8List.fromList(plain);
      } catch (_) {
        throw const BackupDecryptException('This backup file looks corrupted.');
      }
    }
    return _decryptLegacy(data, password);
  }

  static Uint8List _legacyKey(String password) =>
      Uint8List.fromList(crypto.sha256.convert(utf8.encode(password)).bytes);

  static Uint8List _decryptLegacy(Uint8List data, String password) {
    if (data.length <= 16) {
      throw const BackupDecryptException('This backup file looks corrupted.');
    }
    try {
      final enc.Encrypter encrypter =
          enc.Encrypter(enc.AES(enc.Key(_legacyKey(password)), mode: enc.AESMode.cbc));
      final List<int> plain = encrypter.decryptBytes(
        enc.Encrypted(data.sublist(16)),
        iv: enc.IV(data.sublist(0, 16)),
      );
      return Uint8List.fromList(plain);
    } catch (_) {
      throw const BackupDecryptException('Wrong password, or the backup file is damaged.');
    }
  }

  /// The old format. Only here so tests can prove old backups still open.
  @visibleForTesting
  static Uint8List encryptLegacyForTest(Uint8List data, String password) {
    final enc.IV iv = enc.IV.fromSecureRandom(16);
    final enc.Encrypted encrypted =
        enc.Encrypter(enc.AES(enc.Key(_legacyKey(password)), mode: enc.AESMode.cbc))
            .encryptBytes(data, iv: iv);
    return Uint8List.fromList(<int>[...iv.bytes, ...encrypted.bytes]);
  }
}

// Top-level so they can run in a background isolate with `compute`; the key
// stretching takes a moment and must not freeze the screen.
Uint8List backupEncryptJob(Map<String, Object> args) =>
    BackupCrypto.encrypt(args['data']! as Uint8List, args['password']! as String);

Uint8List backupDecryptJob(Map<String, Object> args) =>
    BackupCrypto.decrypt(args['data']! as Uint8List, args['password']! as String);
