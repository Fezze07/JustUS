import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:justus/all_imports.dart';

class AppLanguage {
  final String code;
  final String englishName;
  final String nativeName;
  final String flagEmoji;
  final String aiTranslationHint;

  const AppLanguage({
    required this.code,
    required this.englishName,
    required this.nativeName,
    required this.flagEmoji,
    required this.aiTranslationHint,
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
      aiTranslationHint: 'Italiano naturale, tono caldo e diretto.',
    ),
    AppLanguage(
      code: 'en',
      englishName: 'English',
      nativeName: 'English',
      flagEmoji: '🇬🇧',
      aiTranslationHint: 'Natural English, warm and concise tone.',
    ),
  ];

  static List<Locale> get supportedLocales =>
      supportedLanguages.map((language) => language.locale).toList(growable: false);

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

  static Map<String, String> aiTranslationContext(Locale locale) {
    final language = languageForLocale(locale);

    return {
      'languageCode': language.code,
      'englishName': language.englishName,
      'nativeName': language.nativeName,
      'styleHint': language.aiTranslationHint,
      'arbTemplate': 'lib/core/localization/intl_it.arb',
    };
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
}
