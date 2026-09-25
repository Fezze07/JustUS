import 'package:flutter/material.dart';

/// Categorical accent palette for bucket categories.
///
/// These are identity colors, not theme colors: each one marks a single
/// category across the bucket list, the bucket detail and the home widget, so
/// the same category must always render the same hue. They live here (instead
/// of inline in `bucket_category.dart`) so the palette is as tokenized as
/// `AppColors` and can be re-skinned in one place.
abstract final class AppCategoryColors {
  static const Color travel = Color(0xFF4FC3F7);
  static const Color dates = Color(0xFFFF8A65);
  static const Color goals = Color(0xFF81C784);
  static const Color crazy = Color(0xFFCE93D8);
  static const Color adventure = Color(0xFFFFD54F);
  static const Color romantic = Color(0xFFF06292);
  static const Color homemade = Color(0xFF4DD0E1);
}
