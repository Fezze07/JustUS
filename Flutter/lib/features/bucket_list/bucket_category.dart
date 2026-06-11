import 'package:flutter/material.dart';
import 'package:justus/core/localization/generated/app_localizations.dart';

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

  static const Color travel = Color(0xFF4FC3F7);
  static const Color dates = Color(0xFFFF8A65);
  static const Color goals = Color(0xFF81C784);
  static const Color crazy = Color(0xFFCE93D8);
  static const Color adventure = Color(0xFFFFD54F);
  static const Color romantic = Color(0xFFF06292);
  static const Color homemade = Color(0xFF4DD0E1);

  static const Map<String, Color> _colors = {
    'Travel': travel,
    'Dates': dates,
    'Goals': goals,
    'Crazy': crazy,
    'Adventure': adventure,
    'Romantic': romantic,
    'Homemade': homemade,
  };

  static Color colorFor(String category) {
    return _colors[category] ?? Colors.white70;
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
