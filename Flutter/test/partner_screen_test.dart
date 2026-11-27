import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

// ---------------------------------------------------------------------------
// Strict fake repository
//
// Each test declares the full ordered sequence of responses for getPartnership
// and getCancellation. Calls are served in order; excess calls are recorded so
// verifyAllCallsConsumed() can fail the test with a clear message rather than
// relying on runSafe swallowing a thrown error.
// ---------------------------------------------------------------------------
class _FakePartnerRepository extends PartnershipRepository {
  _FakePartnerRepository({
    required List<PartnershipResponse> partnershipResponses,
    required List<PartnershipCancellation?> cancellationResponses,
    this.acceptResult =
        const Success<Map<String, dynamic>>(<String, dynamic>{'success': true}),
  })  : _partnershipQueue = List.of(partnershipResponses),
        _cancellationQueue = List.of(cancellationResponses);

  final List<PartnershipResponse> _partnershipQueue;
  final List<PartnershipCancellation?> _cancellationQueue;
  int _partnershipIdx = 0;
  int _cancellationIdx = 0;

  ResultWrapper<Map<String, dynamic>> acceptResult;
  int reverts = 0;
  int accepts = 0;

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    if (_partnershipIdx >= _partnershipQueue.length) {
      // Record the overflow; verifyAllCallsConsumed() will surface it.
      _partnershipIdx++;
      return Success(PartnershipResponse(success: false));
    }
    return Success(_partnershipQueue[_partnershipIdx++]);
  }

  @override
  Future<ResultWrapper<PartnershipCancellation?>> getCancellation() async {
    if (_cancellationIdx >= _cancellationQueue.length) {
      _cancellationIdx++;
      return const Success(null);
    }
    return Success(_cancellationQueue[_cancellationIdx++]);
  }

  @override
  Future<ResultWrapper<void>> revertCancellation(int partnershipId) async {
    reverts++;
    return const Success<void>(null);
  }

  @override
  Future<ResultWrapper<Map<String, dynamic>>> acceptCancellation(
      int partnershipId) async {
    accepts++;
    return acceptResult;
  }

  /// Assert that every queued response was consumed exactly once and that no
  /// extra calls were made. Call at the end of every test.
  void verifyAllCallsConsumed() {
    expect(
      _partnershipIdx,
      _partnershipQueue.length,
      reason: _partnershipIdx < _partnershipQueue.length
          ? 'getPartnership() was called $_partnershipIdx time(s); '
              'expected ${_partnershipQueue.length} — '
              '${_partnershipQueue.length - _partnershipIdx} response(s) unused.'
          : 'getPartnership() was called $_partnershipIdx time(s); '
              'only ${_partnershipQueue.length} response(s) queued — '
              '${_partnershipIdx - _partnershipQueue.length} unexpected call(s).',
    );
    expect(
      _cancellationIdx,
      _cancellationQueue.length,
      reason: _cancellationIdx < _cancellationQueue.length
          ? 'getCancellation() was called $_cancellationIdx time(s); '
              'expected ${_cancellationQueue.length} — '
              '${_cancellationQueue.length - _cancellationIdx} response(s) unused.'
          : 'getCancellation() was called $_cancellationIdx time(s); '
              'only ${_cancellationQueue.length} response(s) queued — '
              '${_cancellationIdx - _cancellationQueue.length} unexpected call(s).',
    );
  }
}

// ---------------------------------------------------------------------------
// Fakes for sibling providers
// ---------------------------------------------------------------------------
class _FakeAuthState extends AuthState {
  _FakeAuthState({this.loggedIn = true});

  final bool loggedIn;
  int invitationFetches = 0;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  bool get hasPartner => true;

  @override
  int? get partnershipId => 5;

  @override
  Future<void> fetchInvitations() async {
    invitationFetches += 1;
  }

  @override
  Future<void> fetchSentInvitations() async {}

  @override
  Future<void> refreshPartnershipFromRealtime() async {}
}

class _FakeProfileState extends ProfileState {
  int loads = 0;

  @override
  User? get userProfile =>
      User(id: 1, displayName: 'Me', partnershipCode: 'CODE12');

  @override
  Future<void> loadProfile({bool force = false}) async {
    loads += 1;
  }
}

// ---------------------------------------------------------------------------
// Helper: shared partner responses
// ---------------------------------------------------------------------------
PartnershipResponse _emptyPartnership() => PartnershipResponse(success: true);

