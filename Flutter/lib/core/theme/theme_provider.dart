import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String storageKey = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  bool _isLoaded = false;

  ThemeMode get mode => _mode;
  bool get isLoaded => _isLoaded;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> loadSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = _parse(prefs.getString(storageKey));
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_mode == mode) return;

    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, mode.name);
  }

  Future<void> toggle() {
    return setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static ThemeMode _parse(String? raw) {
    for (final mode in ThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return ThemeMode.dark;
  }
}
