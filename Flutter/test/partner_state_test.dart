import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

class FakePartnerRepository extends PartnershipRepository {
  FakePartnerRepository({required this.partnershipResponse});

  final PartnershipResponse partnershipResponse;
  int partnershipFetches = 0;

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    partnershipFetches += 1;

    return Success(partnershipResponse);
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
