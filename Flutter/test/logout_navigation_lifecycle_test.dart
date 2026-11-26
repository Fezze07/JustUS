import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

// Regression test for 25.2: logout navigation must not depend on the
// lifecycle of the BuildContext that started the teardown.
class _ControllableLogoutAuthState extends AuthState {
  final Completer<void> teardownStarted = Completer<void>();
  final Completer<void> teardownGate = Completer<void>();
  bool loggedIn = true;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<void> logout() async {
    teardownStarted.complete();
    await teardownGate.future;
    loggedIn = false;
    notifyListeners();
  }
}

Widget _app(AuthState auth) {
  return ChangeNotifierProvider<AuthState>.value(
    value: auth,
    child: MaterialApp(
      navigatorKey: ErrorHandler.navigatorKey,
      initialRoute: '/caller',
      routes: {
        '/caller': (_) => const Scaffold(body: Text('caller-route')),
        '/other': (_) => const Scaffold(body: Text('other-route')),
        AppRoutes.login: (_) => const Scaffold(body: Text('login-route')),
      },
    ),
  );
}

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

  testWidgets(
      'logout reaches Login when the calling screen is disposed mid-teardown',
      (tester) async {
    final auth = _ControllableLogoutAuthState();
    await tester.pumpWidget(_app(auth));

    final navigator = ErrorHandler.navigatorKey.currentState!;
    final callerContext = tester.element(find.text('caller-route'));

    final logout = LogoutUtils.performLogout(callerContext);
    await tester.pump();
    expect(auth.teardownStarted.isCompleted, isTrue);

    // Replace the calling route while the teardown is still pending, so the
    // original BuildContext is unmounted before navigation happens.
    navigator.pushReplacementNamed('/other');
    await tester.pumpAndSettle();
    expect(find.text('caller-route'), findsNothing);
    expect(callerContext.mounted, isFalse);

    auth.teardownGate.complete();
    await logout;
    await tester.pumpAndSettle();

    expect(find.text('login-route'), findsOneWidget);
    expect(find.text('other-route'), findsNothing);
    expect(auth.loggedIn, isFalse);
  });
}
