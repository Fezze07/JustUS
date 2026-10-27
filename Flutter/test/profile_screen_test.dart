import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  @override
  User? get userProfile => User(id: 1, displayName: 'Me');

  @override
  Future<void> loadProfile({bool force = false}) async {}
}

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
  }) async {
    final repository = _FakePartnerRepository(
      requestResult: requestResult ?? const Success<void>(null),
    );
    final partnerState = PartnerState(repository: repository);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileState>.value(
              value: _FakeProfileState()),
          ChangeNotifierProvider<AuthState>.value(
              value: _FakeAuthState(hasPartnerValue: hasPartner)),
          ChangeNotifierProvider<PartnerState>.value(value: partnerState),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
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
}
