import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:justus/core/network/api_routes.dart';

class ApiConfig {
  ApiConfig._();

  static const String _defaultAppOrigin = 'https://justus.serverfede.eu';

  static bool get isDebug => dotenv.env['IS_DEBUG']?.toLowerCase() == 'true';

  static String get appOrigin {
    final configured = isDebug
        ? dotenv.env['APP_DEBUG_BASE_URL']
        : dotenv.env['APP_RELEASE_BASE_URL'];

    if (configured != null && configured.trim().isNotEmpty) {
      return _normalizeOrigin(configured);
    }

    return _defaultAppOrigin;
  }

  static String get apiOrigin {
    final configured = isDebug
        ? dotenv.env['API_DEBUG_BASE_URL']
        : dotenv.env['API_RELEASE_BASE_URL'];

    if (configured != null && configured.trim().isNotEmpty) {
      return _normalizeOrigin(configured);
    }

    return appOrigin;
  }

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

  static String _normalizeOrigin(String value) {
    var normalized = value.trim();
    normalized = normalized.replaceFirst(RegExp(r'/$'), '');
    normalized = normalized.replaceFirst(
      RegExp('${ApiRoutes.apiPrefix}\$'),
      '',
    );

    return normalized;
  }
}
