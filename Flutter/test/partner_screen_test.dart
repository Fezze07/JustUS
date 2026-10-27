import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

class _FakePartnerRepository extends PartnershipRepository {
  _FakePartnerRepository({
    required this.partnershipResponse,
    this.cancellation,
    this.acceptResult =
        const Success<Map<String, dynamic>>(<String, dynamic>{'success': true}),
    this.afterAccept,
  });

  PartnershipResponse partnershipResponse;
  PartnershipCancellation? cancellation;
  ResultWrapper<Map<String, dynamic>> acceptResult;
  void Function(_FakePartnerRepository repo)? afterAccept;
  int reverts = 0;
  int accepts = 0;

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return Success(partnershipResponse);
  }

  @override
  Future<ResultWrapper<PartnershipCancellation?>> getCancellation() async {
    return Success(cancellation);
  }

  @override
  Future<ResultWrapper<void>> revertCancellation(int partnershipId) async {
    reverts += 1;
    cancellation = null;
    partnershipResponse = PartnershipResponse(
      success: true,
      status: 'accepted',
      partnershipId: 5,
      partner: User(id: 7, displayName: 'Alex'),
    );
    return const Success<void>(null);
  }

  @override
  Future<ResultWrapper<Map<String, dynamic>>> acceptCancellation(
      int partnershipId) async {
    accepts += 1;
    afterAccept?.call(this);
    return acceptResult;
  }
}

class _FakeAuthState extends AuthState {
  @override
  bool get hasPartner => true;

  @override
  int? get partnershipId => 5;

  @override
  Future<void> fetchSentInvitations() async {}

  @override
  Future<void> fetchReceivedInvitations() async {}

  @override
  Future<void> refreshPartnershipFromRealtime() async {}
}

class _FakeProfileState extends ProfileState {
  @override
  User? get userProfile =>
      User(id: 1, displayName: 'Me', partnershipCode: 'CODE12');

  @override
  Future<void> loadProfile({bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  Future<void> pumpPartnerScreen(
    WidgetTester tester, {
    required _FakePartnerRepository repository,
    required PartnerState state,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileState>.value(
              value: _FakeProfileState()),
          ChangeNotifierProvider<AuthState>.value(value: _FakeAuthState()),
          ChangeNotifierProvider<PartnerState>.value(value: state),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          navigatorKey: ErrorHandler.navigatorKey,
          home: const PartnerScreen(),
          routes: {
            AppRoutes.mainShell: (_) =>
                const Scaffold(body: Text('main-shell')),
            AppRoutes.partner: (_) => const PartnerScreen(),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('requested by me shows the waiting card, restore and logout only',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      cancellation: PartnershipCancellation(
        partnershipId: 5,
        partnerId: 7,
        partnerDisplayName: 'Alex',
        requestedByMe: true,
      ),
    );
    final state = PartnerState(repository: repository);
    await state.fetchPartnership();

    await pumpPartnerScreen(tester, repository: repository, state: state);

    expect(
      find.text(
          'Cancellazione richiesta. In attesa che Alex approvi per continuare.'),
      findsOneWidget,
    );
    expect(find.text('Ripristina partnership'), findsOneWidget);
    expect(find.text('CODE12'), findsNothing);
    expect(find.text('Nuova connessione'), findsNothing);
    expect(find.byTooltip('Accetta'), findsNothing);
    expect(find.text('Logout'), findsOneWidget);

    await tester.tap(find.text('Ripristina partnership'));
    await tester.pumpAndSettle();

    expect(repository.reverts, 1);
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('requested by partner offers decline that restores the pair',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      cancellation: PartnershipCancellation(
        partnershipId: 5,
        partnerId: 7,
        partnerDisplayName: 'Alex',
        requestedByMe: false,
      ),
    );
    final state = PartnerState(repository: repository);
    await state.fetchPartnership();

    await pumpPartnerScreen(tester, repository: repository, state: state);

    expect(
      find.text('Alex ha chiesto di interrompere la partnership'),
      findsOneWidget,
    );
    expect(find.text('Cancellazione partnership'), findsOneWidget);
    expect(find.text('Ripristina partnership'), findsNothing);
    expect(find.byTooltip('Accetta'), findsOneWidget);

    await tester.tap(find.byTooltip('Rifiuta'));
    await tester.pumpAndSettle();

    expect(repository.reverts, 1);
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('accept asks for confirmation and ends the partnership',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      cancellation: PartnershipCancellation(
        partnershipId: 5,
        partnerId: 7,
        partnerDisplayName: 'Alex',
        requestedByMe: false,
      ),
      afterAccept: (repo) {
        repo.cancellation = null;
        repo.partnershipResponse = PartnershipResponse(success: true);
      },
    );
    final state = PartnerState(repository: repository);
    await state.fetchPartnership();

    await pumpPartnerScreen(tester, repository: repository, state: state);

    await tester.tap(find.byTooltip('Accetta'));
    await tester.pumpAndSettle();

    expect(find.text('Interrompi la partnership'), findsOneWidget);
    expect(
      find.text(
          'Tutti i dati condivisi verranno eliminati. L\'azione è definitiva.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Accetta'));
    await tester.pumpAndSettle();

    expect(repository.accepts, 1);
    expect(
      find.text(
          'Partnership interrotta. Tutti i dati condivisi sono stati eliminati.'),
      findsOneWidget,
    );
    expect(find.text('Nuova connessione'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a lost accept response shows the ended state, not an error',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      cancellation: PartnershipCancellation(
        partnershipId: 5,
        partnerId: 7,
        partnerDisplayName: 'Alex',
        requestedByMe: false,
      ),
      acceptResult: const GenericError<Map<String, dynamic>>(
        details: AppError(code: ErrorCodes.apiTimeout001, message: 'Timeout'),
      ),
      afterAccept: (repo) {
        repo.cancellation = null;
        repo.partnershipResponse = PartnershipResponse(success: true);
      },
    );
    final state = PartnerState(repository: repository);
    await state.fetchPartnership();

    await pumpPartnerScreen(tester, repository: repository, state: state);

    await tester.tap(find.byTooltip('Accetta'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Accetta'));
    await tester.pumpAndSettle();

    expect(repository.accepts, 1);
    expect(
      find.text(
          'Partnership interrotta. Tutti i dati condivisi sono stati eliminati.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an accept failure that leaves the request shows the error',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponse: PartnershipResponse(success: true),
      cancellation: PartnershipCancellation(
        partnershipId: 5,
        partnerId: 7,
        partnerDisplayName: 'Alex',
        requestedByMe: false,
      ),
      acceptResult: const GenericError<Map<String, dynamic>>(
        details: AppError(
            code: ErrorCodes.apiValidation014, message: 'Expired'),
      ),
    );
    final state = PartnerState(repository: repository);
    await state.fetchPartnership();

    await pumpPartnerScreen(tester, repository: repository, state: state);

    await tester.tap(find.byTooltip('Accetta'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Accetta'));
    await tester.pumpAndSettle();

    expect(
      find.text('Alex ha chiesto di interrompere la partnership'),
      findsOneWidget,
    );
    expect(find.textContaining('API-VALIDATION-014'), findsOneWidget);
  });
}
