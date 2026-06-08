import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = LanguageHelper.fallbackLocale;
  bool _isLoaded = false;

  Locale get locale => _locale;
  bool get isLoaded => _isLoaded;
  AppLanguage get currentLanguage => LanguageHelper.languageForLocale(_locale);
  List<AppLanguage> get supportedLanguages => LanguageHelper.supportedLanguages;

  Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguageCode = prefs.getString(LanguageHelper.storageKey);

    _locale = LanguageHelper.resolveLanguageCode(savedLanguageCode);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setLanguageCode(String languageCode) async {
    await setLocale(Locale(languageCode));
  }

  Future<void> setLocale(Locale locale) async {
    final resolvedLocale = LanguageHelper.resolveLocale(locale);

    if (_locale.languageCode == resolvedLocale.languageCode) {
      return;
    }

    _locale = resolvedLocale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        LanguageHelper.storageKey, resolvedLocale.languageCode);
  }
}
