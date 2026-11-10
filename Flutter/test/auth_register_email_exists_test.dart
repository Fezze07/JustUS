import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Supabase answers signUp for an already-confirmed email with a fake success
/// (`identities: []`) and sends no email. Registration must report that as a
/// failure so the screen never promises a confirmation mail that never arrives.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({required this.identities});

  final List<sb.UserIdentity>? identities;

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
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-11-04T00:00:00Z',
        email: email,
        identities: identities,
      ),
    );
  }
}

class _FakePartnershipRepository extends PartnershipRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  AuthState buildState(List<sb.UserIdentity>? identities) => AuthState(
        authRepo: _FakeAuthRepository(identities: identities),
        partnershipRepo: _FakePartnershipRepository(),
        captchaTokenProvider: () async => 'captcha-token',
      );

  test('register fails when Supabase returns an existing confirmed email',
      () async {
    final state = buildState(const []);

    final success =
        await state.register('existing@example.com', 'Password1!', 'Mario');

    expect(success, isFalse);
  });

  test('register succeeds for a brand-new account', () async {
    final state = buildState([
      const sb.UserIdentity(
        id: 'identity-1',
        userId: 'user-1',
        identityData: {},
        identityId: 'identity-1',
        provider: 'email',
        createdAt: '2026-11-04T00:00:00Z',
        lastSignInAt: null,
      ),
    ]);

    final success =
        await state.register('new@example.com', 'Password1!', 'Mario');

    expect(success, isTrue);
  });
}
