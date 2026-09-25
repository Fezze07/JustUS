import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_radius.dart';

/// Shared button geometry and disabled palette.
///
/// `AppTheme` feeds this into `FilledButtonThemeData`, `VPButton` only adds a
/// background override, and outlined variants reuse [shape]/[padding]/
/// [minimumSize] — so every button variant in the app shares one look.
class AppButtonStyle {
  AppButtonStyle._();

  static OutlinedBorder get shape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));

  static EdgeInsetsGeometry get padding =>
      const EdgeInsets.symmetric(vertical: AppSpacing.md);

  static Size get minimumSize => const Size(0, AppDims.buttonMinHeight);

  static const Color foreground = AppColors.contentPrimary;
  static const Color disabledForeground = AppColors.contentSecondary;

  /// `backgroundColor` at 60% — the disabled look of every primary action.
  static Color disabledBackground(Color background) =>
      background.withValues(alpha: 0.6);
}

class AppTheme {
  AppTheme._();

  // ── Theme presets ──────────────────────────────────────────────────
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        scaffoldBg: AppColors.backgroundDark,
        appBarFg: AppColors.primary,
      );

  static ThemeData get light => _build(
        brightness: Brightness.light,
        scaffoldBg: AppColors.backgroundLight,
        appBarFg: AppColors.textLight,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffoldBg,
    required Color appBarFg,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: AppColors.primary,
      surface: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
    );
    final textTheme = isDark
        ? GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme)
        : GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scaffoldBg,
        elevation: 0,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: appBarFg,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: isDark
              ? BorderSide(color: AppColors.borderDark)
              : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppButtonStyle.foreground,
          disabledBackgroundColor:
              AppButtonStyle.disabledBackground(AppColors.primary),
          disabledForegroundColor: AppButtonStyle.disabledForeground,
          padding: AppButtonStyle.padding,
          minimumSize: AppButtonStyle.minimumSize,
          shape: AppButtonStyle.shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.neonBlue),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.cardDark : AppColors.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.contentPrimary : AppColors.textLight,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: isDark ? AppColors.contentSecondary : AppColors.textLight,
        ),
      ),
    );
  }
}
