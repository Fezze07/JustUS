import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

// Regression tests for 25.1: `MainShell` must only redirect to
// `PartnerScreen` while the user is authenticated, and must revalidate that
// state inside the post-frame callback so a scheduled redirect can never
// override logout navigation.
class _NoopAuthRepository extends AuthRepository {
  @override
  Future<void> signOut() async {}
}

class _NoopProfileState extends ProfileState {
  @override
  Future<void> loadProfile({bool force = false}) async {}

  @override
  User? get userProfile => User(id: 1, displayName: 'Me');
}

class _NoopHomepageState extends HomepageState {
  @override
  Future<void> init() async {}
}

class _NoopMoodState extends MoodState {
  @override
  Future<void> initHome() async {}
}

class _NoopBucketState extends BucketState {
  @override
  Future<void> init() async {}
}

/// Exposes mutable auth flags so a test can clear the session between the
/// build that schedules the redirect and the callback that would run it.
class _TogglableAuthState extends AuthState {
  bool loggedIn = true;
  bool partnerLinked = false;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  bool get hasPartner => partnerLinked;
}

Future<void> _login(AuthState auth) => auth.setLoginData(
      accessToken: 'access-token',
      user: User(id: 1, email: 'user@example.com', displayName: 'Me'),
    );

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// HomepageScreen runs a repeating pulse animation, so `pumpAndSettle` never
/// settles. Pump a fixed number of frames instead.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(AuthState auth, {Widget? home}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthState>.value(value: auth),
      ChangeNotifierProvider<PartnerState>(create: (_) => PartnerState()),
      ChangeNotifierProvider<ProfileState>(create: (_) => _NoopProfileState()),
      ChangeNotifierProvider<HomepageState>(create: (_) => _NoopHomepageState()),
      ChangeNotifierProvider<MoodState>(create: (_) => _NoopMoodState()),
      ChangeNotifierProvider<BucketState>(create: (_) => _NoopBucketState()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      navigatorKey: ErrorHandler.navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('it'),
      home: home,
      initialRoute: home == null ? AppRoutes.mainShell : null,
      routes: {
        AppRoutes.mainShell: (_) => const MainShell(),
        AppRoutes.login: (_) => const Scaffold(body: Text('login-route')),
        AppRoutes.partner: (_) => const Scaffold(body: Text('partner-route')),
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
    PackageInfo.setMockInitialValues(
      appName: 'JustUS',
      packageName: 'com.fezze.justus',
      version: '2.0.0',
      buildNumber: '10',
      buildSignature: '',
    );
  });

  tearDown(() {
    InstallationIdService.installationIdOverride = null;
  });

  testWidgets('logging out from ProfileScreen ends on Login, never Partner',
      (tester) async {
    _useLargeSurface(tester);
    final auth = AuthState(authRepo: _NoopAuthRepository());
    await _login(auth);
    await auth.setPartner(partnerId: 7, displayName: 'Alex', partnershipId: 5);

    await tester.pumpWidget(_app(auth));
    await _pumpFrames(tester);

    tester.state<MainShellState>(find.byType(MainShell)).switchToTab(6);
    await _pumpFrames(tester);

    // The tile's action is `LogoutUtils.performLogout` with this screen's
    // context; invoke it directly so the real-async teardown can run.
    expect(find.text('DISCONNETTI SESSIONE'), findsOneWidget);
    final profileContext = tester.element(find.byType(ProfileScreen));
    await tester.runAsync(
        () => LogoutUtils.performLogout(profileContext));
    await _pumpFrames(tester);

    expect(find.text('login-route'), findsOneWidget);
    expect(find.text('partner-route'), findsNothing);
    expect(auth.isLoggedIn, isFalse);
  });

  testWidgets('an authenticated user who loses the partner lands on Partner',
      (tester) async {
    _useLargeSurface(tester);
    final auth = AuthState(authRepo: _NoopAuthRepository());
    await _login(auth);
    await auth.setPartner(partnerId: 7, displayName: 'Alex', partnershipId: 5);

    await tester.pumpWidget(_app(auth));
    await _pumpFrames(tester);

    expect(find.byType(MainShell), findsOneWidget);

    await auth.syncPartnership(PartnershipResponse(success: true));
    await _pumpFrames(tester);

    expect(find.text('partner-route'), findsOneWidget);
  });

  testWidgets('a redirect scheduled before logout cannot run after it',
      (tester) async {
    _useLargeSurface(tester);
    final auth = _TogglableAuthState();
    await _login(auth);

    await tester.pumpWidget(
      _app(auth, home: const Scaffold(body: Text('boot'))),
    );

    // Flip the session off in a callback registered before the frame that
    // builds MainShell: its redirect callback is registered during that build,
    // so it must observe the logged-out state when it finally runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      auth.loggedIn = false;
    });
    unawaited(ErrorHandler.navigatorKey.currentState!
        .pushNamed(AppRoutes.mainShell));
    await _pumpFrames(tester, 8);

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.text('partner-route'), findsNothing);
  });
}
