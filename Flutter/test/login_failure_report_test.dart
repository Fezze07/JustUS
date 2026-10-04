import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 9.1: a rejected `signInWithPassword` has to reach the
/// backend strike engine, otherwise `loginAttempts` stays at 0, no strike level
/// is ever reached and the lockout schedule never fires. The report is
/// best-effort: whatever it does, the user must still get the credential error.
class _WrongPasswordAuthRepository extends AuthRepository {
  final List<Map<String, String?>> reports = [];
  Object? reportError;

  @override
  Future<ResultWrapper<Map<String, dynamic>>> checkLoginRisk(
      String email, String deviceFingerprint) async =>
      const Success<Map<String, dynamic>>({'success': true, 'strikeLevel': 0});

  @override
  Future<ResultWrapper<Map<String, dynamic>>> reportFailedLogin(
      String email, String deviceFingerprint, String? reason) async {
    reports.add({
      'email': email,
      'fingerprint': deviceFingerprint,
      'reason': reason,
    });

    if (reportError != null) throw reportError!;

    return const Success<Map<String, dynamic>>(
        {'success': true, 'failures': 1, 'strikeLevel': 0});
  }

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    required String captchaToken,
  }) async {
    throw const AuthException('Invalid login credentials');
  }
}

class _NoSessionAuthRepository extends _WrongPasswordAuthRepository {
  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    required String captchaToken,
  }) async {
    return AuthResponse();
  }
}

/// Captures what the error layer logs, so the assertion can name the error code
/// the user is shown instead of only "login returned false".
Future<List<String>> _capturingOutput(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

AuthState _stateWith(AuthRepository repository) => AuthState(
      authRepo: repository,
      captchaTokenProvider: () async => 'captcha-token',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('a wrong password is reported to the backend strike engine', () async {
    final repo = _WrongPasswordAuthRepository();
    final state = _stateWith(repo);

    final output = await _capturingOutput(() async {
      expect(await state.login('user@example.com', 'wrong-password'), isFalse);
    });

    expect(repo.reports, hasLength(1));
    expect(repo.reports.single['email'], 'user@example.com');
    expect(repo.reports.single['reason'], 'invalid_credentials');
    // Same key the pre-login risk check uses, otherwise the strike would be
    // recorded against a bucket the lockout never reads.
    expect(repo.reports.single['fingerprint'],
        await StorageService.getOrCreateDeviceFingerprint());

    // The user still gets the wrong-password error, not a report failure.
    expect(output.join('\n'), contains(ErrorCodes.authFailCred));
    expect(state.isLoading, isFalse);
    expect(state.isLoggedIn, isFalse);
  });

  test('a failed report never replaces the credential error', () async {
    final repo = _WrongPasswordAuthRepository()
      ..reportError = const NetworkError(message: 'offline');
    final state = _stateWith(repo);

    final output = await _capturingOutput(() async {
      expect(await state.login('user@example.com', 'wrong-password'), isFalse);
    });

    expect(repo.reports, hasLength(1));
    final logged = output.join('\n');
    expect(logged, contains(ErrorCodes.authFailCred));
    expect(logged, isNot(contains(ErrorCodes.localNetworkError)));
  });

  test('a response without a session is reported too', () async {
    final repo = _NoSessionAuthRepository();
    final state = _stateWith(repo);

    final output = await _capturingOutput(() async {
      expect(await state.login('user@example.com', 'any-password'), isFalse);
    });

    expect(repo.reports, hasLength(1));
    expect(repo.reports.single['reason'], 'no_user_data');
    expect(output.join('\n'), contains(ErrorCodes.authFailCred));
  });
}