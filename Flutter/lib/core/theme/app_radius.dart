// =============================================================================
// App Radius - the single source of truth for corner radii
// =============================================================================
//
// Every radius used by `AppTheme` or by a VP component must come from this
// scale, so the shape language cannot drift between the theme and the widgets.

class AppRadius {
  AppRadius._();

  /// Hairline / micro containers: drag handles, code badges, thin bars.
  static const double xs = 4;

  /// Small surfaces: compact cards and boxes.
  static const double sm = 12;

  /// Interactive surfaces: buttons, text fields, icon boxes.
  static const double md = 16;

  /// Large surfaces: cards, dialogs, setting groups.
  static const double lg = 24;

  /// Bottom sheets and the bottom navigation bar.
  static const double sheet = 32;

  /// Fully rounded shapes: chips, pills, circular buttons.
  static const double pill = 100;
}
