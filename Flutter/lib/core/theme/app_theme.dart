import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_dimens.dart';
import 'app_palette.dart';
import 'app_radius.dart';

/// Shared button geometry and disabled palette.
///
/// `AppTheme` feeds this into `FilledButtonThemeData`, `VPButton` only adds a
/// background override, and outlined variants reuse [shape]/[padding]/
/// [minimumSize] — so every button variant in the app shares one look.
///
/// Foreground colors are resolved from the [AppPalette] instead of being
/// constants: a filled violet button needs white text in both themes, which is
/// why they are not simply "the primary text color".
class AppButtonStyle {
  AppButtonStyle._();

  static OutlinedBorder get shape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));

  static EdgeInsetsGeometry get padding =>
      const EdgeInsets.symmetric(vertical: AppSpacing.md);

  static Size get minimumSize => const Size(0, AppDims.buttonMinHeight);

  /// Foreground of a filled button sitting on the brand violet.
  static Color foreground(AppPalette palette) => palette.onPrimary;

  static Color disabledForeground(AppPalette palette) =>
      palette.contentSecondary;

  /// `backgroundColor` at 60% — the disabled look of every primary action.
  static Color disabledBackground(Color background) =>
      background.withValues(alpha: 0.6);
}

class AppTheme {
  AppTheme._();

  // ── Theme presets ──────────────────────────────────────────────────
  static ThemeData get dark => _build(AppPalette.dark);

  static ThemeData get light => _build(AppPalette.light);

  static ThemeData _build(AppPalette palette) {
    final brightness = palette.brightness;
    final colorScheme = _colorScheme(palette);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(
      bodyColor: palette.contentPrimary,
      displayColor: palette.contentPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.canvas,
      extensions: <ThemeExtension<dynamic>>[palette],

      // ── Chrome ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.contentPrimary,
        elevation: 0,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: palette.primaryVariant,
        ),
        iconTheme: IconThemeData(color: palette.contentSecondary),
      ),
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: AppDims.hairline,
        space: AppDims.hairline,
      ),
      iconTheme: IconThemeData(color: palette.contentSecondary),
      listTileTheme: ListTileThemeData(
        iconColor: palette.contentSecondary,
        textColor: palette.contentPrimary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: palette.border),
        ),
        textStyle: GoogleFonts.plusJakartaSans(color: palette.contentPrimary),
      ),

      // ── Containers ──────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: palette.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: palette.contentPrimary,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: palette.contentSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surface,
        modalBarrierColor: palette.scrim,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: palette.track,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceElevated,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: palette.contentPrimary),
        actionTextColor: palette.primaryVariant,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      // ── Inputs ──────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceSunken,
        hintStyle: GoogleFonts.plusJakartaSans(color: palette.contentHint),
        labelStyle: GoogleFonts.plusJakartaSans(color: palette.contentSecondary),
        prefixIconColor: palette.contentDisabled,
        suffixIconColor: palette.contentDisabled,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.danger, width: 2),
        ),
      ),

      // ── Buttons ─────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: AppButtonStyle.foreground(palette),
          disabledBackgroundColor:
              AppButtonStyle.disabledBackground(palette.primary),
          disabledForegroundColor:
              AppButtonStyle.disabledForeground(palette),
          padding: AppButtonStyle.padding,
          minimumSize: AppButtonStyle.minimumSize,
          shape: AppButtonStyle.shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: AppButtonStyle.foreground(palette),
          disabledBackgroundColor:
              AppButtonStyle.disabledBackground(palette.primary),
          disabledForegroundColor:
              AppButtonStyle.disabledForeground(palette),
          elevation: 0,
          padding: AppButtonStyle.padding,
          minimumSize: AppButtonStyle.minimumSize,
          shape: AppButtonStyle.shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primaryVariant,
          side: BorderSide(color: palette.border),
          padding: AppButtonStyle.padding,
          minimumSize: AppButtonStyle.minimumSize,
          shape: AppButtonStyle.shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.primaryVariant),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: AppButtonStyle.foreground(palette),
        elevation: 0,
      ),

      // ── Selection & progress ────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceElevated,
        selectedColor: palette.primary.withValues(alpha: 0.16),
        labelStyle: GoogleFonts.plusJakartaSans(color: palette.contentPrimary),
        secondaryLabelStyle:
            GoogleFonts.plusJakartaSans(color: palette.primaryVariant),
        checkmarkColor: palette.primary,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.onPrimary
              : palette.contentSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.track,
        ),
        trackOutlineColor: WidgetStatePropertyAll(palette.border),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.track,
        circularTrackColor: palette.track,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.primary.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.primaryVariant
                : palette.contentSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: states.contains(WidgetState.selected)
                ? palette.primaryVariant
                : palette.contentSecondary,
          ),
        ),
      ),
    );
  }

  /// M3 roles are overridden instead of relying on the generated tonal palette:
  /// the brand violet is fixed by design, and the surface container ramp has to
  /// stay on the Violet-Punk hue ladder rather than Material's neutral grey.
  static ColorScheme _colorScheme(AppPalette palette) {
    final isDark = palette.isDark;
    return ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: palette.brightness,
    ).copyWith(
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      surface: palette.surface,
      onSurface: palette.contentPrimary,
      onSurfaceVariant: palette.contentSecondary,
      surfaceContainerLowest:
          isDark ? const Color(0xFF0F0819) : const Color(0xFFFFFFFF),
      surfaceContainerLow: isDark ? palette.canvas : const Color(0xFFFBF9FC),
      surfaceContainer:
          isDark ? const Color(0xFF1F1233) : const Color(0xFFF5F1F9),
      surfaceContainerHigh:
          isDark ? const Color(0xFF2A1A42) : const Color(0xFFEFEAF4),
      surfaceContainerHighest:
          isDark ? const Color(0xFF35204F) : const Color(0xFFE9E3EF),
      outline: palette.homeOutline,
      outlineVariant: palette.border,
      error: palette.danger,
      onError: palette.onDanger,
      errorContainer: palette.dangerSurface,
      onErrorContainer: palette.onDanger,
    );
  }
}
