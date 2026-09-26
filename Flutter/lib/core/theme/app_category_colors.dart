import 'package:flutter/material.dart';

/// Categorical accent palette for bucket categories.
///
/// These are identity colors, not theme colors: each one marks a single
/// category across the bucket list, the bucket detail and the home widget, so
/// the same category must always render the same hue. They live here (instead
/// of inline in `bucket_category.dart`) so the palette is as tokenized as
/// `AppPalette.Brand` and can be re-skinned in one place.
abstract final class AppCategoryColors {
  // Dark mode (bright pastel)
  static const Color travel = Color(0xFF4FC3F7);
  static const Color dates = Color(0xFFFF8A65);
  static const Color goals = Color(0xFF81C784);
  static const Color crazy = Color(0xFFCE93D8);
  static const Color adventure = Color(0xFFFFD54F);
  static const Color romantic = Color(0xFFF06292);
  static const Color homemade = Color(0xFF4DD0E1);

  // Light mode (deeper saturated tones for high contrast on light backgrounds)
  static const Color travelLight = Color(0xFF0288D1);
  static const Color datesLight = Color(0xFFD84315);
  static const Color goalsLight = Color(0xFF2E7D32);
  static const Color crazyLight = Color(0xFF7B1FA2);
  static const Color adventureLight = Color(0xFFB45309);
  static const Color romanticLight = Color(0xFFC2185B);
  static const Color homemadeLight = Color(0xFF00838F);
}
