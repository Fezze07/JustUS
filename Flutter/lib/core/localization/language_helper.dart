import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

class AppLanguage {
  final String code;
  final String englishName;
  final String nativeName;
  final String flagEmoji;

  const AppLanguage({
    required this.code,
    required this.englishName,
    required this.nativeName,
    required this.flagEmoji,
  });

  Locale get locale => Locale(code);
}

abstract final class LanguageHelper {
  static const String storageKey = 'app_language_code';
  static const Locale fallbackLocale = Locale('it');

  static const List<AppLanguage> supportedLanguages = [
    AppLanguage(
      code: 'it',
      englishName: 'Italian',
      nativeName: 'Italiano',
      flagEmoji: '🇮🇹',
    ),
    AppLanguage(
      code: 'en',
      englishName: 'English',
      nativeName: 'English',
      flagEmoji: '🇬🇧',
    ),
  ];

  static List<Locale> get supportedLocales => supportedLanguages
      .map((language) => language.locale)
      .toList(growable: false);

  static Locale resolveLocale(Locale? locale) {
    if (locale == null) return fallbackLocale;

    return supportedLocales.firstWhere(
      (supportedLocale) => supportedLocale.languageCode == locale.languageCode,
      orElse: () => fallbackLocale,
    );
  }

  static Locale resolveLanguageCode(String? languageCode) {
    if (languageCode == null || languageCode.trim().isEmpty) {
      return fallbackLocale;
    }

    return resolveLocale(Locale(languageCode.trim().toLowerCase()));
  }

  /// Ordered language codes to try when a catalog is only partly translated:
  /// the requested [languageCode] first, then [fallbackLocale]. A missing
  /// translation degrades to the app default instead of empty text.
  static List<String> localeChain(String languageCode) {
    final requested = resolveLanguageCode(languageCode).languageCode;

    return requested == fallbackLocale.languageCode
        ? [requested]
        : [requested, fallbackLocale.languageCode];
  }

  static Locale localeResolutionCallback(
    Locale? locale,
    Iterable<Locale> supportedLocales,
  ) {
    if (locale == null) return fallbackLocale;

    for (final supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return supportedLocale;
      }
    }

    return fallbackLocale;
  }

  static AppLanguage languageForLocale(Locale locale) {
    final resolvedLocale = resolveLocale(locale);

    return supportedLanguages.firstWhere(
      (language) => language.code == resolvedLocale.languageCode,
      orElse: () => supportedLanguages.first,
    );
  }

  static bool isSupported(String languageCode) {
    return supportedLanguages.any((language) => language.code == languageCode);
  }

  static AppLocalizations? _appLoc;

  static AppLocalizations get appLoc {
    _appLoc ??= lookupAppLocalizations(fallbackLocale);
    return _appLoc!;
  }

  static bool get isLocaleInitialized => _appLoc != null;

  static void setAppLocale(Locale locale) {
    _appLoc = lookupAppLocalizations(resolveLocale(locale));
  }

  /// Initializes [appLoc] from the device system locale.
  /// Safe to call from background isolates (after
  /// [WidgetsFlutterBinding.ensureInitialized]).
  /// Always refreshes so runtime locale changes are picked up.
  static void initFromSystemLocale() {
    final locale = ui.PlatformDispatcher.instance.locale;
    setAppLocale(resolveLocale(locale));
  }

  /// Returns the current app locale language code (e.g. `'it'`, `'en'`).
  ///
  /// Resolution order:
  /// 1. Already-initialised [appLoc] (in-memory, zero I/O).
  /// 2. Value persisted in [SharedPreferences] under [storageKey].
  /// 3. System locale via [initFromSystemLocale] as a last resort.
  static Future<String> currentLocaleCode() async {
    if (isLocaleInitialized) return appLoc.localeName;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      if (saved != null && saved.isNotEmpty) {
        setAppLocale(Locale(saved));
      } else {
        initFromSystemLocale();
      }
    } catch (_) {
      initFromSystemLocale();
    }
    return appLoc.localeName;
  }
}
