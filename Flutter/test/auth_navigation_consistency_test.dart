import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

class _SequencePartnerRepository extends PartnershipRepository {
  _SequencePartnerRepository(this.responses);

  final List<ResultWrapper<PartnershipResponse>> responses;
  int _index = 0;

  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    final res = responses[_index < responses.length ? _index : responses.length - 1];
    _index++;
    return res;
  }

  @override
  Future<ResultWrapper<PartnershipCancellation?>> getCancellation() async =>
      const Success<PartnershipCancellation?>(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  testWidgets(
    'login-time partnership failure followed by route-time success reconciles AuthState and PartnerState on MainShell',
    (tester) async {
      final partner = User(id: 77, displayName: 'Claretta');
      final repo = _SequencePartnerRepository([
        const NetworkError<PartnershipResponse>(),
        Success(PartnershipResponse(
          success: true,
          partnershipId: 9001,
          status: 'accepted',
          partner: partner,
        )),
      ]);

      final authState = AuthState(partnershipRepo: repo);
      final partnerState = PartnerState(repository: repo);

      await authState.setLoginData(
        accessToken: 'jwt-token',
        user: User(id: 42, displayName: 'Fede'),
      );
      // Login-time lookup fails -> AuthState.hasPartner remains false.
      await authState.syncPartnership((await repo.getPartnership()).valueOrNull);
      expect(authState.hasPartner, isFalse);

      late String resolvedRoute;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>.value(value: authState),
            ChangeNotifierProvider<PartnerState>.value(value: partnerState),
          ],
          child: MaterialApp(
            navigatorKey: ErrorHandler.navigatorKey,
            routes: {
              AppRoutes.mainShell: (context) {
                final hasPartner =
                    context.select<AuthState, bool>((a) => a.hasPartner);
                if (!hasPartner) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Navigator.of(context)
                        .pushReplacementNamed(AppRoutes.partner);
                  });
                }
                return const Scaffold(body: Text('MainShell'));
              },
              AppRoutes.partner: (_) =>
                  const Scaffold(body: Text('PartnerScreen')),
            },
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  resolvedRoute =
                      await AuthNavigationUtils.determinePostAuthRouteName(
                          context);
                  if (!context.mounted) return;
                  await Navigator.of(context)
                      .pushReplacementNamed(resolvedRoute);
                },
                child: const Text('Route'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Route'));
      await tester.pumpAndSettle();

      expect(resolvedRoute, AppRoutes.mainShell);
      expect(authState.hasPartner, isTrue);
      expect(authState.partnerId, 77);
      expect(authState.partnershipId, 9001);
      expect(partnerState.partner?.id, 77);
      expect(find.text('MainShell'), findsOneWidget);
      expect(find.text('PartnerScreen'), findsNothing);
    },
  );

  testWidgets(
    'failed route-time lookup does not clear an already known partner',
    (tester) async {
      final repo = _SequencePartnerRepository([
        const NetworkError<PartnershipResponse>(),
      ]);
      final authState = AuthState(partnershipRepo: repo);
      final partnerState = PartnerState(repository: repo);

      await authState.setLoginData(
        accessToken: 'jwt-token',
        user: User(id: 42, displayName: 'Fede'),
      );
      await authState.setPartner(
        partnerId: 77,
        displayName: 'Claretta',
        partnershipId: 9001,
      );

      late String resolvedRoute;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>.value(value: authState),
            ChangeNotifierProvider<PartnerState>.value(value: partnerState),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  resolvedRoute =
                      await AuthNavigationUtils.determinePostAuthRouteName(
                          context);
                },
                child: const Text('Route'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Route'));
      await tester.pumpAndSettle();

      expect(resolvedRoute, AppRoutes.mainShell);
      expect(authState.hasPartner, isTrue);
    },
  );

  testWidgets(
    'successful route-time lookup with no partner clears stale AuthState and routes to PartnerScreen',
    (tester) async {
      final repo = _SequencePartnerRepository([
        Success(PartnershipResponse(success: true)),
      ]);
      final authState = AuthState(partnershipRepo: repo);
      final partnerState = PartnerState(repository: repo);

      await authState.setLoginData(
        accessToken: 'jwt-token',
        user: User(id: 42, displayName: 'Fede'),
      );
      await authState.setPartner(
        partnerId: 77,
        displayName: 'Claretta',
        partnershipId: 9001,
      );

      late String resolvedRoute;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>.value(value: authState),
            ChangeNotifierProvider<PartnerState>.value(value: partnerState),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  resolvedRoute =
                      await AuthNavigationUtils.determinePostAuthRouteName(
                          context);
                },
                child: const Text('Route'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Route'));
      await tester.pumpAndSettle();

      expect(resolvedRoute, AppRoutes.partner);
      expect(authState.hasPartner, isFalse);
      expect(partnerState.partner, isNull);
    },
  );
}
