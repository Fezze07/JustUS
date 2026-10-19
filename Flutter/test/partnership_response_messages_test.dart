import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Accepting/declining a partnership request must confirm the outcome through
/// the global AuthState message channel (shown by the root host).
class _FakePartnershipRepository extends PartnershipRepository {
  final List<int> accepted = [];
  final List<int> rejected = [];

  ResultWrapper<void> acceptResult = const Success<void>(null);
  ResultWrapper<void> rejectResult = const Success<void>(null);

  @override
  Future<ResultWrapper<void>> acceptPartnerRequest(int partnershipId) async {
    accepted.add(partnershipId);
    return acceptResult;
  }

  @override
  Future<ResultWrapper<void>> rejectPartnerRequest(int partnershipId) async {
    rejected.add(partnershipId);
    return rejectResult;
  }

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return Success(PartnershipResponse(success: true, status: 'accepted'));
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

  AuthState state(_FakePartnershipRepository repo) => AuthState(
        authRepo: _NoopAuthRepository(),
        partnershipRepo: repo,
      );

  test('accepting a request confirms it', () async {
    final repo = _FakePartnershipRepository();
    final auth = state(repo);

    final success = await auth.acceptInvitation(7);

    expect(success, isTrue);
    expect(repo.accepted, [7]);
    expect(auth.message, LanguageHelper.appLoc.partner_requestAccepted);
  });

  test('declining a request confirms it', () async {
    final repo = _FakePartnershipRepository();
    final auth = state(repo);

    final success = await auth.rejectInvitation(7);

    expect(success, isTrue);
    expect(repo.rejected, [7]);
    expect(auth.message, LanguageHelper.appLoc.partner_requestRejected);
  });

  test('a failed accept does not confirm success', () async {
    final repo = _FakePartnershipRepository()
      ..acceptResult = const GenericError<void>(message: 'boom', code: 500);
    final auth = state(repo);

    final success = await auth.acceptInvitation(7);

    expect(success, isFalse);
    expect(auth.message, isNot(LanguageHelper.appLoc.partner_requestAccepted));
  });
}
