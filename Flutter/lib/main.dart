import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) {
    return;
  }

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
  await NotificationService().initLocalNotifications(isBackground: true);
  await NotificationService().showRemoteMessage(message, isBackground: true);
}

void main() {
  unawaited(runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        ErrorHandler.handleGlobal(
            details.exception, details.stack ?? StackTrace.current);
      };

      await dotenv.load();

      await StorageService.init();

      await SupabaseService.initialize();

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

      final notificationService = NotificationService();
      await notificationService.init();

      final languageProvider = LanguageProvider();
      await languageProvider.loadSavedLocale();

      runApp(JustUsApp(languageProvider: languageProvider));
    },
    (error, stackTrace) => ErrorHandler.handleGlobal(error, stackTrace),
  ));
}

class JustUsApp extends StatelessWidget {
  final LanguageProvider languageProvider;

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
        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        // Feature states
        ChangeNotifierProvider(create: (_) => HomepageState()),
        ChangeNotifierProvider(create: (_) => MoodState()),
        ChangeNotifierProvider(create: (_) => BucketState()),
        ChangeNotifierProvider(create: (_) => GameState()),
        ChangeNotifierProvider(create: (_) => DriveState()),
        ChangeNotifierProvider(create: (_) => ProfileState()),
      ],
      child: RealtimeSyncScope(
        child: Selector2<LanguageProvider, ThemeProvider, _AppThemeData>(
          selector: (_, lp, tp) => _AppThemeData(
            locale: lp.locale,
            themeMode: tp.mode,
          ),
          builder: (context, data, _) {
            return MaterialApp(
              onGenerateTitle: (context) => context.loc.appTitle,
              debugShowCheckedModeBanner: false,
              navigatorKey: ErrorHandler.navigatorKey,
              themeMode: data.themeMode,
              locale: data.locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              localeResolutionCallback: LanguageHelper.localeResolutionCallback,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
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

class _AppThemeData {
  final Locale locale;
  final ThemeMode themeMode;

  const _AppThemeData({
    required this.locale,
    required this.themeMode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AppThemeData &&
          locale == other.locale &&
          themeMode == other.themeMode;

  @override
  int get hashCode => locale.hashCode ^ themeMode.hashCode;
}
