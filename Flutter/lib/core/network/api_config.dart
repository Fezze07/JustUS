import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  static const String _devServerOrigin = 'https://justus-dev.serverfede.eu';
  static const String _prodServerOrigin = 'https://justus.serverfede.eu';

  static bool get isDebug => kDebugMode;

  static String get serverOrigin =>
      isDebug ? _devServerOrigin : _prodServerOrigin;

  static String get apiOrigin => serverOrigin;

  static String get appOrigin => serverOrigin;

  static Uri apiUri(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    final uri = Uri.parse('$apiOrigin$path');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  static String appUrl(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    return '$appOrigin$normalizedPath';
  }
}