// =============================================================================
// ApiService - HTTP client with all API endpoints
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:justus/all_imports.dart';

// --- Isolate helper for JSON response decoding ---
// Top-level function required by compute() for isolate offloading.

Map<String, dynamic> _isolateDecodeResponse(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

class ApiService {
  static String? _cachedDeviceFingerprint;
  static String? _cachedRequestBindingSecret;

  static void setCachedRequestBindingSecret(String secret) {
    _cachedRequestBindingSecret = secret;
  }

  static void clearHeadersCache() {
    _cachedDeviceFingerprint = null;
    _cachedRequestBindingSecret = null;
  }

  static Map<String, String> get authHeaders {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      return const {};
    }

    return {'Authorization': 'Bearer $token'};
  }

  static String? resolveProtectedMediaUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;

    return ApiConfig.apiUri(
      ApiRoutes.mediaFile,
      queryParameters: {'filename': url},
    ).toString();
  }

  // HTTP client
  final http.Client _client;
  final Uuid _uuid = const Uuid();
  late final String _clientUserAgent = _buildClientUserAgent();
  late final String _clientUserAgentHash = _sha256(_clientUserAgent);

  ApiService({http.Client? client})
      : _client = client ?? LoggingHttpClient(http.Client(), tag: 'ApiService');

  // Flag to prevent concurrent refresh attempts
  bool _isRefreshing = false;

  // Global callback for session expiration
  static Future<void> Function()? onSessionExpired;

  // -------------------- Helper Methods --------------------

  Future<Map<String, String>> _getHeaders({bool skipAuth = false}) async {
    return _buildHeaders(skipAuth: skipAuth);
  }

  Future<Map<String, String>> _buildHeaders({
    bool skipAuth = false,
    String? method,
    String? path,
    Object? payload,
    bool requireSignature = false,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (!skipAuth) {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    String? deviceFingerprint = _cachedDeviceFingerprint;
    if (deviceFingerprint == null) {
      deviceFingerprint = await StorageService.getOrCreateDeviceFingerprint();
      _cachedDeviceFingerprint = deviceFingerprint;
    }
    headers['X-Device-Fingerprint'] = deviceFingerprint;
    headers['X-Client-User-Agent'] = _clientUserAgent;
    headers['X-Client-User-Agent-Hash'] = _clientUserAgentHash;

    if (method != null && path != null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final nonce = _uuid.v4();
      headers['X-Request-Timestamp'] = timestamp;
      headers['X-Request-Nonce'] = nonce;

      String? bindingSecret = _cachedRequestBindingSecret;
      if (bindingSecret == null) {
        bindingSecret = await StorageService.getRequestBindingSecret();
        _cachedRequestBindingSecret = bindingSecret;
      }
      if (bindingSecret != null && bindingSecret.isNotEmpty) {
        final bodyString = payload == null ? '' : jsonEncode(payload);
        final bodyHash = _sha256(bodyString);
        final canonical = [
          method.toUpperCase(),
          path,
          timestamp,
          nonce,
          bodyHash,
        ].join('.');
        final signature = Hmac(
          sha256,
          utf8.encode(bindingSecret),
        ).convert(utf8.encode(canonical)).toString();

        headers['X-Request-Timestamp'] = timestamp;
        headers['X-Request-Nonce'] = nonce;
        headers['X-Request-Signature'] = signature;
      } else if (requireSignature) {
        throw const HttpException('Missing request binding secret');
      }
    }

    return headers;
  }

  String _buildClientUserAgent() {
    if (kIsWeb) {
      return 'justus/flutter/web';
    }

    return 'justus/flutter/${defaultTargetPlatform.name}';
  }

  String _sha256(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<ResultWrapper<T>> _safeCall<T>(
    Future<http.Response> Function() call,
    T Function(Map<String, dynamic>) fromJson, {
    bool isRetry = false,
    Duration timeout = const Duration(seconds: 10),
    String? label,
  }) async {
    try {
      final response = await call().timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AnsiLogger.api('⇠ Body: ${response.body}');
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = await compute(_isolateDecodeResponse, response.body);

        return Success(fromJson(body));
      } else if (response.statusCode == 401 && !isRetry && !_isRefreshing) {
        // Token expired - try to refresh
        final refreshResult = await _tryRefreshToken();
        if (refreshResult) {
          // Retry the original call
          return _safeCall(call, fromJson,
              isRetry: true, timeout: timeout, label: label);
        }
        // Refresh failed
        await onSessionExpired?.call();

        return const GenericError(
            code: 401, message: 'Session expired. Please login again.');
      } else {
        String? errorMessage;
        AppError? appError;
        try {
          final errorBody =
              await compute(_isolateDecodeResponse, response.body);
          if (errorBody['error'] != null) {
            appError = AppError.fromJson(errorBody);
            errorMessage = appError.message;
          } else {
            errorMessage =
                (errorBody['error'] ?? errorBody['message']) as String?;
          }
        } catch (_) {}

        if (appError != null) {
          return GenericError(
              code: response.statusCode,
              message: errorMessage,
              details: appError);
        }

        return GenericError(code: response.statusCode, message: errorMessage);
      }
    } on TimeoutException {
      return const NetworkError(
          message: 'Richiesta scaduta (timeout). Controlla la connessione.');
    } on SocketException catch (e) {
      AnsiLogger.error('SocketException: $e', tag: 'ApiService');

      return NetworkError(message: 'Errore di connessione: ${e.message}');
    } on HttpException catch (e) {
      AnsiLogger.error('HttpException: $e', tag: 'ApiService');

      return NetworkError(message: e.message);
    } catch (e) {
      AnsiLogger.error('Unknown error: $e', tag: 'ApiService');

      return GenericError(message: e.toString());
    }
  }

  Future<ResultWrapper<T>> _get<T>(
    String path, {
    bool skipAuth = false,
    String? label,
    T Function(Map<String, dynamic>)? fromJson,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _safeCall<T>(
      () async {
        final headers = await _getHeaders(skipAuth: skipAuth);

        return _client.get(ApiConfig.apiUri(path), headers: headers);
      },
      fromJson ?? (json) => json as T,
      label: label,
      timeout: timeout,
    );
  }

  Future<ResultWrapper<T>> _post<T>(
    String path, {
    Object? body,
    bool skipAuth = false,
    bool requireSignature = false,
    String? label,
    T Function(Map<String, dynamic>)? fromJson,
    Duration timeout = const Duration(seconds: 10),
    Map<String, String>? extraHeaders,
  }) async {
    return _safeCall<T>(
      () async {
        final headers = await _buildHeaders(
          method: 'POST',
          path: path,
          payload: body,
          requireSignature: requireSignature,
          skipAuth: skipAuth,
        );

        if (extraHeaders != null) {
          headers.addAll(extraHeaders);
        }

        return _client.post(
          ApiConfig.apiUri(path),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      },
      fromJson ?? (json) => json as T,
      label: label,
      timeout: timeout,
    );
  }

  Future<bool> _tryRefreshToken() async {
    if (_isRefreshing) return false;
    _isRefreshing = true;

    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      final response = await _client.post(
        ApiConfig.apiUri(ApiRoutes.authRefresh),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = body['accessToken'] as String?;
        if (newAccessToken != null) {
          await StorageService.saveAccessToken(newAccessToken);
          // Also save new refresh token if provided
          final newRefreshToken = body['refreshToken'] as String?;
          if (newRefreshToken != null) {
            await StorageService.saveRefreshToken(newRefreshToken);
          }

          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  // -------------------- Auth --------------------
  Future<ResultWrapper<UpdateTokenResponse>> updateDeviceToken(
      UpdateTokenRequest body) async {
    return _post(
      ApiRoutes.authDeviceToken,
      body: body.toJson(),
      requireSignature: true,
      fromJson: UpdateTokenResponse.fromJson,
      label: 'Update Device Token',
    );
  }

  Future<ResultWrapper<Map<String, dynamic>>> inviteUser(
      Map<String, dynamic> body) async {
    return _post(ApiRoutes.authInvite, body: body, label: 'Invite User');
  }

  Future<ResultWrapper<Map<String, dynamic>>> requestPartnership(
      Map<String, dynamic> body) async {
    return _post(ApiRoutes.authInvite,
        body: body, label: 'Request Partnership');
  }

  Future<ResultWrapper<Map<String, dynamic>>> checkLoginRisk(
      Map<String, dynamic> body) async {
    return _post(ApiRoutes.authLoginRiskCheck,
        body: body, skipAuth: true, label: 'Check Login Risk');
  }

  Future<ResultWrapper<Map<String, dynamic>>> reportFailedLogin(
      Map<String, dynamic> body) async {
    return _post(ApiRoutes.authLoginAttempt,
        body: body, skipAuth: true, label: 'Report Failed Login');
  }

  Future<ResultWrapper<Map<String, dynamic>>> syncSession(
      Map<String, dynamic> body) async {
    return _post(ApiRoutes.authSessionSync, body: body, label: 'Sync Session');
  }

  Future<ResultWrapper<Map<String, dynamic>>> createMediaUploadUrl(
      Map<String, dynamic> body) async {
    return _post(ApiRoutes.mediaUploadUrl,
        body: body, requireSignature: true, label: 'Create Media Upload URL');
  }

  Future<ResultWrapper<Map<String, dynamic>>> completeMediaUpload(
      Map<String, dynamic> body) async {
    return _post(ApiRoutes.mediaComplete,
        body: body, requireSignature: true, label: 'Complete Media Upload');
  }

  // -------------------- AI Question Generation --------------------

  Future<ResultWrapper<Map<String, dynamic>>> generateAiQuestion() async {
    return _post(
      ApiRoutes.aiQuestion,
      body: {},
      requireSignature: true,
      extraHeaders: {'X-Idempotency-Key': _uuid.v4()},
      timeout: const Duration(seconds: 60),
      label: 'AI Question Generation',
    );
  }

  // -------------------- Notifications --------------------

  /// Sends a notification key + params so the receiver's device
  /// localizes the message into its own language.
  Future<ResultWrapper<Map<String, dynamic>>> notifyPartner({
    required String notificationKey,
    Map<String, String> params = const {},
  }) {
    return _post(
      ApiRoutes.notifyPartner,
      body: {
        'notificationKey': notificationKey,
        'params': params,
      },
      label: 'Notify Partner',
    );
  }

  // -------------------- App Version --------------------

  Future<ResultWrapper<AppVersionResponse>> getAppVersion() async {
    return _get(
      ApiRoutes.appVersion,
      skipAuth: true,
      fromJson: AppVersionResponse.fromJson,
      label: 'Get App Version',
    );
  }

  // -------------------- User Data --------------------

  Future<ResultWrapper<Map<String, dynamic>>> wipeUserData() async {
    return _post(ApiRoutes.userWipe, label: 'Wipe User Data');
  }

  // -------------------- Cleanup --------------------

  void dispose() {
    _client.close();
  }
}
