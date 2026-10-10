import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/backup_crypto.dart';

String _hex(List<int> b) => b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final Uint8List payload = Uint8List.fromList(utf8.encode('zip bytes ' * 50));

  test('PBKDF2-HMAC-SHA256 matches the RFC test vectors', () {
    expect(_hex(BackupCrypto.pbkdf2('password', utf8.encode('salt'), 1, 32)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(_hex(BackupCrypto.pbkdf2('password', utf8.encode('salt'), 2, 32)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
  });

  test('new format round-trips and starts with the KSB2 marker', () {
    final Uint8List locked = BackupCrypto.encrypt(payload, 'hunter2', iterations: 10);
    expect(utf8.decode(locked.sublist(0, 4)), 'KSB2');
    expect(BackupCrypto.decrypt(locked, 'hunter2', iterations: 10), payload);
  });

  test('two backups of the same data differ (random salt and iv)', () {
    final Uint8List a = BackupCrypto.encrypt(payload, 'pw', iterations: 10);
    final Uint8List b = BackupCrypto.encrypt(payload, 'pw', iterations: 10);
    expect(a, isNot(b));
  });

  test('wrong password is rejected', () {
    final Uint8List locked = BackupCrypto.encrypt(payload, 'right', iterations: 10);
    expect(() => BackupCrypto.decrypt(locked, 'wrong', iterations: 10),
        throwsA(isA<BackupDecryptException>()));
  });

  test('a damaged file is rejected', () {
    final Uint8List locked = BackupCrypto.encrypt(payload, 'pw', iterations: 10);
    locked[locked.length ~/ 2] ^= 0x01;
    expect(() => BackupCrypto.decrypt(locked, 'pw', iterations: 10),
        throwsA(isA<BackupDecryptException>()));
  });

  test('old-format backups still open', () {
    final Uint8List old = BackupCrypto.encryptLegacyForTest(payload, 'oldpw');
    expect(BackupCrypto.decrypt(old, 'oldpw'), payload);
    expect(() => BackupCrypto.decrypt(old, 'nope'), throwsA(isA<BackupDecryptException>()));
  });
}
