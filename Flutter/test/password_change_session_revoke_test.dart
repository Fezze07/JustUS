import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 9.3: a password write has to end every *other* session
/// of the account, otherwise a refresh token copied from another device keeps
/// working after the user changed the password. The current session survives
/// (the revoke is `SignOutScope.others`), and the revoke is best-effort — the
/// password is already changed when it runs, so it must not turn a successful
/// change into a failure.
class _RecordingAuthRepository extends AuthRepository {
  _RecordingAuthRepository({
    this.onRevoke,
    this.onDeviceRevoke,
    this.reAuthError,
    this.deviceRevokeError,
  });

  final Future<void> Function()? onRevoke;
  final Future<void> Function()? onDeviceRevoke;
  final Object? reAuthError;
  final Object? deviceRevokeError;
  final List<String> calls = [];

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
  Future<sb.AuthResponse> signInWithPassword({
    required String email,
    required String password,
    required String captchaToken,
  }) async {
    calls.add('signInWithPassword');
    final error = reAuthError;
    if (error != null) throw error;
    return sb.AuthResponse(session: _session, user: _session.user);
  }

  @override
  Future<ResultWrapper<void>> changePassword(
      String currentPassword, String newPassword) async {
    calls.add('changePassword');
    return const Success(null);
  }

  @override
  Future<ResultWrapper<void>> updatePasswordWithoutCurrent(
      String newPassword) async {
    calls.add('updatePasswordWithoutCurrent');
    return const Success(null);
  }

  @override
  Future<void> revokeOtherSessions() async {
    calls.add('revokeOtherSessions');
    await onRevoke?.call();
  }

  @override
  Future<ResultWrapper<Map<String, dynamic>>> revokeOtherDeviceTokens(
      String keepDeviceToken) async {
    calls.add('revokeOtherDeviceTokens:$keepDeviceToken');
    final error = deviceRevokeError;
    if (error != null) return GenericError(message: '$error');
    await onDeviceRevoke?.call();
    return const Success(<String, dynamic>{'success': true});
  }
}

class _NoSessionAuthRepository extends _RecordingAuthRepository {
  @override
  sb.Session? get currentSession => null;
}

class _FailingChangeRepository extends _RecordingAuthRepository {
  @override
  Future<ResultWrapper<void>> changePassword(
      String currentPassword, String newPassword) async {
    calls.add('changePassword');
    return const GenericError<void>(message: 'update rejected');
  }
}

AuthState _stateWith(
  AuthRepository repository, {
  Duration sessionRevokeTimeout = const Duration(milliseconds: 100),
}) =>
    AuthState(
      authRepo: repository,
      captchaTokenProvider: () async => 'captcha-token',
      sessionRevokeTimeout: sessionRevokeTimeout,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String kKeepToken = 'fcm-token-kept-by-the-caller-0123456789';

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    DeviceTokenService.tokenOverride = () async => kKeepToken;
  });

  tearDown(() {
    DeviceTokenService.tokenOverride = null;
  });

  test('a password change signs the other sessions out', () async {
    final repo = _RecordingAuthRepository();
    final state = _stateWith(repo);

    final result = await state.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password',
    );

    expect(result, ChangePasswordResult.success);
    // The session revoke runs last, followed by the push-registration revoke:
    // the password must already be written, and each needs the session created
    // by the re-auth to stay untouched.
    expect(repo.calls, [
      'signInWithPassword',
      'changePassword',
      'revokeOtherSessions',
      'revokeOtherDeviceTokens:$kKeepToken',
    ]);
    expect(state.isLoading, isFalse);
  });

  test('the recovery flow signs the other sessions out too', () async {
    final repo = _RecordingAuthRepository();
    final state = _stateWith(repo);

    expect(await state.updatePasswordNew('new-password'), isTrue);

    expect(repo.calls, [
      'updatePasswordWithoutCurrent',
      'revokeOtherSessions',
      'revokeOtherDeviceTokens:$kKeepToken',
    ]);
  });

  test('a failed revoke never turns a successful change into a failure',
      () async {
    final repo = _RecordingAuthRepository(
      onRevoke: () async => throw const NetworkError(message: 'offline'),
    );
    final state = _stateWith(repo);

    final result = await state.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password',
    );

    expect(result, ChangePasswordResult.success);
    expect(repo.calls, contains('changePassword'));
    expect(repo.calls, contains('revokeOtherSessions'));
    expect(repo.calls, contains('revokeOtherDeviceTokens:$kKeepToken'));
    expect(state.isLoading, isFalse);
  });

  test('a revoke that never answers does not block the change', () async {
    final repo = _RecordingAuthRepository(
      onRevoke: () => Completer<void>().future,
    );
    final state = _stateWith(repo);

    // Without the timeout bound this call never returns and the outer timeout
    // is what fails the test.
    final result = await state
        .changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password',
        )
        .timeout(const Duration(seconds: 10));

    expect(result, ChangePasswordResult.success);
    expect(repo.calls, contains('revokeOtherSessions'));
    expect(repo.calls, contains('revokeOtherDeviceTokens:$kKeepToken'));
  });

  test('a failing push-registration revoke never fails the change', () async {
    final repo = _RecordingAuthRepository(
      deviceRevokeError: 'backend rejected the delete',
    );
    final state = _stateWith(repo);

    final result = await state.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password',
    );

    expect(result, ChangePasswordResult.success);
    expect(repo.calls, contains('revokeOtherDeviceTokens:$kKeepToken'));
  });

  test('a push-registration revoke that never answers does not block the change',
      () async {
    final repo =
        _RecordingAuthRepository(onDeviceRevoke: () => Completer<void>().future);
    final state = _stateWith(repo);

    final result = await state
        .changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password',
        )
        .timeout(const Duration(seconds: 10));

    expect(result, ChangePasswordResult.success);
    expect(repo.calls, contains('revokeOtherDeviceTokens:$kKeepToken'));
  });

  test('an unresolvable local token skips the revoke-all but not the sessions',
      () async {
    DeviceTokenService.tokenOverride = () async => 'UNKNOWN_DEVICE_TOKEN';
    final repo = _RecordingAuthRepository();
    final state = _stateWith(repo);

    final result = await state.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password',
    );

    expect(result, ChangePasswordResult.success);
    expect(repo.calls, [
      'signInWithPassword',
      'changePassword',
      'revokeOtherSessions',
    ]);
  });

  test('a wrong current password never reaches the revoke', () async {
    final repo = _RecordingAuthRepository(
      reAuthError: const sb.AuthException('Invalid login credentials'),
    );
    final state = _stateWith(repo);

    final result = await state.changePassword(
      currentPassword: 'wrong-password',
      newPassword: 'new-password',
    );

    expect(result, ChangePasswordResult.currentPasswordWrong);
    expect(repo.calls, ['signInWithPassword']);
  });

  test('a rejected password write never reaches the revoke', () async {
    final repo = _FailingChangeRepository();
    final state = _stateWith(repo);

    final result = await state.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password',
    );

    expect(result, ChangePasswordResult.failure);
    expect(repo.calls, ['signInWithPassword', 'changePassword']);
  });

  test('without a session nothing is written and nothing is revoked',
      () async {
    final repo = _NoSessionAuthRepository();
    final state = _stateWith(repo);

    final result = await state.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password',
    );

    expect(result, ChangePasswordResult.failure);
    expect(repo.calls, isEmpty);
  });
}
