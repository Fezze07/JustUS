import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

class _FakeAuthRepository extends AuthRepository {
  // ignore: close_sinks
  final StreamController<dynamic> authChanges =
      StreamController<dynamic>.broadcast();

  sb.Session? sessionToReturn;
  int signOutCalls = 0;

  @override
  sb.Session? get currentSession => sessionToReturn;

  @override
  Stream<dynamic> get onAuthStateChange => authChanges.stream;

  @override
  Future<sb.AuthResponse> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
    required String emailRedirectTo,
    required String captchaToken,
  }) async {
    return sb.AuthResponse(
      user: sb.User(
        id: 'auth-user-1',
        appMetadata: const {},
        userMetadata: const {'username': 'Mario'},
        aud: 'authenticated',
        createdAt: DateTime(2026).toIso8601String(),
        email: email,
        identities: [
          sb.UserIdentity(
            id: 'identity-1',
            userId: 'auth-user-1',
            identityData: const {},
            identityId: 'identity-1',
            provider: 'email',
            createdAt: DateTime(2026).toIso8601String(),
            lastSignInAt: null,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    sessionToReturn = null;
  }
}

sb.Session _sessionFor(String email) {
  return sb.Session(
    accessToken: 'temp-access-token',
    tokenType: 'bearer',
    user: sb.User(
      id: 'auth-user-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime(2026).toIso8601String(),
      email: email,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    installMockPathProvider();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    InstallationIdService.installationIdOverride = () async => '';
    InstallationIdService.onRegisteredOverride = const Stream.empty();
    LanguageHelper.initFromSystemLocale();
  });

  tearDown(() {
    InstallationIdService.installationIdOverride = null;
    InstallationIdService.onRegisteredOverride = null;
  });

  // ── Unit tests ────────────────────────────────────────────────────────────

  test('register saves pending signup email to storage', () async {
    final repo = _FakeAuthRepository();
    addTearDown(repo.authChanges.close);
    final authState = AuthState(
      authRepo: repo,
      captchaTokenProvider: () async => 'captcha-ok',
    );
    await authState.init();

    final registered = await authState.register(
      'mario@example.com',
      'Password1!',
      'Mario',
    );
    expect(registered, isTrue);

    final stored = await StorageService.getPendingSignupEmail();
    expect(stored, 'mario@example.com');
  });

  test(
      'warm start: signedIn event sets message, prefills email, revokes session',
      () async {
    final repo = _FakeAuthRepository();
    addTearDown(repo.authChanges.close);
    final authState = AuthState(
      authRepo: repo,
      captchaTokenProvider: () async => 'captcha-ok',
    );
    await authState.init();
    await authState.register('mario@example.com', 'Password1!', 'Mario');

    repo.authChanges.add(sb.AuthState(
      sb.AuthChangeEvent.signedIn,
      _sessionFor('mario@example.com'),
    ));
    // Let the async listener body fully execute.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(repo.signOutCalls, 1,
        reason: 'Session must be immediately revoked after confirmation');
    expect(authState.isLoggedIn, isFalse);
    expect(authState.consumePendingLoginEmail(), 'mario@example.com',
        reason: 'Confirmed email must be queued for LoginScreen prefill');
    expect(authState.message, isNotNull,
        reason: 'Success toast must be set via setMessage()');
    expect(authState.message, isNotEmpty);

    // Calling consume a second time returns null (one-shot).
    expect(authState.consumePendingLoginEmail(), isNull);

    // Pending storage must be cleared.
    expect(await StorageService.getPendingSignupEmail(), isNull);
  });

  test('cold start: initial session + pending email prefills and revokes',
      () async {
    final repo = _FakeAuthRepository();
    addTearDown(repo.authChanges.close);

    // First app run: register saves pending email.
    final firstAuth = AuthState(
      authRepo: repo,
      captchaTokenProvider: () async => 'captcha-ok',
    );
    await firstAuth.init();
    await firstAuth.register('luigi@example.com', 'Password1!', 'Luigi');

    // Simulate app relaunch from deep link: Supabase already has a session.
    repo.sessionToReturn = _sessionFor('luigi@example.com');
    final restartedAuth = AuthState(authRepo: repo);
    await restartedAuth.init();

    expect(repo.signOutCalls, 1,
        reason: 'Session must be revoked at init time');
    expect(restartedAuth.isLoggedIn, isFalse);
    expect(restartedAuth.consumePendingLoginEmail(), 'luigi@example.com');
    expect(restartedAuth.message, isNotNull);
    expect(restartedAuth.message, isNotEmpty);
    expect(await StorageService.getPendingSignupEmail(), isNull);
  });

  test('unrelated auth events do not set pending email or message', () async {
    final repo = _FakeAuthRepository();
    addTearDown(repo.authChanges.close);
    final authState = AuthState(authRepo: repo);
    await authState.init();

    repo.authChanges.add(
        const sb.AuthState(sb.AuthChangeEvent.tokenRefreshed, null));
    repo.authChanges.add(
        const sb.AuthState(sb.AuthChangeEvent.signedOut, null));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(authState.consumePendingLoginEmail(), isNull);
    expect(authState.message, isNull);
    expect(repo.signOutCalls, 0);
  });

  // ── Widget test: email controller is prefilled ────────────────────────────

  testWidgets('LoginScreen controller is prefilled from pendingLoginEmail',
      (tester) async {
    final repo = _FakeAuthRepository();
    addTearDown(repo.authChanges.close);
    final authState = AuthState(
      authRepo: repo,
      captchaTokenProvider: () async => 'captcha-ok',
    );
    await authState.init();
    await authState.register('anna@example.com', 'Password1!', 'Anna');

    // Simulate the signedIn event and wait for the async listener body.
    await tester.runAsync(() async {
      repo.authChanges.add(sb.AuthState(
        sb.AuthChangeEvent.signedIn,
        _sessionFor('anna@example.com'),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });

    // Now _pendingLoginEmail is set; mount the LoginScreen.
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: authState,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('it'),
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pump(); // initState + post-frame listeners connect

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, 'anna@example.com',
        reason: 'Email field should be prefilled from confirmed signup');
    expect(fields[1].controller?.text, isEmpty,
        reason: 'Password field must remain empty');

    // Confirm the email was consumed by the first mount — a second mount
    // must not prefill (pending email is a one-shot).
    expect(authState.consumePendingLoginEmail(), isNull,
        reason: 'pendingLoginEmail consumed by first mount');
  });
}
