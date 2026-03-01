// =============================================================================
// JustUs - Main entry point
// Flutter cross-platform app for couples
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'state/auth_state.dart';
import 'state/login_state.dart';
import 'state/register_state.dart';
import 'state/homepage_state.dart';
import 'state/mood_state.dart';
import 'state/bucket_state.dart';
import 'state/game_state.dart';
import 'state/drive_state.dart';
import 'state/partner_state.dart';
import 'state/profile_state.dart';
import 'services/notification_service.dart';
import 'constants/app_colors.dart';

import 'screens/splash_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb and defaultTargetPlatform

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
}

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
        ChangeNotifierProvider(create: (_) => LoginState()),
        ChangeNotifierProvider(create: (_) => RegisterState()),
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
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.light,
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
          cardTheme: CardThemeData(
            elevation: 0,
            color: AppColors.cardLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
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
          ),
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
          cardTheme: CardThemeData(
            elevation: 0,
            color: AppColors.cardDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: AppColors.borderDark,
                width: 1,
              ),
            ),
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
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
          ),
        ),
        themeMode: ThemeMode.system,
        home: const SplashScreen(),
      ),
    );
  }
}
