import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/source_scan.dart';

class MockHttpClient extends Mock implements http.Client {}

/// Returns a canned result, so `UpdateService`'s own decision logic is
/// exercised without a network round trip.
class _FakeVersionRepository extends VersionRepository {
  _FakeVersionRepository(this._result);

  final ResultWrapper<AppVersionResponse> _result;

  int checkAppVersionCalls = 0;

  @override
  Future<ResultWrapper<AppVersionResponse>> checkAppVersion() async {
    checkAppVersionCalls++;
    return _result;
  }
}

/// The dialog's own barrier. A modal route builds an `AnimatedModalBarrier`,
/// a `ModalBarrier` subclass, so `find.byType` (exact runtime type) misses it.
ModalBarrier _dialogBarrier(WidgetTester tester) => tester
    .widgetList<ModalBarrier>(
        find.byWidgetPredicate((widget) => widget is ModalBarrier))
    .last;

/// `PopScope` is created without an explicit type argument, so its runtime type
/// is `PopScope<dynamic>` and `find.byType(PopScope<void>)` misses it too.
PopScope<dynamic> _dialogPopScope(WidgetTester tester) => tester
    .widgetList<PopScope<dynamic>>(
        find.byWidgetPredicate((widget) => widget is PopScope))
    .last;

AppVersionResponse _version({
  required int build,
  required int minBuild,
  bool forceUpdate = false,
  String apkUrl = 'https://example.test/justus.apk',
  String changelog = 'Fixed the thing',
}) {
  return AppVersionResponse(
    version: '2.0.0',
    build: build,
    minBuild: minBuild,
    forceUpdate: forceUpdate,
    apkUrl: apkUrl,
    changelog: changelog,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final launchedUrls = <String>[];

  late _FakeVersionRepository repo;
  late UpdateService service;
  late BuildContext checkContext;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    ApiService.clearHeadersCache();
    launchedUrls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
      if (call.method == 'canLaunch' || call.method == 'supportsMode') {
        return true;
      }
      if (call.method == 'launch') {
        launchedUrls.add((call.arguments as Map)['url'] as String);
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, null);
  });

  /// Pumps an app whose only action runs the real `UpdateService.checkVersion`
  /// against a real `BuildContext` — what both call sites do.
  Future<void> pumpCheck(
    WidgetTester tester, {
    required ResultWrapper<AppVersionResponse> result,
    required String localBuild,
    bool showNoUpdateToast = false,
  }) async {
    PackageInfo.setMockInitialValues(
      appName: 'JustUs',
      packageName: 'com.fezze.justus',
      version: '1.0.0',
      buildNumber: localBuild,
      buildSignature: '',
    );

    repo = _FakeVersionRepository(result);
    service = UpdateService(repository: repo);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              checkContext = context;
              return TextButton(
                onPressed: () => service.checkVersion(
                  context,
                  showNoUpdateToast: showNoUpdateToast,
                ),
                child: const Text('check'),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> runCheck(WidgetTester tester) async {
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
  }

  /// The non-error toast schedules its own 4s auto-removal, which
  /// `testWidgets` fails on if it is still pending at teardown. Advancing the
  /// clock also pins that auto-dismiss.
  Future<void> expireToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('AppVersionResponse.fromJson', () {
    test('parses every field of the backend payload', () {
      final parsed = AppVersionResponse.fromJson({
        'version': '2.0.0',
        'build': 20,
        'min_build': 5,
        'force_update': true,
        'apk_url': 'https://example.test/justus.apk',
        'changelog': 'Fixed the thing',
      });

      expect(parsed.version, '2.0.0');
      expect(parsed.build, 20);
      expect(parsed.minBuild, 5);
      expect(parsed.forceUpdate, isTrue);
      expect(parsed.apkUrl, 'https://example.test/justus.apk');
      expect(parsed.changelog, 'Fixed the thing');
    });

    test('absent fields fall back to the documented defaults', () {
      final parsed = AppVersionResponse.fromJson({});

      expect(parsed.version, isEmpty);
      expect(parsed.build, 0);
      expect(parsed.minBuild, 0);
      expect(parsed.forceUpdate, isFalse);
      expect(parsed.apkUrl, isEmpty);
      expect(parsed.changelog, isEmpty);
    });

    test('build and min_build are truncated from a JSON double', () {
      final parsed = AppVersionResponse.fromJson({
        'build': 20.9,
        'min_build': 5.4,
      });

      expect(parsed.build, 20);
      expect(parsed.minBuild, 5);
    });

    test('only a real boolean true arms force_update, mirroring the backend',
        () {
      // `versionService.js` normalizes with `parsed.force_update === true`
      // before the payload leaves the server, so `'true'` and `1` cannot arrive
      // as truthy values. Pinning `== true` here keeps both sides on one rule.
      expect(
        AppVersionResponse.fromJson({'force_update': 'true'}).forceUpdate,
        isFalse,
      );
      expect(
        AppVersionResponse.fromJson({'force_update': 1}).forceUpdate,
        isFalse,
      );
      expect(
        AppVersionResponse.fromJson({'force_update': true}).forceUpdate,
        isTrue,
      );
    });

    test('a non-numeric build is rejected instead of silently becoming 0', () {
      // The backend refuses to serve a non-number build
      // (`typeof parsed.build !== "number"`), so this shape never arrives from
      // `versionService`. What matters is that the client does not degrade it
      // to "build 0", which would read as ancient and re-prompt forever.
      expect(
        () => AppVersionResponse.fromJson({'build': '20'}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('VersionRepository -> ApiService', () {
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
    });

    test('checkAppVersion hits the versioned route and returns the parsed '
        'model', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({
                  'version': '2.0.0',
                  'build': 20,
                  'min_build': 5,
                  'force_update': false,
                  'apk_url': 'https://example.test/justus.apk',
                  'changelog': 'Fixed the thing',
                }),
                200,
              ));

      final versionRepository =
          VersionRepository(api: ApiService(client: mockClient));
      final result = await versionRepository.checkAppVersion();

      final capturedUri = verify(
        () => mockClient.get(captureAny(), headers: any(named: 'headers')),
      ).captured.last as Uri;

      expect(capturedUri.path, '/api/v1/app-version');
      final value = result.valueOrNull;
      expect(value, isNotNull);
      expect(value!.build, 20);
      expect(value.minBuild, 5);
      expect(value.apkUrl, 'https://example.test/justus.apk');
      expect(value.changelog, 'Fixed the thing');
    });

    test('a transport failure surfaces as a result with no value', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(const SocketException('No internet'));

      final versionRepository =
          VersionRepository(api: ApiService(client: mockClient));
      final result = await versionRepository.checkAppVersion();

      expect(result, isA<NetworkError<AppVersionResponse>>());
      expect(result.valueOrNull, isNull);
    });
  });

  group('checkVersion: up-to-date branch', () {
    testWidgets('a local build equal to the server build shows no dialog and '
        'answers a manual check with the up-to-date toast', (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 10, minBuild: 5)),
        localBuild: '10',
        showNoUpdateToast: true,
      );
      await runCheck(tester);

      expect(repo.checkAppVersionCalls, 1);
      expect(find.byType(VPDialog), findsNothing);
      expect(find.text('App is up to date!'), findsOneWidget);

      await expireToast(tester);
      expect(find.text('App is up to date!'), findsNothing,
          reason: 'a non-error toast removes itself after 4 seconds');
    });

    testWidgets('a local build ahead of the server is not a downgrade prompt',
        (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 10, minBuild: 5)),
        localBuild: '11',
        showNoUpdateToast: true,
      );
      await runCheck(tester);

      expect(repo.checkAppVersionCalls, 1);
      expect(find.byType(VPDialog), findsNothing);
      expect(find.text('App is up to date!'), findsOneWidget,
          reason: 'localBuild >= serverBuild takes the up-to-date branch');

      await expireToast(tester);
    });

    testWidgets('the automatic check stays silent when up to date',
        (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 10, minBuild: 5)),
        localBuild: '10',
      );
      await runCheck(tester);

      expect(find.byType(VPDialog), findsNothing);
      expect(find.text('App is up to date!'), findsNothing);
    });

    testWidgets('an unparseable local build number reads as 0, which is '
        'mandatory against any positive min_build', (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 10, minBuild: 5)),
        localBuild: 'not-a-number',
        showNoUpdateToast: true,
      );
      await runCheck(tester);

      expect(find.byType(VPDialog), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsNothing,
          reason: 'localBuild 0 < minBuild 5, so the floor is enforced');
    });
  });

  group('checkVersion: force-update truth table '
      '(mandatory = forceUpdate || localBuild < minBuild)', () {
    final cases = <({
      String name,
      int local,
      int server,
      int min,
      bool force,
      bool mandatory,
    })>[
      (
        name: 'below min_build with force_update false is still mandatory',
        local: 10,
        server: 20,
        min: 15,
        force: false,
        mandatory: true,
      ),
      (
        name: 'above min_build with force_update true is still mandatory',
        local: 10,
        server: 20,
        min: 5,
        force: true,
        mandatory: true,
      ),
      (
        name: 'both disjuncts true is mandatory',
        local: 10,
        server: 20,
        min: 15,
        force: true,
        mandatory: true,
      ),
      (
        name: 'neither disjunct true leaves the update optional',
        local: 10,
        server: 20,
        min: 5,
        force: false,
        mandatory: false,
      ),
      (
        name: 'localBuild == minBuild is allowed (the comparison is strict)',
        local: 15,
        server: 20,
        min: 15,
        force: false,
        mandatory: false,
      ),
      (
        name: 'one build below minBuild is mandatory',
        local: 14,
        server: 20,
        min: 15,
        force: false,
        mandatory: true,
      ),
    ];

    for (final row in cases) {
      testWidgets(row.name, (tester) async {
        await pumpCheck(
          tester,
          result: Success(
            _version(
              build: row.server,
              minBuild: row.min,
              forceUpdate: row.force,
            ),
          ),
          localBuild: '${row.local}',
        );
        await runCheck(tester);

        expect(find.byType(VPDialog), findsOneWidget);
        expect(find.text('Update now'), findsOneWidget);
        expect(find.text('Later'), row.mandatory ? findsNothing : findsOneWidget,
            reason: 'the dismiss action exists only for an optional update');
      });
    }
  });

  group('checkVersion: the update dialog', () {
    testWidgets('a mandatory update survives a barrier tap and a back gesture',
        (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 20, minBuild: 15)),
        localBuild: '10',
      );
      await runCheck(tester);

      expect(find.text('Update available!'), findsOneWidget);
      expect(find.text('Later'), findsNothing);

      // The barrier's own flag is pinned as well as the resulting behavior:
      // a barrier tap pops through `Navigator.maybePop`, which `PopScope`
      // also blocks, so behaviour alone cannot tell the two apart.
      expect(
        _dialogBarrier(tester).dismissible,
        isFalse,
        reason: 'showDialog must be called with barrierDismissible: false',
      );
      expect(
        _dialogPopScope(tester).canPop,
        isFalse,
        reason: 'the dialog body must be wrapped in PopScope(canPop: false)',
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(VPDialog), findsOneWidget,
          reason: 'barrierDismissible must be false for a mandatory update');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(VPDialog), findsOneWidget,
          reason: 'canPop must be false for a mandatory update');

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.byType(VPDialog), findsOneWidget);
    });

    testWidgets('an optional update is dismissed by the barrier, by "Later" '
        'and by a back gesture', (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 20, minBuild: 5)),
        localBuild: '10',
      );
      await runCheck(tester);

      expect(find.text('Later'), findsOneWidget);
      expect(
        _dialogBarrier(tester).dismissible,
        isTrue,
        reason: 'showDialog must be called with barrierDismissible: true',
      );
      expect(
        _dialogPopScope(tester).canPop,
        isTrue,
        reason: 'the dialog body must be wrapped in PopScope(canPop: true)',
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(VPDialog), findsNothing,
          reason: 'barrierDismissible must be true for an optional update');

      await runCheck(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(VPDialog), findsNothing,
          reason: 'canPop must be true for an optional update');

      await runCheck(tester);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(VPDialog), findsNothing);
      expect(repo.checkAppVersionCalls, 3);
    });

    testWidgets('"Update now" launches the APK url and closes an optional '
        'dialog', (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 20, minBuild: 5)),
        localBuild: '10',
      );
      await runCheck(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(launchedUrls, ['https://example.test/justus.apk']);
      expect(find.byType(VPDialog), findsNothing);
    });

    testWidgets('"Update now" launches the APK url but keeps a mandatory '
        'dialog up', (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 20, minBuild: 15)),
        localBuild: '10',
      );
      await runCheck(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(launchedUrls, ['https://example.test/justus.apk']);
      expect(find.byType(VPDialog), findsOneWidget);
    });

    testWidgets('an empty changelog hides the changelog section',
        (tester) async {
      await pumpCheck(
        tester,
        result: Success(
          AppVersionResponse(
            version: '2.0.0',
            build: 20,
            minBuild: 5,
            forceUpdate: false,
            apkUrl: 'https://example.test/justus.apk',
            changelog: '',
          ),
        ),
        localBuild: '10',
      );
      await runCheck(tester);

      expect(find.byType(VPDialog), findsOneWidget);
      expect(find.text('A new version of JustUs is available.'), findsOneWidget);
      expect(find.text('What\u2019s new:'), findsNothing);
    });

    testWidgets('a non-empty changelog is rendered under its header',
        (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 20, minBuild: 5)),
        localBuild: '10',
      );
      await runCheck(tester);

      expect(find.text('What\u2019s new:'), findsOneWidget);
      expect(find.text('Fixed the thing'), findsOneWidget);
    });

    testWidgets('a second check while a mandatory dialog is up is suppressed',
        (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 20, minBuild: 15)),
        localBuild: '10',
      );
      await runCheck(tester);
      expect(repo.checkAppVersionCalls, 1);

      await service.checkVersion(checkContext);
      await tester.pumpAndSettle();

      expect(repo.checkAppVersionCalls, 1,
          reason: '_isDialogShowing must gate a re-entrant check');
      expect(find.byType(VPDialog), findsOneWidget);
    });

    testWidgets('a dismissed optional dialog clears the guard so the next '
        'check runs', (tester) async {
      await pumpCheck(
        tester,
        result: Success(_version(build: 20, minBuild: 5)),
        localBuild: '10',
      );
      await runCheck(tester);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      await runCheck(tester);

      expect(repo.checkAppVersionCalls, 2);
      expect(find.byType(VPDialog), findsOneWidget);
    });
  });

  group('checkVersion: failure feedback', () {
    testWidgets('a failed manual check reports the network error',
        (tester) async {
      await pumpCheck(
        tester,
        result: const NetworkError<AppVersionResponse>(message: 'No internet'),
        localBuild: '10',
        showNoUpdateToast: true,
      );
      await runCheck(tester);

      expect(find.byType(VPDialog), findsNothing);
      expect(find.textContaining('[LOCAL-NET-001]'), findsOneWidget);

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('[LOCAL-NET-001]'), findsNothing,
          reason: 'an error toast stays until it is dismissed explicitly');
    });

    testWidgets('a failed automatic check stays silent', (tester) async {
      await pumpCheck(
        tester,
        result: const NetworkError<AppVersionResponse>(message: 'No internet'),
        localBuild: '10',
      );
      await runCheck(tester);

      expect(find.byType(VPDialog), findsNothing);
      expect(find.textContaining('[LOCAL-NET-001]'), findsNothing);
    });
  });

  group('call sites', () {
    test('home runs the automatic check from a post-frame callback, with no '
        'gesture and no toast', () {
      final file = File('lib/features/home/screens/homepage_screen.dart');
      expect(file.existsSync(), isTrue);

      final source = stripComments(file.readAsStringSync());

      expect(
        RegExp(r'addPostFrameCallback\(\(_\) \{[^}]*'
                r'_updateService\.checkVersion\(context\)')
            .hasMatch(source),
        isTrue,
        reason: 'the home entry point must run the automatic check',
      );
      expect(source.contains('showNoUpdateToast'), isFalse,
          reason: 'the automatic check is not a manual request');
    });

    test('the profile manual check asks for feedback and stays reachable',
        () {
      final file = File('lib/features/settings/screens/profile_screen.dart');
      expect(file.existsSync(), isTrue);

      final source = stripComments(file.readAsStringSync());

      expect(
        source.contains(
            'UpdateService().checkVersion(context, showNoUpdateToast: true)'),
        isTrue,
        reason: 'the manual check must set showNoUpdateToast: true',
      );
      expect(
        RegExp(r'onTap: _checkUpdate').allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason: 'the manual check is reachable from the setting tiles and the '
            'version row',
      );
    });
  });
}