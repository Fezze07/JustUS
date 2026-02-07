// =============================================================================
// JustUs - Main entry point
// Flutter cross-platform app for couples
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
            seedColor: Colors.pink,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
            seedColor: Colors.pink,
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
