import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 19.4: a failing `signOut()` must not abort the local
/// teardown, and no invitation or partner state may survive into the next
/// account in the same process.
class _NoopAuthRepository extends AuthRepository {
  @override
  Future<void> signOut() async {}
}

class _ThrowingAuthRepository extends AuthRepository {
  @override
  Future<void> signOut() async {
    throw const NetworkError(message: 'offline');
  }
}

class _InvitationPartnershipRepository extends PartnershipRepository {
  @override
  Future<ResultWrapper<List<PartnershipInvitation>>>
      getPendingInvitations() async {
    return Success([
      PartnershipInvitation(
        id: 1,
        status: 'pending',
        createdAt: DateTime(2026),
        partnerId: 7,
        partnerDisplayName: 'Alex',
      ),
      PartnershipInvitation(
        id: 2,
        status: 'pending',
        createdAt: DateTime(2026),
        partnerId: 8,
        partnerDisplayName: 'Bea',
        isReceived: true,
      ),
    ]);
  }
}

class _ActivePartnerRepository extends PartnershipRepository {
  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return Success(PartnershipResponse(
      success: true,
      status: 'accepted',
      partnershipId: 5,
      partner: User(id: 7, displayName: 'Alex'),
    ));
  }

  @override
  Future<ResultWrapper<PartnershipCancellation?>> getCancellation() async {
    return Success(PartnershipCancellation(
      partnershipId: 5,
      partnerId: 7,
      requestedByMe: true,
    ));
  }
}

Future<void> _login(AuthState auth) => auth.setLoginData(
      accessToken: 'access-token',
      user: User(id: 1, email: 'user@example.com', displayName: 'Alex'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    installMockPathProvider();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    PartnershipRepository.clearPartnershipCache();
    InstallationIdService.installationIdOverride = () async => '';
  });

  tearDown(() {
    InstallationIdService.installationIdOverride = null;
  });

  testWidgets('a throwing signOut still clears the session and reaches login',
      (tester) async {
    final auth = AuthState(authRepo: _ThrowingAuthRepository());
    await _login(auth);
    await StorageService.saveMood('me', '😀');
    await CacheService.saveCheckpoint(
        CacheService.kMissYou, DateTime(2026).toUtc().toIso8601String());

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: auth,
        child: MaterialApp(
          initialRoute: '/main',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Scaffold(body: Text(settings.name ?? '')),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => LogoutUtils.performLogout(tester.element(find.text('/main'))),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppRoutes.login), findsOneWidget);
    expect(auth.isLoggedIn, isFalse);
    expect(await StorageService.getUserId(), isNull);
    expect(await StorageService.getMood('me'), isNull);
    expect(await CacheService.getCheckpoint(CacheService.kMissYou), isNull);
  });

  test('logout empties both invitation lists and the partner state', () async {
    final auth = AuthState(
      authRepo: _NoopAuthRepository(),
      partnershipRepo: _InvitationPartnershipRepository(),
    );
    await _login(auth);
    await auth.fetchSentInvitations();

    final partnerState = PartnerState(repository: _ActivePartnerRepository());
    await partnerState.fetchPartnership();

    // Preconditions: A's invitations and partner/cancellation are really there.
    expect(auth.sentInvitations, hasLength(1));
    expect(auth.receivedInvitations, hasLength(1));
    expect(partnerState.partner?.id, 7);
    expect(partnerState.cancellation, isNotNull);

    auth.onClearFeatureStates = partnerState.clear;

    await auth.logout();

    expect(auth.sentInvitations, isEmpty);
    expect(auth.receivedInvitations, isEmpty);
    expect(partnerState.partnershipInfo, isNull);
    expect(partnerState.partner, isNull);
    expect(partnerState.cancellation, isNull);
  });
}
