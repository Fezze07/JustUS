import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

class FakePartnerRepository extends PartnershipRepository {
  FakePartnerRepository({
    required this.partnershipResponse,
    this.sendResult = const Success<void>(null),
  });

  final PartnershipResponse partnershipResponse;
  final ResultWrapper<void> sendResult;
  int partnershipFetches = 0;

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    partnershipFetches += 1;

    return Success(partnershipResponse);
  }

  @override
  Future<ResultWrapper<void>> sendPartnerRequest(
    String email,
    String partnershipCode,
  ) async {
    return sendResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('fetchPartnership stores the active partner in local cache', () async {
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(
        success: true,
        status: 'accepted',
        partner: User(id: 7, displayName: 'Alex'),
      ),
    );
    final state = PartnerState(repository: repository);

    await state.fetchPartnership();

    expect(state.partner?.id, 7);
    expect(state.partner?.username, 'Alex');
    expect(await StorageService.getPartnerId(), 7);
    expect(await StorageService.getPartnerDisplayName(), 'Alex');
  });

  test('sendPartnerRequest updates the UI message and refreshes partnership',
      () async {
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(
        success: true,
      ),
    );
    final state = PartnerState(repository: repository);

    await state.sendPartnerRequest('partner@example.com', 'ABC123');

    expect(state.message, 'Richiesta inviata a partner@example.com');
    expect(repository.partnershipFetches, 1);
  });

  test(
      'sendPartnerRequest failure does not report success and skips the refetch',
      () async {
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      sendResult: const GenericError(message: 'Codice non valido', code: 400),
    );
    final state = PartnerState(repository: repository);

    await state.sendPartnerRequest('partner@example.com', 'WRONG1');

    // A rejected request must never surface the success copy...
    expect(state.message, isNot('Richiesta inviata a partner@example.com'));
    expect(state.message, isNull);
    // ...must not trigger the follow-up partnership refresh that a successful
    // send performs...
    expect(repository.partnershipFetches, 0);
    // ...and must not leave a half-applied partner in memory or in storage.
    expect(state.partner, isNull);
    expect(await StorageService.getPartnerId(), isNull);
  });

  test('fetchPartnership failure never clobbers the persisted partner',
      () async {
    await StorageService.savePartner(7, 'Alex');
    final state = PartnerState(repository: _FailingPartnerRepository());

    await state.fetchPartnership();

    // A network error must not be mistaken for "no partnership": the in-memory
    // view stays empty and the persisted partner survives untouched.
    expect(state.partnershipInfo, isNull);
    expect(state.partner, isNull);
    expect(await StorageService.getPartnerId(), 7);
    expect(await StorageService.getPartnerDisplayName(), 'Alex');
  });
}

/// Repository whose partnership fetch always fails, to prove a network error
/// does not wipe an already-cached partner.
class _FailingPartnerRepository extends PartnershipRepository {
  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return const NetworkError();
  }
}
