import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class BucketCategory {
  BucketCategory._();

  static const String all = 'all';

  static const List<String> items = [
    'Travel',
    'Dates',
    'Goals',
    'Crazy',
    'Adventure',
    'Romantic',
    'Homemade',
  ];

  static List<String> get withAll => [all, ...items];

  static const Color travel = AppCategoryColors.travel;
  static const Color dates = AppCategoryColors.dates;
  static const Color goals = AppCategoryColors.goals;
  static const Color crazy = AppCategoryColors.crazy;
  static const Color adventure = AppCategoryColors.adventure;
  static const Color romantic = AppCategoryColors.romantic;
  static const Color homemade = AppCategoryColors.homemade;

  static const Map<String, Color> _colors = {
    'Travel': travel,
    'Dates': dates,
    'Goals': goals,
    'Crazy': crazy,
    'Adventure': adventure,
    'Romantic': romantic,
    'Homemade': homemade,
  };

  static const Map<String, Color> _lightColors = {
    'Travel': AppCategoryColors.travelLight,
    'Dates': AppCategoryColors.datesLight,
    'Goals': AppCategoryColors.goalsLight,
    'Crazy': AppCategoryColors.crazyLight,
    'Adventure': AppCategoryColors.adventureLight,
    'Romantic': AppCategoryColors.romanticLight,
    'Homemade': AppCategoryColors.homemadeLight,
  };

  static Color colorFor(BuildContext context, String category) {
    final isDark = context.palette.isDark;
    final map = isDark ? _colors : _lightColors;
    return map[category] ?? context.palette.contentSecondary;
  }

  static String localizedLabel(String category, AppLocalizations loc) {
    return switch (category) {
      all => loc.bucket_categoryAll,
      'Travel' => loc.bucket_categoryTravel,
      'Dates' => loc.bucket_categoryDates,
      'Goals' => loc.bucket_categoryGoals,
      'Crazy' => loc.bucket_categoryCrazy,
      'Adventure' => loc.bucket_categoryAdventure,
      'Romantic' => loc.bucket_categoryRomantic,
      'Homemade' => loc.bucket_categoryHomemade,
      _ => category,
    };
  }
}
