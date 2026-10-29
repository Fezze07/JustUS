import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
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

      FirebaseAnalytics? analytics;
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          kIsWeb) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          FirebaseMessaging.onBackgroundMessage(
              _firebaseMessagingBackgroundHandler);
          analytics = FirebaseAnalytics.instance;
        } catch (e) {
          AnsiLogger.error('Firebase init error: $e', tag: 'Firebase');
        }
      }

      final notificationService = NotificationService();
      await notificationService.init();

      final languageProvider = LanguageProvider();
      await languageProvider.loadSavedLocale();

      final themeProvider = ThemeProvider();
      await themeProvider.loadSavedMode();

      runApp(JustUsApp(
        languageProvider: languageProvider,
        themeProvider: themeProvider,
        analytics: analytics,
      ));
    },
    (error, stackTrace) => ErrorHandler.handleGlobal(error, stackTrace),
  ));
}

Route<dynamic>? generateAppRoute(RouteSettings settings) {
  final routes = <String, WidgetBuilder>{
    AppRoutes.splash: (_) => const SplashScreen(),
    AppRoutes.login: (_) => const LoginScreen(),
    AppRoutes.register: (_) => const RegisterScreen(),
    AppRoutes.resetPassword: (_) => const ResetPasswordScreen(),
    AppRoutes.changePassword: (_) => const ChangePasswordScreen(),
    AppRoutes.localization: (_) => const LocalizationScreen(),
    AppRoutes.partner: (_) => const PartnerScreen(),
    AppRoutes.mainShell: (_) => const MainShell(),
  };

  WidgetBuilder? builder = routes[settings.name];
  if (settings.name == AppRoutes.driveItem) {
    final id = settings.arguments is int
        ? settings.arguments as int
        : int.tryParse(settings.arguments?.toString() ?? '');
    if (id != null) builder = (_) => DriveItemScreen(itemId: id);
  }

  if (builder == null) return null;

  return MaterialPageRoute(
    builder: builder,
    settings: settings,
  );
}

class JustUsApp extends StatelessWidget {
  final LanguageProvider languageProvider;
  final ThemeProvider themeProvider;
  final FirebaseAnalytics? analytics;

  const JustUsApp({
    super.key,
    required this.languageProvider,
    required this.themeProvider,
    this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: languageProvider),
        ChangeNotifierProvider.value(value: themeProvider),

        // Global state
        ChangeNotifierProvider(create: (_) => AuthState()),
        ChangeNotifierProvider(create: (_) => PartnerState()),

        // Feature states
        ChangeNotifierProvider(create: (_) => HomepageState()),
        ChangeNotifierProvider(create: (_) => MoodState()),
        ChangeNotifierProvider(create: (_) => BucketState()),
        ChangeNotifierProvider(
            create: (_) => GameState(languageProvider: languageProvider)),
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
              navigatorObservers: [
                if (analytics != null)
                  FirebaseAnalyticsObserver(analytics: analytics!),
              ],
              themeMode: data.themeMode,
              locale: data.locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              localeResolutionCallback: LanguageHelper.localeResolutionCallback,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              builder: (context, child) => AuthMessageHost(
                child: child ?? const SizedBox.shrink(),
              ),
              home: const SplashScreen(),
              onGenerateRoute: generateAppRoute,
            );
          },
        ),
      ),
    );
  }
}

/// Global listener for [AuthState] messages.
///
/// `AuthState` is shared by login/register/change-password/reset-password and
/// the invite dialogs, so no single screen owns its feedback. Mounted above the
/// Navigator, this host shows each message once via the root overlay, so the
/// snackbar survives a `pop` or a `pushReplacement` that disposes the screen
/// that triggered the action.
class AuthMessageHost extends StatefulWidget {
  final Widget child;

  const AuthMessageHost({super.key, required this.child});

  @override
  State<AuthMessageHost> createState() => AuthMessageHostState();
}

class AuthMessageHostState extends State<AuthMessageHost>
    with StateMessageListener<AuthState, AuthMessageHost> {
  @override
  AuthState get messageSource => context.read<AuthState>();

  @override
  Widget build(BuildContext context) => widget.child;
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
