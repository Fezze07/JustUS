// =============================================================================
// App Dimensions - spacing scale and recurring component sizes
// =============================================================================
//
// Replaces the inline magic numbers that used to be repeated across screens.
// Only values shared by more than one component belong here; one-off layout
// numbers stay local to the widget that needs them.

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppDims {
  AppDims._();

  /// Square icon container used by setting tiles, headers and app bars.
  static const double iconBox = 48;

  /// Round icon button (nav, sheets, drive back button).
  static const double circleButton = 40;

  /// Minimum height of a primary action button.
  static const double buttonMinHeight = 52;

  /// Thickness of `VPDivider` / hairline separators.
  static const double hairline = 1;

  /// Elevated "home" button of the bottom navigation bar.
  static const double navCenter = 56;

  /// Active-indicator dot of the bottom navigation bar.
  static const double dot = 4;

  /// Height of the bottom navigation bar.
  static const double navBar = 90;

  /// Bucket-list completion box.
  static const double checkbox = 24;

  /// Gap between a form's last field and its submit button.
  static const double formSectionGap = 48;
}
