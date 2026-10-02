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
  static Future<String?>? _bindingSecretRecovery;
  static DateTime? _lastBindingSecretSyncAttempt;

  static void setCachedRequestBindingSecret(String secret) {
    _cachedRequestBindingSecret = secret;
  }

  static void clearHeadersCache() {
    _cachedDeviceFingerprint = null;
    _cachedRequestBindingSecret = null;
    _bindingSecretRecovery = null;
    _lastBindingSecretSyncAttempt = null;
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

  /// Resolves [url] to a fetchable media URL and appends `v=<version>` so the
  /// image cache treats a new [version] as a brand new entry. A `null` [version]
  /// returns the plain resolved URL.
  static String? versionedMediaUrl(String? url, int? version) {
    final resolved = resolveProtectedMediaUrl(url);
    if (resolved == null || version == null) return resolved;

    final uri = Uri.parse(resolved);

    return uri.replace(
      queryParameters: {...uri.queryParameters, 'v': '$version'},
    ).toString();
  }

  // HTTP client
  final http.Client _client;
  final Uuid _uuid = const Uuid();
  late final String _clientUserAgent = _buildClientUserAgent();
  late final String _clientUserAgentHash = _sha256(_clientUserAgent);

  ApiService({http.Client? client})
      : _client = client ?? LoggingHttpClient(http.Client(), tag: 'ApiService');

  // Global callback for session expiration
  static Future<void> Function()? onSessionExpired;

  static Future<void> Function()? onMissingBindingSecret;

  /// Optional override for token refreshing (used in tests to bypass Supabase.instance dependency).
  @visibleForTesting
  static Future<bool> Function(String? staleAccessToken)? tokenRefreshHandler;

  /// Optional override for the access-token read.
  ///
  /// The 401 refresh-retry contract (1.1/1.2) can only be verified by observing
  /// that the retry is authorized with the *new* token, which requires a
  /// rotatable session that no in-process fake of the Supabase SDK provides.
  @visibleForTesting
  static String? Function()? readAccessTokenForTest;

  // -------------------- Helper Methods --------------------

  /// Reads the current Supabase access token, or `null` when there is no
  /// session or the Supabase singleton is not reachable.
  ///
  /// A lookup failure is logged, never silently swallowed: dropping the
  /// `Authorization` header turns a locally detectable misconfiguration into a
  /// puzzling 401 from the API, so it must be visible in the log.
  static String? _readAccessToken() {
    final override = readAccessTokenForTest;
    if (override != null) {
      return override();
    }

    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (error) {
      AnsiLogger.error(
        'Access token unavailable: $error',
        tag: 'ApiService',
      );

      return null;
    }
  }

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
      final token = _readAccessToken();
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

      String? bindingSecret = _cachedRequestBindingSecret;
      if (bindingSecret == null) {
        bindingSecret = await StorageService.getRequestBindingSecret();
        _cachedRequestBindingSecret = bindingSecret;
      }

      if ((bindingSecret == null || bindingSecret.isEmpty) &&
          requireSignature &&
          !skipAuth) {
        bindingSecret = await _recoverBindingSecret();
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
        throw const AppError(
          code: ErrorCodes.localBindingSecretMissing,
          message: 'Request binding secret unavailable',
          severity: ErrorSeverity.high,
        );
      } else {
        headers['X-Request-Timestamp'] = timestamp;
        headers['X-Request-Nonce'] = nonce;
      }
    }

    return headers;
  }

  Future<String?> _recoverBindingSecret() {
    final inFlight = _bindingSecretRecovery;
    if (inFlight != null) return inFlight;

    final now = DateTime.now();
    final lastAttempt = _lastBindingSecretSyncAttempt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 30)) {
      return Future.value(_cachedRequestBindingSecret);
    }

    _lastBindingSecretSyncAttempt = now;
    final recovery = _runBindingSecretRecovery().whenComplete(() {
      _bindingSecretRecovery = null;
    });
    _bindingSecretRecovery = recovery;

    return recovery;
  }

  Future<String?> _runBindingSecretRecovery() async {
    try {
      await onMissingBindingSecret?.call();
    } catch (e) {
      AnsiLogger.error('Binding secret recovery failed: $e', tag: 'ApiService');
    }

    final secret = _cachedRequestBindingSecret ??
        await StorageService.getRequestBindingSecret();
    _cachedRequestBindingSecret = secret;

    return (secret == null || secret.isEmpty) ? null : secret;
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
    bool usesAuth = true,
    Duration timeout = const Duration(seconds: 10),
    String? label,
  }) async {
    final requestAccessToken = usesAuth ? _readAccessToken() : null;

    try {
      final response = await call().timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AnsiLogger.api('⇠ Body: ${response.body}');
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = await compute(_isolateDecodeResponse, response.body);

        return Success(fromJson(body));
      } else if (response.statusCode == 401 && !isRetry) {
        // Token expired - refresh through the single Supabase SDK path
        final refreshResult = await _tryRefreshToken(requestAccessToken);
        if (refreshResult) {
          // Retry the original call
          return await _safeCall(call, fromJson,
              isRetry: true,
              usesAuth: usesAuth,
              timeout: timeout,
              label: label);
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
    } on AppError catch (e) {
      AnsiLogger.error('AppError: $e', tag: 'ApiService');

      return GenericError(message: e.message, details: e);
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
      usesAuth: !skipAuth,
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
      usesAuth: !skipAuth,
      timeout: timeout,
    );
  }

  Future<bool> _tryRefreshToken(String? staleAccessToken) async {
    if (tokenRefreshHandler != null) {
      return tokenRefreshHandler!(staleAccessToken);
    }

    final auth = Supabase.instance.client.auth;

    final currentAccessToken = auth.currentSession?.accessToken;
    if (currentAccessToken != null &&
        currentAccessToken.isNotEmpty &&
        currentAccessToken != staleAccessToken) {
      return true;
    }

    try {
      final response = await auth.refreshSession();
      final session = response.session;
      if (session == null || session.accessToken.isEmpty) {
        return false;
      }

      await StorageService.saveAccessToken(session.accessToken);
      final newRefreshToken = session.refreshToken;
      if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
        await StorageService.saveRefreshToken(newRefreshToken);
      }

      return session.accessToken != staleAccessToken;
    } catch (e) {
      AnsiLogger.error('_tryRefreshToken error: $e', tag: 'ApiService');

      return false;
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

  Future<ResultWrapper<Map<String, dynamic>>> deleteMediaItem(int id) async {
    return _post(
      ApiRoutes.mediaDelete,
      body: {'id': id},
      requireSignature: true,
      label: 'Delete Media',
    );
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
