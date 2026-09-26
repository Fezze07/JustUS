import 'package:flutter/material.dart';

/// Brightness-aware semantic colors, registered on [AppTheme.dark] and
/// [AppTheme.light] as a [ThemeExtension].
///
/// Everything the theme must adapt lives here and is read through
/// `context.palette`, so a widget repaints when the user switches theme.
/// `content*` is ink on themed surfaces and `on*` is the foreground on a
/// saturated fill, so a filled violet button keeps white text in both themes
/// while body ink flips to near-black.
///
/// The `brand*` statics are the Violet-Punk identity itself, deliberately
/// identical in light and dark and the source values the two palettes are built
/// from. Prefer a themed token; read a `brand*` member only where the color is
/// the brand rather than a surface or ink — a saturated gradient the user reads
/// white text on, or a neon used as decoration.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.contentPrimary,
    required this.contentSecondary,
    required this.contentTertiary,
    required this.contentFaint,
    required this.contentDisabled,
    required this.contentPlaceholder,
    required this.contentHint,
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.surfaceGroup,
    required this.glass,
    required this.backdrop,
    required this.scrim,
    required this.border,
    required this.divider,
    required this.overlay,
    required this.track,
    required this.primary,
    required this.onPrimary,
    required this.primaryVariant,
    required this.accentAqua,
    required this.accentBlue,
    required this.accentPurple,
    required this.accentPink,
    required this.accentGreen,
    required this.onAccent,
    required this.danger,
    required this.onDanger,
    required this.dangerSurface,
    required this.success,
    required this.warning,
    required this.info,
    required this.infoSurface,
    required this.shadow,
    required this.shadowSoft,
    required this.shadowStrong,
    required this.shadowToast,
    required this.homeSurface,
    required this.homeSurfaceContainer,
    required this.homeOnSurface,
    required this.homeOnSurfaceVariant,
    required this.homeOutline,
    required this.homeOutlineVariant,
    required this.homeGlass,
    required this.homePrimary,
    required this.homePrimaryContainer,
    required this.homeSecondary,
    required this.homeBlob,
    required this.neutralMuted,
    required this.neutralStrong,
    required this.neutralText,
  });

  /// Violet-Punk, dark first. Unchanged from the shipped dark theme.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,    contentPrimary: Color(0xFFFFFFFF),
    contentSecondary: Color(0xB3FFFFFF),
    contentTertiary: Color(0x8AFFFFFF),
    contentFaint: Color(0x99FFFFFF),
    contentDisabled: Color(0x61FFFFFF),
    contentPlaceholder: Color(0x4DFFFFFF),
    contentHint: Color(0x3DFFFFFF),
    canvas: Color(0xFF191022),
    surface: Color(0xFF1A0B2E),
    surfaceElevated: Color(0xFF1E0B36),
    surfaceSunken: Color(0xFF120526),
    surfaceGroup: Color(0x662D1652),
    glass: Color(0x33FFFFFF),
    backdrop: Color(0xFF12091D),
    scrim: Color(0x8A000000),
    border: Color(0x0DFFFFFF),
    divider: Color(0x1AFFFFFF),
    overlay: Color(0x1AFFFFFF),
    track: Color(0x3DFFFFFF),
    primary: brandPrimary,
    onPrimary: Color(0xFFFFFFFF),
    primaryVariant: Color(0xFFC9A6FF),
    accentAqua: brandAccentAqua,
    accentBlue: brandNeonBlue,
    accentPurple: brandNeonPurple,
    accentPink: brandNeonPink,
    accentGreen: brandNeonGreen,
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFF44336),
    onDanger: Color(0xFFFFFFFF),
    dangerSurface: Color(0xFFB71C1C),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFF9800),
    info: Color(0xFF2196F3),
    infoSurface: Color(0xFFBBDEFB),
    shadow: Color(0x33000000),
    shadowSoft: Color(0x1A000000),
    shadowStrong: Color(0x4D000000),
    shadowToast: Color(0x73000000),
    homeSurface: Color(0xFF151219),
    homeSurfaceContainer: Color(0xFF211E26),
    homeOnSurface: Color(0xFFE7E0EA),
    homeOnSurfaceVariant: Color(0xFFCCC3D4),
    homeOutline: Color(0xFF958E9D),
    homeOutlineVariant: Color(0xFF4A4452),
    homeGlass: Color(0x661E1E1E),
    homePrimary: Color(0xFFD4BBFF),
    homePrimaryContainer: Color(0xFFB388FF),
    homeSecondary: Color(0xFFFFB3AE),
    homeBlob: Color(0xFF46128D),
    neutralMuted: Color(0xFFBDBDBD),
    neutralStrong: Color(0xFF424242),
    neutralText: Color(0xFF9E9E9E),
  );

  /// First-class light theme: same Violet-Punk identity, but light violet-tinted
  /// surfaces and dark ink. Every accent is darkened from its neon dark-mode
  /// value so it stays legible as text on `#F7F6F8` while still accepting white
  /// text as a fill foreground.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    contentPrimary: Color(0xFF140D1B),
    contentSecondary: Color(0xFF4A4354),
    contentTertiary: Color(0xFF6B6478),
    contentFaint: Color(0xFF8A8397),
    contentDisabled: Color(0xFFB3ADBD),
    contentPlaceholder: Color(0xFF9A93A6),
    contentHint: Color(0xFFB3ADBD),
    canvas: Color(0xFFF7F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF1EDF5),
    surfaceGroup: Color(0xFFE9E1F4),
    glass: Color(0xB3FFFFFF),
    backdrop: Color(0xFFEDE8F2),
    scrim: Color(0x8A140D1B),
    border: Color(0xFFE4DFEA),
    divider: Color(0xFFECE8F1),
    overlay: Color(0x0F140D1B),
    track: Color(0xFFDCD6E4),
    primary: brandPrimary,
    onPrimary: Color(0xFFFFFFFF),
    primaryVariant: Color(0xFF7F13EC),
    accentAqua: Color(0xFF00758C),
    accentBlue: Color(0xFF0369A1),
    accentPurple: Color(0xFF6E0FC4),
    accentPink: Color(0xFFB8005F),
    accentGreen: Color(0xFF00796B),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFC62828),
    onDanger: Color(0xFFFFFFFF),
    dangerSurface: Color(0xFFB3261E),
    success: Color(0xFF2E7D32),
    warning: Color(0xFFC2410C),
    info: Color(0xFF1565C0),
    infoSurface: Color(0xFF1E88E5),
    shadow: Color(0x14140D1B),
    shadowSoft: Color(0x0F140D1B),
    shadowStrong: Color(0x24140D1B),
    shadowToast: Color(0x59140D1B),
    homeSurface: Color(0xFFFFFFFF),
    homeSurfaceContainer: Color(0xFFF3EFF8),
    homeOnSurface: Color(0xFF1E1A24),
    homeOnSurfaceVariant: Color(0xFF4E4757),
    homeOutline: Color(0xFF6E6879),
    homeOutlineVariant: Color(0xFFE3DEE9),
    homeGlass: Color(0xB3FFFFFF),
    homePrimary: Color(0xFF5B21B6),
    homePrimaryContainer: Color(0xFF6D28D9),
    homeSecondary: Color(0xFF9A3412),
    homeBlob: Color(0xFFDDD0F5),
    neutralMuted: Color(0xFFE0DCE4),
    neutralStrong: Color(0xFF6E6879),
    neutralText: Color(0xFF6E6879),
  );

  /// The palette of the closest [Theme]. Falls back to dark so a widget still
  /// builds under a bare `ThemeData` (tests, `showDialog` outside the app).
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? dark;

  // ── Brand-fixed Violet-Punk identity (identical in both themes) ─────────────
  /// Primary brand violet, the fill of every primary action.
  static const Color brandPrimary = Color(0xFF7F13EC);

  static const Color brandAccentAqua = Color(0xFF00D4FF);
  static const Color brandNeonPurple = Color(0xFFBC13FE);
  static const Color brandNeonBlue = Color(0xFF00F5FF);
  static const Color brandNeonGreen = Color(0xFF00FFD9);
  static const Color brandNeonPink = Color(0xFFFF0080);

  static const Color brandGradientStart = Color(0xFF7F13EC);
  static const Color brandGradientAccent = Color(0xFFA855F7);

  /// Decorative circles over the auth hero gradient.
  static const Color brandHeroOverlay = Color(0x1AFFFFFF);

  /// Translucent white fill on the auth hero gradient.
  static const Color brandHeroGlass = Color(0x33FFFFFF);

  final Brightness brightness;

  // ── Ink ramp ───────────────────────────────────────────────────────────────
  /// Headings, body copy, primary icons.
  final Color contentPrimary;

  /// Supporting copy next to a title.
  final Color contentSecondary;

  /// Captions, timestamps, section headers.
  final Color contentTertiary;

  /// Barely-visible supporting copy.
  final Color contentFaint;

  /// Disabled / not-yet-available content.
  final Color contentDisabled;

  /// Placeholder and hint text of non-branded fields.
  final Color contentPlaceholder;

  /// Text field hint text.
  final Color contentHint;

  // ── Surfaces ───────────────────────────────────────────────────────────────
  /// `Scaffold` background.
  final Color canvas;

  /// Cards, dialogs, sheets, list tiles.
  final Color surface;

  /// Chips, banners, toasts, empty states.
  final Color surfaceElevated;

  /// Icon wells and inset areas.
  final Color surfaceSunken;

  /// Setting groups and other grouped fills.
  final Color surfaceGroup;

  /// Translucent fill on top of a colored gradient.
  final Color glass;

  /// Full-screen media viewer.
  final Color backdrop;

  /// Darkening layer over media tiles.
  final Color scrim;

  /// Component outlines.
  final Color border;

  /// Separators.
  final Color divider;

  /// Translucent fill for empty states and decorative shapes.
  final Color overlay;

  /// Progress tracks, sheet drag handles.
  final Color track;

  // ── Brand ──────────────────────────────────────────────────────────────────
  /// Filled primary action.
  final Color primary;

  /// Foreground on [primary].
  final Color onPrimary;

  /// Brand violet at text weight: readable on both canvases.
  final Color primaryVariant;

  final Color accentAqua;

  /// Bright cyan accent.
  final Color accentBlue;

  final Color accentPurple;
  final Color accentPink;
  final Color accentGreen;

  /// Foreground on any [accent*] fill.
  final Color onAccent;

  // ── Status ─────────────────────────────────────────────────────────────────
  final Color danger;

  /// Foreground on [dangerSurface].
  final Color onDanger;

  /// Error toast / banner fill.
  final Color dangerSurface;

  final Color success;
  final Color warning;
  final Color info;

  /// Info-toned element color (icons, chips).
  final Color infoSurface;

  // ── Shadows ────────────────────────────────────────────────────────────────
  final Color shadow;
  final Color shadowSoft;

  /// Elevated chrome (bottom nav, upload banner).
  final Color shadowStrong;

  /// Toast elevation.
  final Color shadowToast;

  // ── Homepage ("Midnight Glass") ────────────────────────────────────────────
  final Color homeSurface;
  final Color homeSurfaceContainer;
  final Color homeOnSurface;
  final Color homeOnSurfaceVariant;
  final Color homeOutline;
  final Color homeOutlineVariant;
  final Color homeGlass;
  final Color homePrimary;
  final Color homePrimaryContainer;
  final Color homeSecondary;
  final Color homeBlob;

  // ── Neutrals ───────────────────────────────────────────────────────────────
  /// Media placeholder fill.
  final Color neutralMuted;

  final Color neutralStrong;
  final Color neutralText;

  bool get isDark => brightness == Brightness.dark;

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? contentPrimary,
    Color? contentSecondary,
    Color? contentTertiary,
    Color? contentFaint,
    Color? contentDisabled,
    Color? contentPlaceholder,
    Color? contentHint,
    Color? canvas,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSunken,
    Color? surfaceGroup,
    Color? glass,
    Color? backdrop,
    Color? scrim,
    Color? border,
    Color? divider,
    Color? overlay,
    Color? track,
    Color? primary,
    Color? onPrimary,
    Color? primaryVariant,
    Color? accentAqua,
    Color? accentBlue,
    Color? accentPurple,
    Color? accentPink,
    Color? accentGreen,
    Color? onAccent,
    Color? danger,
    Color? onDanger,
    Color? dangerSurface,
    Color? success,
    Color? warning,
    Color? info,
    Color? infoSurface,
    Color? shadow,
    Color? shadowSoft,
    Color? shadowStrong,
    Color? shadowToast,
    Color? homeSurface,
    Color? homeSurfaceContainer,
    Color? homeOnSurface,
    Color? homeOnSurfaceVariant,
    Color? homeOutline,
    Color? homeOutlineVariant,
    Color? homeGlass,
    Color? homePrimary,
    Color? homePrimaryContainer,
    Color? homeSecondary,
    Color? homeBlob,
    Color? neutralMuted,
    Color? neutralStrong,
    Color? neutralText,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      contentPrimary: contentPrimary ?? this.contentPrimary,
      contentSecondary: contentSecondary ?? this.contentSecondary,
      contentTertiary: contentTertiary ?? this.contentTertiary,
      contentFaint: contentFaint ?? this.contentFaint,
      contentDisabled: contentDisabled ?? this.contentDisabled,
      contentPlaceholder: contentPlaceholder ?? this.contentPlaceholder,
      contentHint: contentHint ?? this.contentHint,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceGroup: surfaceGroup ?? this.surfaceGroup,
      glass: glass ?? this.glass,
      backdrop: backdrop ?? this.backdrop,
      scrim: scrim ?? this.scrim,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      overlay: overlay ?? this.overlay,
      track: track ?? this.track,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryVariant: primaryVariant ?? this.primaryVariant,
      accentAqua: accentAqua ?? this.accentAqua,
      accentBlue: accentBlue ?? this.accentBlue,
      accentPurple: accentPurple ?? this.accentPurple,
      accentPink: accentPink ?? this.accentPink,
      accentGreen: accentGreen ?? this.accentGreen,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      infoSurface: infoSurface ?? this.infoSurface,
      shadow: shadow ?? this.shadow,
      shadowSoft: shadowSoft ?? this.shadowSoft,
      shadowStrong: shadowStrong ?? this.shadowStrong,
      shadowToast: shadowToast ?? this.shadowToast,
      homeSurface: homeSurface ?? this.homeSurface,
      homeSurfaceContainer:
          homeSurfaceContainer ?? this.homeSurfaceContainer,
      homeOnSurface: homeOnSurface ?? this.homeOnSurface,
      homeOnSurfaceVariant:
          homeOnSurfaceVariant ?? this.homeOnSurfaceVariant,
      homeOutline: homeOutline ?? this.homeOutline,
      homeOutlineVariant: homeOutlineVariant ?? this.homeOutlineVariant,
      homeGlass: homeGlass ?? this.homeGlass,
      homePrimary: homePrimary ?? this.homePrimary,
      homePrimaryContainer:
          homePrimaryContainer ?? this.homePrimaryContainer,
      homeSecondary: homeSecondary ?? this.homeSecondary,
      homeBlob: homeBlob ?? this.homeBlob,
      neutralMuted: neutralMuted ?? this.neutralMuted,
      neutralStrong: neutralStrong ?? this.neutralStrong,
      neutralText: neutralText ?? this.neutralText,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      contentPrimary: c(contentPrimary, other.contentPrimary),
      contentSecondary: c(contentSecondary, other.contentSecondary),
      contentTertiary: c(contentTertiary, other.contentTertiary),
      contentFaint: c(contentFaint, other.contentFaint),
      contentDisabled: c(contentDisabled, other.contentDisabled),
      contentPlaceholder: c(contentPlaceholder, other.contentPlaceholder),
      contentHint: c(contentHint, other.contentHint),
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      surfaceGroup: c(surfaceGroup, other.surfaceGroup),
      glass: c(glass, other.glass),
      backdrop: c(backdrop, other.backdrop),
      scrim: c(scrim, other.scrim),
      border: c(border, other.border),
      divider: c(divider, other.divider),
      overlay: c(overlay, other.overlay),
      track: c(track, other.track),
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      primaryVariant: c(primaryVariant, other.primaryVariant),
      accentAqua: c(accentAqua, other.accentAqua),
      accentBlue: c(accentBlue, other.accentBlue),
      accentPurple: c(accentPurple, other.accentPurple),
      accentPink: c(accentPink, other.accentPink),
      accentGreen: c(accentGreen, other.accentGreen),
      onAccent: c(onAccent, other.onAccent),
      danger: c(danger, other.danger),
      onDanger: c(onDanger, other.onDanger),
      dangerSurface: c(dangerSurface, other.dangerSurface),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      info: c(info, other.info),
      infoSurface: c(infoSurface, other.infoSurface),
      shadow: c(shadow, other.shadow),
      shadowSoft: c(shadowSoft, other.shadowSoft),
      shadowStrong: c(shadowStrong, other.shadowStrong),
      shadowToast: c(shadowToast, other.shadowToast),
      homeSurface: c(homeSurface, other.homeSurface),
      homeSurfaceContainer:
          c(homeSurfaceContainer, other.homeSurfaceContainer),
      homeOnSurface: c(homeOnSurface, other.homeOnSurface),
      homeOnSurfaceVariant:
          c(homeOnSurfaceVariant, other.homeOnSurfaceVariant),
      homeOutline: c(homeOutline, other.homeOutline),
      homeOutlineVariant: c(homeOutlineVariant, other.homeOutlineVariant),
      homeGlass: c(homeGlass, other.homeGlass),
      homePrimary: c(homePrimary, other.homePrimary),
      homePrimaryContainer:
          c(homePrimaryContainer, other.homePrimaryContainer),
      homeSecondary: c(homeSecondary, other.homeSecondary),
      homeBlob: c(homeBlob, other.homeBlob),
      neutralMuted: c(neutralMuted, other.neutralMuted),
      neutralStrong: c(neutralStrong, other.neutralStrong),
      neutralText: c(neutralText, other.neutralText),
    );
  }
}

/// Palette of the enclosing [Theme].
extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(this);
}
