import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 10.12 (F-PN5): device-token registration at login has
/// to pass the same `supportsFcm` guard the other call sites use. Without it an
/// FCM-less platform registers the shared `UNKNOWN_DEVICE_TOKEN` placeholder
/// and, because `user_devices.device_token` is globally UNIQUE, one row
/// silently re-points between unrelated accounts as they log in and out.
const String _kFcmToken = 'fcm-token-registered-by-the-login-test-0123456789';

class _RecordingAuthRepository extends AuthRepository {
  final List<String> registeredTokens = [];

  static final sb.Session _session = sb.Session(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 'bearer',
    user: const sb.User(
      id: 'auth-uuid',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      email: 'user@example.com',
      createdAt: '2026-05-01T00:00:00.000Z',
    ),
  );

  @override
  sb.Session? get currentSession => _session;

  @override
  Future<ResultWrapper<Map<String, dynamic>>> checkLoginRisk(
          String email, String deviceFingerprint) async =>
      const Success<Map<String, dynamic>>({'success': true});

  @override
  Future<ResultWrapper<Map<String, dynamic>>> bindSession(
          String deviceFingerprint) async =>
      const Success<Map<String, dynamic>>({'bindingSecret': 'secret'});

  @override
  Future<sb.AuthResponse> signInWithPassword({
    required String email,
    required String password,
    required String captchaToken,
  }) async =>
      sb.AuthResponse(session: _session, user: _session.user);

  @override
  Future<ResultWrapper<void>> updateDeviceToken(String deviceToken,
      {String? locale}) async {
    registeredTokens.add(deviceToken);
    return const Success(null);
  }
}

class _FakeUserRepository extends UserRepository {
  @override
  Future<ResultWrapper<User>> fetchProfileByAuthId(String authId) async =>
      Success(User(
        id: 1,
        email: 'user@example.com',
        authId: authId,
        displayName: 'Alex',
      ));
}

class _FakePartnershipRepository extends PartnershipRepository {
  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async =>
      Success(PartnershipResponse(success: true));
}

AuthState _stateWith(AuthRepository repository) => AuthState(
      authRepo: repository,
      userRepo: _FakeUserRepository(),
      partnershipRepo: _FakePartnershipRepository(),
      captchaTokenProvider: () async => 'captcha-token',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    DeviceTokenService.tokenOverride = () async => _kFcmToken;
  });

  tearDown(() {
    DeviceTokenService.tokenOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test('login registers the token when FCM is supported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final repo = _RecordingAuthRepository();
    final state = _stateWith(repo);

    expect(await state.login('user@example.com', 'password'), isTrue);
    expect(repo.registeredTokens, [_kFcmToken]);
  });

  test('login makes no device-token request when FCM is unsupported', () async {
    // macOS/Linux: `getDeviceToken()` would return the shared placeholder.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final repo = _RecordingAuthRepository();
    final state = _stateWith(repo);

    expect(await state.login('user@example.com', 'password'), isTrue);
    expect(repo.registeredTokens, isEmpty);
  });
}
