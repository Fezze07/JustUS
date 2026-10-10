import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

class _NoopAuthRepository extends AuthRepository {
  @override
  Future<void> signOut() async {}
}

final Uint8List _bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    installMockPathProvider();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('logout empties the on-disk R2 media cache', () async {
    await MediaCacheManager().putFile('users/1/a.jpg', _bytes);
    await MediaCacheManager().putFile('users/1/b.jpg', _bytes);

    expect(await MediaCacheManager().getFileFromCache('users/1/a.jpg'),
        isNotNull);
    expect(await MediaCacheManager().getFileFromCache('users/1/b.jpg'),
        isNotNull);

    await AuthState(authRepo: _NoopAuthRepository()).logout();

    expect(await MediaCacheManager().getFileFromCache('users/1/a.jpg'), isNull);
    expect(await MediaCacheManager().getFileFromCache('users/1/b.jpg'), isNull);
  });

  test('logout best-effort cache clearing still completes', () async {
    final auth = AuthState(authRepo: _NoopAuthRepository());

    await auth.logout();

    expect(auth.isLoggedIn, isFalse);
  });
}