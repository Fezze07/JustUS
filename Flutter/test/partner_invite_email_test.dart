import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for the "your partner doesn't have Just Us?" invite: the
/// state must forward the address and the platform redirect to the repository
/// and report failure without pretending the email went out.
class _FakePartnershipRepository extends PartnershipRepository {
  _FakePartnershipRepository({required this.result});

  final ResultWrapper<void> result;
  final List<String> invitedEmails = [];
  final List<String> redirects = [];

  @override
  Future<ResultWrapper<void>> inviteUnregisteredPartner(
      String email, String redirectTo) async {
    invitedEmails.add(email);
    redirects.add(redirectTo);

    return result;
  }
}

class _NoopAuthRepository extends AuthRepository {
  @override
  Future<void> signOut() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('inviteUnregisteredPartner forwards the email and the platform redirect',
      () async {
    final repository =
        _FakePartnershipRepository(result: const Success<void>(null));
    final state = AuthState(
      authRepo: _NoopAuthRepository(),
      partnershipRepo: repository,
    );

    final success = await state.inviteUnregisteredPartner('partner@example.com');

    expect(success, isTrue);
    expect(repository.invitedEmails, ['partner@example.com']);
    expect(repository.redirects, [state.emailRedirectTo]);
    expect(state.message, LanguageHelper.appLoc.partner_inviteEmailSuccess);
  });

  test('inviteUnregisteredPartner reports failure when the request fails',
      () async {
    final repository = _FakePartnershipRepository(
      result: const GenericError<void>(
        message: 'Email already registered',
        code: 409,
      ),
    );
    final state = AuthState(
      authRepo: _NoopAuthRepository(),
      partnershipRepo: repository,
    );

    final success = await state.inviteUnregisteredPartner('existing@example.com');

    expect(success, isFalse);
  });
}
