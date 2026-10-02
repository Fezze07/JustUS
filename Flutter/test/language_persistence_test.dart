import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 4.6 / F-SC4: logout must not wipe the persisted
/// language preference (device-level, not account-level).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  Future<void> seedAccountAndLanguage() async {
    StorageService.setActivePartnership(7);
    await StorageService.saveMood('me', 'happy');
    await CacheService.saveCheckpoint(
        CacheService.kMoods, '2026-02-01T00:00:00.000Z');

    final p = await prefs();
    await p.setString(LanguageHelper.storageKey, 'en');
  }

  test('F-SC4: clearAll wipes account data but keeps app_language_code',
      () async {
    await seedAccountAndLanguage();

    await StorageService.clearAll();

    final p = await prefs();
    expect(p.getString(LanguageHelper.storageKey), 'en');
    expect(p.getString('mood_me:7'), isNull);
    expect(p.getString('chk_moods:7'), isNull);
  });

  test('F-SC4: clearAll with no saved language leaves no app_language_code',
      () async {
    await seedAccountAndLanguage();
    final p = await prefs();
    await p.remove(LanguageHelper.storageKey);

    await StorageService.clearAll();

    expect(p.getString(LanguageHelper.storageKey), isNull);
  });
}
