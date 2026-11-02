import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

class _FakePartnerRepository extends PartnershipRepository {
  _FakePartnerRepository({required this.requestResult});

  ResultWrapper<void> requestResult;
  int requests = 0;

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return Success(PartnershipResponse(success: true));
  }

  @override
  Future<ResultWrapper<PartnershipCancellation?>> getCancellation() async {
    return const Success<PartnershipCancellation?>(null);
  }

  @override
  Future<ResultWrapper<void>> requestCancellation(int partnershipId) async {
    requests += 1;
    return requestResult;
  }
}

class _FakeAuthState extends AuthState {
  _FakeAuthState({required this.hasPartnerValue});

  final bool hasPartnerValue;

  @override
  bool get hasPartner => hasPartnerValue;

  @override
  int? get partnershipId => 5;

  @override
  Future<void> refreshPartnershipFromRealtime() async {}
}

class _FakeProfileState extends ProfileState {
  bool wipeResult = true;
  int wipeCalls = 0;

  @override
  User? get userProfile => User(id: 1, displayName: 'Me');

  @override
  Future<void> loadProfile({bool force = false}) async {}

  @override
  Future<bool> wipeAppData() async {
    wipeCalls += 1;
    return wipeResult;
  }
}

class _MockRealtimeSyncService extends Mock implements RealtimeSyncService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    await StorageService.saveAppVersion('v1.0.0');
  });

  Future<(_FakePartnerRepository, PartnerState)> pumpProfile(
    WidgetTester tester, {
    required bool hasPartner,
    ResultWrapper<void>? requestResult,
    _FakeProfileState? profileState,
    _MockRealtimeSyncService? realtime,
  }) async {
    final repository = _FakePartnerRepository(
      requestResult: requestResult ?? const Success<void>(null),
    );
    final partnerState = PartnerState(repository: repository);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileState>.value(
              value: profileState ?? _FakeProfileState()),
          ChangeNotifierProvider<AuthState>.value(
              value: _FakeAuthState(hasPartnerValue: hasPartner)),
          ChangeNotifierProvider<PartnerState>.value(value: partnerState),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          Provider<RealtimeSyncService>.value(
              value: realtime ?? _MockRealtimeSyncService()),
          ChangeNotifierProvider<GameState>.value(value: GameState()),
          ChangeNotifierProvider<BucketState>.value(value: BucketState()),
          ChangeNotifierProvider<DriveState>.value(value: DriveState()),
          ChangeNotifierProvider<MoodState>.value(value: MoodState()),
          ChangeNotifierProvider<HomepageState>.value(value: HomepageState()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          navigatorKey: ErrorHandler.navigatorKey,
          home: const ProfileScreen(),
          routes: {
            AppRoutes.partner: (_) =>
                const Scaffold(body: Text('partner-route')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    return (repository, partnerState);
  }

  Future<void> tapCancellationButton(WidgetTester tester) async {
    final button = find.text('RICHIEDI LA CANCELLAZIONE DELLA PARTNERSHIP');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> tapWipeButton(WidgetTester tester) async {
    final button = find.text('Cancella dati app');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('the cancellation button is hidden without a partner',
      (tester) async {
    await pumpProfile(tester, hasPartner: false);

    expect(find.text('RICHIEDI LA CANCELLAZIONE DELLA PARTNERSHIP'),
        findsNothing);
  });

  testWidgets('the button opens a simple confirmation dialog', (tester) async {
    await pumpProfile(tester, hasPartner: true);

    await tapCancellationButton(tester);

    expect(find.text('Richiedi la cancellazione della partnership'),
        findsOneWidget);
    expect(
      find.text(
          'Il tuo partner deve approvare. L\'app resterà in pausa fino ad allora.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Richiedi cancellazione'),
        findsOneWidget);
  });

  testWidgets('a confirmed request lands on PartnerScreen', (tester) async {
    final (repository, _) = await pumpProfile(tester, hasPartner: true);

    await tapCancellationButton(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Richiedi cancellazione'));
    await tester.pumpAndSettle();

    expect(repository.requests, 1);
    expect(find.text('partner-route'), findsOneWidget);
    expect(find.text('Cancellazione richiesta'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a cooldown failure stays on Profile and shows the error',
      (tester) async {
    final (repository, _) = await pumpProfile(
      tester,
      hasPartner: true,
      requestResult: const GenericError<void>(
        details: AppError(
          code: ErrorCodes.apiValidation013,
          message: 'Cooldown',
        ),
      ),
    );

    await tapCancellationButton(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Richiedi cancellazione'));
    await tester.pumpAndSettle();

    expect(repository.requests, 1);
    expect(find.text('partner-route'), findsNothing);
    expect(find.textContaining('API-VALIDATION-013'), findsOneWidget);
  });

  testWidgets('a failed wipe resumes realtime processing', (tester) async {
    final profile = _FakeProfileState()..wipeResult = false;
    final realtime = _MockRealtimeSyncService();
    when(() => realtime.suppress()).thenReturn(null);
    when(() => realtime.resume(refresh: any(named: 'refresh')))
        .thenReturn(null);
    when(() => realtime.refreshChannel()).thenAnswer((_) async {});

    await pumpProfile(
      tester,
      hasPartner: true,
      profileState: profile,
      realtime: realtime,
    );
    await tapWipeButton(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CANCELLA TUTTO'));
    await tester.pumpAndSettle();

    expect(profile.wipeCalls, 1);
    verify(() => realtime.suppress()).called(1);
    verify(() => realtime.resume()).called(1);
    verifyNever(() => realtime.refreshChannel());
  });

  testWidgets('a successful wipe still refreshes the channel', (tester) async {
    final profile = _FakeProfileState()..wipeResult = true;
    final realtime = _MockRealtimeSyncService();
    when(() => realtime.suppress()).thenReturn(null);
    when(() => realtime.resume(refresh: any(named: 'refresh')))
        .thenReturn(null);
    when(() => realtime.refreshChannel()).thenAnswer((_) async {});

    await pumpProfile(
      tester,
      hasPartner: true,
      profileState: profile,
      realtime: realtime,
    );
    await tapWipeButton(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CANCELLA TUTTO'));
    await tester.pumpAndSettle();

    expect(profile.wipeCalls, 1);
    verify(() => realtime.suppress()).called(1);
    verify(() => realtime.refreshChannel()).called(1);
    verifyNever(() => realtime.resume(refresh: any(named: 'refresh')));
  });
}
