// =============================================================================
// App Colors - Based on Stitch JustUS Design
// =============================================================================

import 'package:flutter/material.dart';

class AppColors {
  // Primary brand color
  static const Color primary = Color(0xFF7F13EC);
  
  // Accent colors
  static const Color accentAqua = Color(0xFF00D4FF);
  
  // Background colors
  static const Color backgroundLight = Color(0xFFF7F6F8);
  static const Color backgroundDark = Color(0xFF191022);
  static const Color deepViolet = Color(0xFF120526);
  static const Color punkPurple = Color(0xFF2D1652);
  
  // Neon colors
  static const Color neonPurple = Color(0xFFBC13FE);
  static const Color neonBlue = Color(0xFF00F5FF);
  static const Color neonGreen = Color(0xFF00FFD9);
  static const Color neonPink = Color(0xFFFF0080);
  
  static const Color cardDark = Color(0xFF1A0B2E);
  
  // Gradient colors for mood card
  static const Color gradientStart = Color(0xFF7F13EC);
  static const Color gradientEnd = Color(0xFFA65CF0);
  
  // Card colors
  static const Color cardLight = Colors.white;
  
  // Text colors
  static const Color textLight = Color(0xFF140D1B);
  static const Color textDark = Color(0xFFFAF8FC);
  
  // Border colors
  static Color borderLight = Colors.grey[100]!;
  static Color borderDark = Colors.white.withValues(alpha: 0.05);
  
  // Homepage ("Midnight Glass") palette — was the homepage's private `_C` class
  static const Color homeSurface = Color(0xFF151219);
  static const Color homeSurfaceContainer = Color(0xFF211E26);
  static const Color homePrimary = Color(0xFFD4BBFF); // light lavender
  static const Color homePrimaryContainer = Color(0xFFB388FF); // neon purple
  static const Color homeSecondary = Color(0xFFFFB3AE); // soft red/pink
  static const Color homeOnSurface = Color(0xFFE7E0EA);
  static const Color homeOnSurfaceVariant = Color(0xFFCCC3D4);
  static const Color homeOutline = Color(0xFF958E9D);
  static const Color homeOutlineVariant = Color(0xFF4A4452);
  static const Color homeGlass = Color(0x661E1E1E); // glass card fill
  static const Color homeBlob = Color(0xFF46128D); // atmospheric blob accent
}
