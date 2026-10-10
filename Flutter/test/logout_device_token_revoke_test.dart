import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 9.2: logout must drop the push registration for this
/// device, and it must do so without ever blocking or failing the teardown —
/// an offline device still has to end up logged out.
const String kTestFcmToken = 'fcm-token-used-by-the-logout-tests-0123456789';

class _RecordingAuthRepository extends AuthRepository {
  _RecordingAuthRepository({this.onRevoke});

  final Future<void> Function(String deviceToken)? onRevoke;
  final List<String> calls = [];

  @override
  Future<void> signOut() async {
    calls.add('signOut');
  }

  @override
  Future<ResultWrapper<Map<String, dynamic>>> revokeDeviceToken(
      String deviceToken) async {
    calls.add('revoke:$deviceToken');

    final hook = onRevoke;
    if (hook != null) await hook(deviceToken);

    return const Success(<String, dynamic>{'success': true});
  }
}

Future<void> _login(AuthState auth) => auth.setLoginData(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      user: User(id: 1, email: 'user@example.com', displayName: 'Alex'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    installMockPathProvider();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    DeviceTokenService.tokenOverride = () async => kTestFcmToken;
  });

  tearDown(() {
    DeviceTokenService.tokenOverride = null;
  });

  test('logout revokes the device token before signing out', () async {
    final repo = _RecordingAuthRepository();
    final auth = AuthState(authRepo: repo);
    await _login(auth);

    expect(auth.isLoggedIn, isTrue);
    expect(repo.calls, isEmpty);

    await auth.logout();

    // The revoke must run while the JWT and the binding secret still exist:
    // it is issued before `signOut()`, not after.
    expect(repo.calls, ['revoke:$kTestFcmToken', 'signOut']);
    expect(auth.isLoggedIn, isFalse);
    expect(await StorageService.getAccessToken(), isNull);
  });

  test('logout completes when the revoke fails', () async {
    final repo = _RecordingAuthRepository(
      onRevoke: (_) async => throw const NetworkError(message: 'offline'),
    );
    final auth = AuthState(authRepo: repo);
    await _login(auth);

    await auth.logout();

    expect(repo.calls, ['revoke:$kTestFcmToken', 'signOut']);
    expect(auth.isLoggedIn, isFalse);
    expect(await StorageService.getUserId(), isNull);
  });

  test('logout is not blocked by a revoke that never answers', () async {
    final repo = _RecordingAuthRepository(
      onRevoke: (_) => Completer<void>().future,
    );
    final auth = AuthState(
      authRepo: repo,
      deviceRevokeTimeout: const Duration(milliseconds: 100),
    );
    await _login(auth);

    // Without the timeout bound this call never returns and the outer timeout
    // is what fails the test.
    await auth.logout().timeout(const Duration(seconds: 10));

    expect(repo.calls, ['revoke:$kTestFcmToken', 'signOut']);
    expect(auth.isLoggedIn, isFalse);
  });

  test('logout skips the revoke when no token could be resolved', () async {
    DeviceTokenService.tokenOverride = () async => 'UNKNOWN_DEVICE_TOKEN';
    final repo = _RecordingAuthRepository();
    final auth = AuthState(authRepo: repo);
    await _login(auth);

    await auth.logout();

    expect(repo.calls, ['signOut']);
  });

  test('logout without a session does not call the revoke route', () async {
    final repo = _RecordingAuthRepository();
    final auth = AuthState(authRepo: repo);

    expect(auth.isLoggedIn, isFalse);

    await auth.logout();

    expect(repo.calls, ['signOut']);
  });
}
