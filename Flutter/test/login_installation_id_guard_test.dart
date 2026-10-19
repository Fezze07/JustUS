import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 10.12 (F-PN5): installation-id registration at login
/// has to pass the same `supportsFcm` guard the other call sites use. Without
/// it an FCM-less platform would register an empty id and, because
/// `user_devices.installation_id` is globally UNIQUE, one row silently
/// re-points between unrelated accounts as they log in and out.
const String _kInstallationId =
    'fid-registered-by-the-login-test-0123456789';

class _RecordingAuthRepository extends AuthRepository {
  final List<String> registeredInstallationIds = [];

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
  Future<ResultWrapper<void>> updateInstallationId(String installationId,
      {String? locale}) async {
    registeredInstallationIds.add(installationId);
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
    InstallationIdService.installationIdOverride = () async => _kInstallationId;
  });

  tearDown(() {
    InstallationIdService.installationIdOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test('login registers the installation id when FCM is supported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final repo = _RecordingAuthRepository();
    final state = _stateWith(repo);

    expect(await state.login('user@example.com', 'password'), isTrue);
    expect(repo.registeredInstallationIds, [_kInstallationId]);
  });

  test('login makes no request when FCM is unsupported', () async {
    // macOS/Linux: `getInstallationId()` returns an empty string.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final repo = _RecordingAuthRepository();
    final state = _stateWith(repo);

    expect(await state.login('user@example.com', 'password'), isTrue);
    expect(repo.registeredInstallationIds, isEmpty);
  });
}
