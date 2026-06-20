import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) {
    // Already shown natively by the OS — nothing to do.
    return;
  }

  // Data-only message: we must show it manually even when closed.
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      kIsWeb) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {}
  }

  LanguageHelper.initFromSystemLocale();
  await NotificationService().initLocalNotifications();
  await NotificationService().showRemoteMessage(message);
}

void main() {
  unawaited(runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Global Flutter framework error handler
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        ErrorHandler.handleGlobal(
            details.exception, details.stack ?? StackTrace.current);
      };

      // Load environment variables
      await dotenv.load();

      // Initialize local storage (SharedPreferences)
      await StorageService.init();

      // Initialize Supabase
      await SupabaseService.initialize();

      // Initialize Firebase (only for supported platforms: Android, iOS, Web)
      // Windows is NOT supported by firebase_core default initialization without options.
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          kIsWeb) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          FirebaseMessaging.onBackgroundMessage(
              _firebaseMessagingBackgroundHandler);
        } catch (e) {
          AnsiLogger.error('Firebase init error: $e', tag: 'Firebase');
        }
      }

      // Initialize notifications
      final notificationService = NotificationService();
      await notificationService.init();

      final languageProvider = LanguageProvider();
      await languageProvider.loadSavedLocale();

      runApp(JustUsApp(languageProvider: languageProvider));
    },
    (error, stackTrace) => ErrorHandler.handleGlobal(error, stackTrace),
  ));
}

CardThemeData _cardTheme(Brightness brightness) => CardThemeData(
      elevation: 0,
      color: brightness == Brightness.light
          ? AppColors.cardLight
          : AppColors.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: brightness == Brightness.dark
            ? BorderSide(color: AppColors.borderDark)
            : BorderSide.none,
      ),
      margin: EdgeInsets.zero,
    );

InputDecorationTheme _inputDecorationTheme() => InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
    );

FilledButtonThemeData _filledButtonTheme() => FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

class JustUsApp extends StatelessWidget {
  final LanguageProvider languageProvider;

  static final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
  );

  static final ColorScheme _darkColorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
    primary: AppColors.primary,
    surface: AppColors.backgroundDark,
  );

  static final TextTheme _textTheme = GoogleFonts.plusJakartaSansTextTheme();
  static final TextTheme _darkTextTheme =
      GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme);

  const JustUsApp({
    super.key,
    required this.languageProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: languageProvider),

        // Global state
        ChangeNotifierProvider(create: (_) => AuthState()),
        ChangeNotifierProvider(create: (_) => PartnerState()),

        // Feature states
        ChangeNotifierProvider(create: (_) => HomepageState()),
        ChangeNotifierProvider(create: (_) => MoodState()),
        ChangeNotifierProvider(create: (_) => BucketState()),
        ChangeNotifierProvider(create: (_) => GameState()),
        ChangeNotifierProvider(create: (_) => DriveState()),
        ChangeNotifierProvider(create: (_) => ProfileState()),
      ],
      child: RealtimeSyncScope(
        child: Selector<LanguageProvider, Locale>(
          selector: (_, lp) => lp.locale,
          builder: (context, locale, _) {
            return MaterialApp(
              onGenerateTitle: (context) => context.loc.appTitle,
              debugShowCheckedModeBanner: false,
              navigatorKey: ErrorHandler.navigatorKey,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              localeResolutionCallback: LanguageHelper.localeResolutionCallback,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: _lightColorScheme,
                textTheme: _textTheme,
                scaffoldBackgroundColor: AppColors.backgroundLight,
                appBarTheme: AppBarTheme(
                  centerTitle: true,
                  backgroundColor: AppColors.backgroundLight,
                  elevation: 0,
                  titleTextStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textLight,
                  ),
                ),
                cardTheme: _cardTheme(Brightness.light),
                inputDecorationTheme: _inputDecorationTheme(),
                filledButtonTheme: _filledButtonTheme(),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorScheme: _darkColorScheme,
                textTheme: _darkTextTheme,
                scaffoldBackgroundColor: AppColors.backgroundDark,
                appBarTheme: AppBarTheme(
                  centerTitle: true,
                  backgroundColor: AppColors.backgroundDark,
                  elevation: 0,
                  titleTextStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                cardTheme: _cardTheme(Brightness.dark),
                inputDecorationTheme: _inputDecorationTheme(),
                filledButtonTheme: _filledButtonTheme(),
              ),
              home: const SplashScreen(),
              routes: {
                '/login': (context) => const LoginScreen(),
                '/register': (context) => const RegisterScreen(),
                '/homepage': (context) => MainShell(key: MainShell.shellKey),
                '/partner': (context) => const PartnerScreen(),
                '/localization': (context) => const LocalizationScreen(),
                '/change-password': (context) => const ChangePasswordScreen(),
              },
            );
          },
        ),
      ),
    );
  }
}
