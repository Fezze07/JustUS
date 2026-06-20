import 'package:flutter/foundation.dart';

class AnsiLogger {
  // Color constants
  static const String reset = '\x1B[0m';
  static const String black = '\x1B[30m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String purple = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';

  // Helper method to log with a specific color
  static void log(String message, {required String color, String? tag}) {
    if (!kDebugMode) return;
    final prefix = tag != null ? '[$tag] ' : '';
    // ignore: avoid_print
    print('$color$prefix$message$reset');
  }

  // Specialized helpers
  static void auth(String message, {String tag = 'Auth'}) => log(message, color: green, tag: tag);
  static void api(String message, {String tag = 'ApiService'}) => log(message, color: cyan, tag: tag);
  static void supabase(String message, {String tag = 'SupabaseService'}) => log(message, color: blue, tag: tag);
  static void realtime(String message, {String tag = 'RealtimeSync'}) => log(message, color: purple, tag: tag);
  static void notification(String message, {String tag = 'Notifications'}) => log(message, color: yellow, tag: tag);
  static void error(String message, {String tag = 'Error'}) => log(message, color: red, tag: tag);
}
