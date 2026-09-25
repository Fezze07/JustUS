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

  // ── On-dark content ramp ───────────────────────────────────────────────────
  // Replaces the raw Colors.whiteNN literals that were spread over every screen.
  /// Headings, body copy, primary icons.
  static const Color contentPrimary = Colors.white;

  /// Supporting copy next to a title.
  static const Color contentSecondary = Colors.white70;

  /// Captions, timestamps, section headers.
  static const Color contentTertiary = Colors.white54;

  /// Barely-visible supporting copy.
  static const Color contentFaint = Colors.white60;

  /// Disabled / not-yet-available content.
  static const Color contentDisabled = Colors.white38;

  /// Placeholder and hint text.
  static const Color contentPlaceholder = Colors.white30;

  /// Text field hint text.
  static const Color contentHint = Colors.white24;

  // ── Translucent surfaces ───────────────────────────────────────────────────
  /// Borders, dividers, empty-state fills.
  static const Color surfaceOverlay = Colors.white10;

  /// Translucent white fill on top of a colored gradient.
  static const Color surfaceGlass = Color(0x33FFFFFF);

  /// Progress tracks, sheet drag handles.
  static const Color surfaceTrack = Colors.white24;

  /// Lighter surface than `cardDark` (chips, banners, empty states).
  static const Color surfaceElevated = Color(0xFF1E0B36);

  /// Backdrop of the full-screen media viewer.
  static const Color viewerBackdrop = Color(0xFF12091D);

  /// Secondary gradient stop next to `primary`.
  static const Color gradientAccent = Color(0xFFA855F7);

  // ── Shadows & scrims ───────────────────────────────────────────────────────
  /// Default card elevation.
  static const Color shadow = Color(0x33000000);

  /// Small elevation: emoji tiles, grid overlays.
  static const Color shadowSoft = Colors.black26;

  /// Elevated chrome (bottom nav, upload banner, notification bell).
  static const Color shadowStrong = Color(0x4D000000);

  /// Toast elevation.
  static const Color shadowToast = Color(0x73000000);

  /// Darkening layer over media tiles.
  static const Color scrim = Colors.black54;

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color danger = Colors.red;
  static final Color dangerSurface = Colors.red.shade800;
  static const Color success = Colors.green;
  static const Color warning = Colors.orange;
  static const Color info = Colors.blue;
  static final Color infoSurface = Colors.blue[100]!;
  static const Color accentPurple = Colors.purple;

  // ── Neutrals for media placeholders and debug output ───────────────────────
  static final Color neutralMuted = Colors.grey[300]!;
  static final Color neutralStrong = Colors.grey[800]!;
  static const Color neutralText = Colors.grey;

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
