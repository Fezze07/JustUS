import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 10.1 / F-SC1: `StorageService.clearAll()` must
/// preserve `_keyDeviceFingerprint` across logout (it binds the device, not
/// the account), so a logout/login cycle keeps the same fingerprint and the
/// backend strike/binding keys stay stable. Only the in-memory
/// `_cachedDeviceFingerprint` is cleared, which a fresh read re-populates from
/// the preserved value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    ApiService.clearHeadersCache();
  });

  test('clearAll preserves the device fingerprint across a logout/login cycle',
      () async {
    final before = await StorageService.getOrCreateDeviceFingerprint();

    await StorageService.saveUserId(42);
    await StorageService.saveAccessToken('token');
    await StorageService.saveRequestBindingSecret('secret');

    await StorageService.clearAll();
    ApiService.clearHeadersCache();

    final after = await StorageService.getOrCreateDeviceFingerprint();
    expect(after, before);
  });

  test(
      'clearAll still wipes the session-bound secure storage values '
      '(user id, tokens, binding secret)', () async {
    await StorageService.saveUserId(42);
    await StorageService.saveAccessToken('token');
    await StorageService.saveRefreshToken('refresh');
    await StorageService.saveRequestBindingSecret('secret');
    final fingerprint = await StorageService.getOrCreateDeviceFingerprint();

    await StorageService.clearAll();

    expect(await StorageService.getUserId(), isNull);
    expect(await StorageService.getAccessToken(), isNull);
    expect(await StorageService.getRefreshToken(), isNull);
    expect(await StorageService.getRequestBindingSecret(), isNull);
    expect(await StorageService.getOrCreateDeviceFingerprint(), fingerprint);
  });
}