PartnershipResponse _partnershipWithAlex() => PartnershipResponse(
      success: true,
      status: 'accepted',
      partnershipId: 5,
      partner: User(id: 7, displayName: 'Alex'),
    );

PartnershipCancellation _cancellationByMe() => PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      partnerDisplayName: 'Alex',
      requestedByMe: true,
    );

PartnershipCancellation _cancellationByPartner() => PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      partnerDisplayName: 'Alex',
      requestedByMe: false,
    );

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    await StorageService.saveUserId(1);
  });

  Future<void> pumpPartnerScreen(
    WidgetTester tester, {
    required _FakePartnerRepository repository,
    required PartnerState state,
    _FakeAuthState? authState,
    _FakeProfileState? profileState,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileState>.value(
              value: profileState ?? _FakeProfileState()),
          ChangeNotifierProvider<AuthState>.value(
              value: authState ?? _FakeAuthState()),
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
    // pumpAndSettle drives all postFrameCallbacks (initState fetch) and
    // any subsequent state notifications to completion.
    await tester.pumpAndSettle();
  }

  testWidgets('a signed-out screen starts no private request', (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponses: const [],
      cancellationResponses: const [],
    );
    final authState = _FakeAuthState(loggedIn: false);
    final profileState = _FakeProfileState();

    await pumpPartnerScreen(
      tester,
      repository: repository,
      state: PartnerState(repository: repository),
      authState: authState,
      profileState: profileState,
    );

    expect(profileState.loads, 0);
    expect(authState.invitationFetches, 0);
    repository.verifyAllCallsConsumed();
  });

  // -------------------------------------------------------------------------
  // T1 — I requested cancellation; I tap Restore.
  //
  // Call sequence:
  //   1. initState → fetchPartnership()           getPartnership[0] + getCancellation[0]
  //   2. revertCancellation internal fetch        getPartnership[1] + getCancellation[1]
  //   3. screen success fetch                     getPartnership[2] + getCancellation[2]
  // -------------------------------------------------------------------------
  testWidgets(
      'requested by me shows the waiting card, restore and logout only',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponses: [
        _emptyPartnership(),       // 1 — initState
        _partnershipWithAlex(),    // 2 — revert internal
        _partnershipWithAlex(),    // 3 — screen success fetch
      ],
      cancellationResponses: [
        _cancellationByMe(),       // 1 — initState
        null,                      // 2 — revert internal
        null,                      // 3 — screen success fetch
      ],
    );
    final state = PartnerState(repository: repository);

    await pumpPartnerScreen(tester, repository: repository, state: state);

    expect(
      find.text(
          'Cancellazione richiesta. In attesa che Alex approvi per continuare.'),
      findsOneWidget,
    );
    expect(find.text('Ripristina partnership'), findsOneWidget);
    expect(find.text('CODE12'), findsNothing);
    expect(find.text('Collega un partner'), findsNothing);
    expect(find.byTooltip('Accetta'), findsNothing);
    expect(find.text('Logout'), findsOneWidget);

    await tester.tap(find.text('Ripristina partnership'));
    await tester.pumpAndSettle();

    expect(repository.reverts, 1);
    expect(find.text('main-shell'), findsOneWidget);
    repository.verifyAllCallsConsumed();
  });

  // -------------------------------------------------------------------------
  // T2 — Partner requested cancellation; I tap Decline (reverts the pair).
  //
  // Call sequence:
  //   1. initState → fetchPartnership()           getPartnership[0] + getCancellation[0]
  //   2. revertCancellation internal fetch        getPartnership[1] + getCancellation[1]
  //   3. screen success fetch                     getPartnership[2] + getCancellation[2]
  // -------------------------------------------------------------------------
  testWidgets('requested by partner offers decline that restores the pair',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponses: [
        _emptyPartnership(),       // 1 — initState
        _partnershipWithAlex(),    // 2 — revert internal
        _partnershipWithAlex(),    // 3 — screen success fetch
      ],
      cancellationResponses: [
        _cancellationByPartner(),  // 1 — initState
        null,                      // 2 — revert internal
        null,                      // 3 — screen success fetch
      ],
    );
    final state = PartnerState(repository: repository);

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
    repository.verifyAllCallsConsumed();
  });

  // -------------------------------------------------------------------------
  // T3 — Partner requested cancellation; I accept (partnership ends).
  //
  // Call sequence:
  //   1. initState → fetchPartnership()           getPartnership[0] + getCancellation[0]
  //   2. acceptCancellation internal fetch        getPartnership[1] + getCancellation[1]
  //      → _teleportIfEnded fires (hadCancellation=true, now null+null)
  //        queues pushNamedAndRemoveUntil(partner)
  //   3. screen success fetch                     getPartnership[2] + getCancellation[2]
  //   4. new PartnerScreen initState (teleport)   getPartnership[3] + getCancellation[3]
  // -------------------------------------------------------------------------
  testWidgets('accept asks for confirmation and ends the partnership',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponses: [
        _emptyPartnership(),   // 1 — initState
        _emptyPartnership(),   // 2 — accept internal (partnership ended)
        _emptyPartnership(),   // 3 — screen success fetch
        _emptyPartnership(),   // 4 — new PartnerScreen initState (teleport)
      ],
      cancellationResponses: [
        _cancellationByPartner(),  // 1 — initState
        null,                      // 2 — accept internal
        null,                      // 3 — screen success fetch
        null,                      // 4 — new PartnerScreen initState (teleport)
      ],
    );
    final state = PartnerState(repository: repository);

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
    expect(find.text('Collega un partner'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    repository.verifyAllCallsConsumed();
  });

  // -------------------------------------------------------------------------
  // T4 — Accept returns a network error but the backend ended the partnership
  //       (lost-response reconciliation returns Success({ended: true})).
  //
  // Call sequence:
  //   1. initState → fetchPartnership()           getPartnership[0] + getCancellation[0]
  //   2. error path: fetchCancellation only       getCancellation[1]           (no getPartnership)
  //   3. error path: fetchPartnership             getPartnership[1] + getCancellation[2]
  //      → Success({ended:true}) returned; screen treats as success
  //   4. screen success fetch                     getPartnership[2] + getCancellation[3]
  //      → hadCancellation=false → no teleport
  // -------------------------------------------------------------------------
  testWidgets('a lost accept response shows the ended state, not an error',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponses: [
        _emptyPartnership(),   // 1 — initState
        _emptyPartnership(),   // 3 — error path fetchPartnership (ended)
        _emptyPartnership(),   // 4 — screen success fetch
      ],
      cancellationResponses: [
        _cancellationByPartner(),  // 1 — initState
        null,                      // 2 — error path fetchCancellation
        null,                      // 3 — error path fetchPartnership
        null,                      // 4 — screen success fetch
      ],
      acceptResult: const GenericError<Map<String, dynamic>>(
        details: AppError(code: ErrorCodes.apiTimeout001, message: 'Timeout'),
      ),
    );
    final state = PartnerState(repository: repository);

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
    repository.verifyAllCallsConsumed();
  });

  // -------------------------------------------------------------------------
  // T5 — Accept fails and the cancellation row is still present (clean error).
  //
  // Call sequence:
  //   1. initState → fetchPartnership()           getPartnership[0] + getCancellation[0]
  //   2. error path: fetchCancellation only       getCancellation[1]           (no getPartnership)
  //   3. error path: fetchPartnership             getPartnership[1] + getCancellation[2]
  //      → cancellation still present → returns GenericError
  //   4. screen else fetch                        getPartnership[2] + getCancellation[3]
  //      → cancellation still present → ErrorHandler.handle
  // -------------------------------------------------------------------------
  testWidgets('an accept failure that leaves the request shows the error',
      (tester) async {
    final repository = _FakePartnerRepository(
      partnershipResponses: [
        _emptyPartnership(),   // 1 — initState
        _emptyPartnership(),   // 3 — error path fetchPartnership
        _emptyPartnership(),   // 4 — screen else fetch
      ],
      cancellationResponses: [
        _cancellationByPartner(),  // 1 — initState
        _cancellationByPartner(),  // 2 — error path fetchCancellation
        _cancellationByPartner(),  // 3 — error path fetchPartnership
        _cancellationByPartner(),  // 4 — screen else fetch
      ],
      acceptResult: const GenericError<Map<String, dynamic>>(
        details: AppError(
            code: ErrorCodes.apiValidation014, message: 'Expired'),
      ),
    );
    final state = PartnerState(repository: repository);

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
    repository.verifyAllCallsConsumed();
  });
}
