import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 6.4: the theme preference is device-level state, so it
/// must survive a process restart (persisted by `ThemeProvider`) and a
/// logout/wipe (`StorageService.clearAll`, F-SC4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('defaults to dark before any preference is stored', () async {
    final provider = ThemeProvider();
    await provider.loadSavedMode();

    expect(provider.mode, ThemeMode.dark);
    expect(provider.isDark, isTrue);
    expect(provider.isLoaded, isTrue);
  });

  test('a stored mode is restored by a fresh provider (app restart)', () async {
    final first = ThemeProvider();
    await first.loadSavedMode();
    await first.setThemeMode(ThemeMode.light);
    expect(first.mode, ThemeMode.light);

    final restored = ThemeProvider();
    await restored.loadSavedMode();

    expect(restored.mode, ThemeMode.light);
    expect(restored.isDark, isFalse);
    expect((await prefs()).getString(ThemeProvider.storageKey), 'light');
  });

  test('toggle flips the mode and persists it', () async {
    final provider = ThemeProvider();
    await provider.loadSavedMode();

    await provider.toggle();
    expect(provider.mode, ThemeMode.light);

    await provider.toggle();
    expect(provider.mode, ThemeMode.dark);
    expect((await prefs()).getString(ThemeProvider.storageKey), 'dark');
  });

  test('setThemeMode is a no-op when the mode is unchanged', () async {
    final provider = ThemeProvider();
    await provider.loadSavedMode();

    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setThemeMode(ThemeMode.dark);

    expect(notifications, 0);
    expect((await prefs()).getString(ThemeProvider.storageKey), isNull);
  });

  test('an unrecognized stored mode falls back to dark', () async {
    final p = await prefs();
    await p.setString(ThemeProvider.storageKey, 'sepia');

    final provider = ThemeProvider();
    await provider.loadSavedMode();

    expect(provider.mode, ThemeMode.dark);
  });

  test('clearAll wipes account data but keeps the theme preference', () async {
    StorageService.setActivePartnership(7);
    await StorageService.saveMood('me', 'happy');
    await StorageService.saveTotalMissYou(3);

    final p = await prefs();
    await p.setString(LanguageHelper.storageKey, 'en');

    final provider = ThemeProvider();
    await provider.loadSavedMode();
    await provider.setThemeMode(ThemeMode.light);

    await StorageService.clearAll();

    expect(p.getString(ThemeProvider.storageKey), 'light');
    expect(p.getString(LanguageHelper.storageKey), 'en');
    expect(p.getString('mood_me:7'), isNull);
    expect(await StorageService.getTotalMissYou(), isNull);

    final restored = ThemeProvider();
    await restored.loadSavedMode();
    expect(restored.mode, ThemeMode.light);
  });

  test('clearAll with no saved theme leaves no theme key', () async {
    final provider = ThemeProvider();
    await provider.loadSavedMode();

    await StorageService.clearAll();

    expect((await prefs()).getString(ThemeProvider.storageKey), isNull);
  });
}
