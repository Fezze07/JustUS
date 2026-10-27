import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

class FakePartnerRepository extends PartnershipRepository {
  FakePartnerRepository({
    required this.partnershipResponse,
    this.cancellation,
    this.acceptResult =
        const NetworkError<Map<String, dynamic>>(),
  });

  PartnershipResponse partnershipResponse;
  PartnershipCancellation? cancellation;
  ResultWrapper<Map<String, dynamic>> acceptResult;
  int partnershipFetches = 0;
  int cancellationFetches = 0;

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    partnershipFetches += 1;

    return Success(partnershipResponse);
  }

  @override
  Future<ResultWrapper<PartnershipCancellation?>> getCancellation() async {
    cancellationFetches += 1;

    return Success(cancellation);
  }

  @override
  Future<ResultWrapper<Map<String, dynamic>>> acceptCancellation(
      int partnershipId) async {
    return acceptResult;
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
    expect(state.cancellation, isNull);
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

  test('fetchPartnership exposes a cancellation requested by me', () async {
    final cancellation = PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      partnerDisplayName: 'Alex',
      requestedByMe: true,
    );
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      cancellation: cancellation,
    );
    final state = PartnerState(repository: repository);

    await state.fetchPartnership();

    expect(state.partner, isNull);
    expect(state.cancellation, same(cancellation));
    expect(await StorageService.getPartnerId(), isNull);
  });

  test('fetchPartnership exposes a cancellation requested by the partner',
      () async {
    final cancellation = PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      partnerDisplayName: 'Alex',
      requestedByMe: false,
    );
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      cancellation: cancellation,
    );
    final state = PartnerState(repository: repository);

    await state.fetchPartnership();

    expect(state.partner, isNull);
    expect(state.cancellation?.requestedByMe, isFalse);
  });

  test('a deleted partnership clears the cancellation and the partner cache',
      () async {
    final cancellation = PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      requestedByMe: true,
    );
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(
        success: true,
        status: 'accepted',
        partner: User(id: 7, displayName: 'Alex'),
      ),
    );
    final state = PartnerState(repository: repository);

    await state.fetchPartnership();
    repository.partnershipResponse = PartnershipResponse(success: true);
    repository.cancellation = cancellation;
    await state.fetchPartnership();

    expect(state.cancellation, same(cancellation));

    repository.cancellation = null;
    await state.refreshFromRealtime();

    expect(state.partner, isNull);
    expect(state.cancellation, isNull);
    expect(await StorageService.getPartnerId(), isNull);
    expect(await StorageService.getPartnershipId(), isNull);
  });

  test('a lost accept response reports the deleted row as ended', () async {
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
    );
    final state = PartnerState(repository: repository);

    final result = await state.acceptCancellation(5);

    expect(result, isA<Success<Map<String, dynamic>>>());
    expect((result as Success<Map<String, dynamic>>).value['ended'], isTrue);
    expect(state.cancellation, isNull);
  });

  test('an expired accept returns the error and keeps the accepted pair',
      () async {
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(
        success: true,
        status: 'accepted',
        partner: User(id: 7, displayName: 'Alex'),
      ),
      acceptResult: const GenericError<Map<String, dynamic>>(
        details: AppError(
          code: ErrorCodes.apiValidation014,
          message: 'Expired',
        ),
      ),
    );
    final state = PartnerState(repository: repository);

    final result = await state.acceptCancellation(5);

    expect(result, isA<GenericError<Map<String, dynamic>>>());
    expect(state.cancellation, isNull);
    expect(state.partner?.id, 7);
  });

  testWidgets('an accepted cancellation teleports from a pushed route',
      (tester) async {
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(
        success: true,
        status: 'accepted',
        partner: User(id: 7, displayName: 'Alex'),
      ),
    );
    final state = PartnerState(repository: repository);

    await state.fetchPartnership();
    repository.partnershipResponse = PartnershipResponse(success: true);
    await state.fetchPartnership();
    repository.cancellation = PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      requestedByMe: true,
    );
    await state.fetchCancellation();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: ErrorHandler.navigatorKey,
      initialRoute: '/main',
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(body: Text(settings.name ?? '')),
      ),
    ));
    ErrorHandler.navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/media'),
      builder: (_) => const Scaffold(body: Text('/media')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('/media'), findsOneWidget);

    repository.cancellation = null;
    await state.refreshFromRealtime();
    await tester.pumpAndSettle();

    expect(find.text(AppRoutes.partner), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a still-pending cancellation does not teleport', (tester) async {
    final repository = FakePartnerRepository(
      partnershipResponse: PartnershipResponse(
        success: true,
        status: 'accepted',
        partner: User(id: 7, displayName: 'Alex'),
      ),
    );
    final state = PartnerState(repository: repository);

    await state.fetchPartnership();
    repository.partnershipResponse = PartnershipResponse(success: true);
    repository.cancellation = PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      requestedByMe: false,
    );
    await state.refreshFromRealtime();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: ErrorHandler.navigatorKey,
      initialRoute: '/main',
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(body: Text(settings.name ?? '')),
      ),
    ));
    ErrorHandler.navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/media'),
      builder: (_) => const Scaffold(body: Text('/media')),
    ));
    await tester.pumpAndSettle();

    await state.refreshFromRealtime();
    await tester.pumpAndSettle();

    expect(find.text('/media'), findsOneWidget);
    expect(find.text(AppRoutes.partner), findsNothing);
  });
}

/// Repository whose partnership fetch always fails, to prove a network error
/// does not wipe an already-cached partner.
class _FailingPartnerRepository extends PartnershipRepository {
  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return const NetworkError();
  }

  @override
  Future<ResultWrapper<PartnershipCancellation?>> getCancellation() async {
    return const Success<PartnershipCancellation?>(null);
  }
}
