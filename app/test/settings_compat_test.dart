// Settings saved by an older version (with a storagePath) must still load.
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/user_settings.dart';

void main() {
  test('old settings JSON with storagePath still loads', () {
    final UserSettings s = UserSettings.fromJson(<String, dynamic>{'storagePath': '/old/path', 'language': 'en'});
    expect(s.language, 'en');
    expect(s.toJson().containsKey('storagePath'), isFalse);
  });
}
