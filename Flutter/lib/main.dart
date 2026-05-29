import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

void main() {
  unawaited(runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Global Flutter framework error handler
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        ErrorHandler.handleGlobal(details.exception, details.stack ?? StackTrace.current);
      };

      // Load environment variables
      await dotenv.load();

      // Initialize Supabase
      await SupabaseService.initialize();

      // Initialize Firebase (only for supported platforms: Android, iOS, Web)
      // Windows is NOT supported by firebase_core default initialization without options.
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          kIsWeb) {
        try {
          await Firebase.initializeApp();
        } catch (e) {
          debugPrint("Firebase init error: $e");
        }
      }

      // Initialize notifications
      final notificationService = NotificationService();
      await notificationService.init();

      runApp(const JustUsApp());
    },
    (error, stackTrace) => ErrorHandler.handleGlobal(error, stackTrace),
  ));
}

CardThemeData _cardTheme(Brightness brightness) => CardThemeData(
      elevation: 0,
      color: brightness == Brightness.light ? AppColors.cardLight : AppColors.cardDark,
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
  const JustUsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
      child: MaterialApp(
        title: 'JustUs',
        debugShowCheckedModeBanner: false,
        navigatorKey: ErrorHandler.navigatorKey,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
          ),
          textTheme: GoogleFonts.plusJakartaSansTextTheme(),
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.dark,
            primary: AppColors.primary,
            surface: AppColors.backgroundDark,
          ),
          textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
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
          '/homepage': (context) => const HomepageScreen(),
          '/partner': (context) => const PartnerScreen(),
          '/change-password': (context) => const ChangePasswordScreen(),
        },
      ),
    );
  }
}
