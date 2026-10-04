import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'test_helpers/mock_secure_storage.dart';
import 'package:justus/all_imports.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiService apiService;
  late MockHttpClient mockClient;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    installMockSecureStorage();
    ApiService.clearHeadersCache();
    ApiService.onSessionExpired = null;
    ApiService.onMissingBindingSecret = null;
    ApiService.tokenRefreshHandler = null;
    ApiService.readAccessTokenForTest = null;
    mockClient = MockHttpClient();
    apiService = ApiService(client: mockClient);
  });

  // Counts every onMissingBindingSecret round trip so the tests can prove the
  // recovery is invoked exactly once (and throttled) rather than merely "some
  // time".
  var recoveryCalls = 0;

  void trackRecovery(String? Function() produceSecret) {
    recoveryCalls = 0;
    ApiService.onMissingBindingSecret = () async {
      recoveryCalls++;
      final secret = produceSecret();
      if (secret != null) {
        await StorageService.saveRequestBindingSecret(secret);
      }
    };
  }

  group('ApiService - Error Handling', () {
    test('returns NetworkError on SocketException', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(const SocketException('No internet'));

      final result = await apiService.getAppVersion();

      expect(result, isA<NetworkError<AppVersionResponse>>());
      expect((result as NetworkError).message, contains('No internet'));
    });

    test('returns GenericError on malformed JSON', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('invalid json', 200));

      final result = await apiService.getAppVersion();

      expect(result, isA<GenericError<AppVersionResponse>>());
    });

    test('returns GenericError with AppError details on 400', () async {
      final errorPayload = jsonEncode({
        'error': {'message': 'Custom Error', 'code': 'ERR001'}
      });
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(errorPayload, 400));

      final result = await apiService.getAppVersion();

      expect(result, isA<GenericError<AppVersionResponse>>());
      expect((result as GenericError).message, 'Custom Error');
    });
  });

  group('ApiService - Headers', () {
    test('X-Device-Fingerprint and Client-User-Agent are present', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
              jsonEncode({'version': '1.0.0', 'apk_url': '', 'changelog': ''}),
              200));

      await apiService.getAppVersion();

      final capturedHeaders = verify(() =>
              mockClient.get(any(), headers: captureAny(named: 'headers')))
          .captured
          .last as Map<String, String>;

      expect(capturedHeaders.containsKey('X-Device-Fingerprint'), true);
      expect(capturedHeaders.containsKey('X-Client-User-Agent'), true);
      expect(capturedHeaders.containsKey('X-Client-User-Agent-Hash'), true);
    });
  });

  group('ApiService - Versioned routes', () {
    test('builds versioned app-version requests', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode(
                    {'version': '1.0.0', 'apk_url': '', 'changelog': ''}),
                200,
              ));

      await apiService.getAppVersion();

      final capturedUri = verify(
        () => mockClient.get(captureAny(), headers: any(named: 'headers')),
      ).captured.last as Uri;

      expect(capturedUri.toString(),
          'https://justus-dev.serverfede.eu/api/v1/app-version');
    });

    test('builds protected media URLs under /api/v1/media/file', () {
      final resolved =
          ApiService.resolveProtectedMediaUrl('uploads/42/pic.jpg');

      expect(
        resolved,
        'https://justus-dev.serverfede.eu/api/v1/media/file'
        '?filename=uploads%2F42%2Fpic.jpg',
      );
    });

    test('centralizes callback routes', () {
      expect(ApiRoutes.authCallbackPath, '/auth/callback');
      expect(ApiConfig.appUrl(ApiRoutes.authCallbackPath),
          'https://justus-dev.serverfede.eu/auth/callback');
    });
  });

  group('ApiService - Auth Refresh & Retry Flow (Phase 8.1)', () {
    // The refresh seam is the ONLY way to observe the token transition, so
    // these tests assert on the headers of BOTH the original attempt and the
    // retry. A handler that returns `true` without doing anything must not be
    // enough to pass: the stale token has to reach the handler and the retry
    // has to re-read the (new) session token.
    //
    // These use `updateDeviceToken` (an *authenticated*, signed POST) rather
    // than `getAppVersion`, because the latter is `skipAuth: true` and therefore
    // never carries an `Authorization` header at all.
    test('refresh success: 401 refreshes, then retries with the fresh token',
        () async {
      await StorageService.saveRequestBindingSecret('binding-secret-xyz');

      var sessionToken = 'stale-access-token';
      ApiService.readAccessTokenForTest = () => sessionToken;

      final observedStaleTokens = <String?>[];
      ApiService.tokenRefreshHandler = (stale) async {
        observedStaleTokens.add(stale);
        // Emulate the Supabase SDK rotating the session.
        sessionToken = 'fresh-access-token';

        return true;
      };

      final authorizations = <String?>[];
      final nonces = <String?>[];
      var postCalls = 0;
      when(() => mockClient.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'))).thenAnswer((invocation) async {
        final headers =
            invocation.namedArguments[#headers] as Map<String, String>;
        authorizations.add(headers['Authorization']);
        nonces.add(headers['X-Request-Nonce']);
        postCalls++;
        if (postCalls == 1) {
          return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
        }

        return http.Response(
            jsonEncode({'success': true, 'token': 'device-tok'}), 200);
      });

      final result = await apiService.updateDeviceToken(
        UpdateTokenRequest(deviceToken: 'tok123', deviceType: 'android'),
      );

      expect(postCalls, 2, reason: 'exactly one retry, no refresh loop');
      // The handler must be told which token the rejected request carried,
      // otherwise it cannot skip a redundant refresh (see _tryRefreshToken).
      expect(observedStaleTokens, ['stale-access-token']);

      // The decisive assertion: the retry is authorized with the NEW token.
      expect(authorizations, [
        'Bearer stale-access-token',
        'Bearer fresh-access-token',
      ]);
      // Signed endpoints must re-sign the retry, not replay the stale signature.
      expect(nonces.first, isNotNull);
      expect(nonces.last, isNotNull);
      expect(nonces.last, isNot(nonces.first),
          reason: 'the retry must get a fresh nonce/signature pair');

      expect(result, isA<Success<UpdateTokenResponse>>());
    });

    test('refresh failure: 401 expires the session and does NOT retry',
        () async {
      await StorageService.saveRequestBindingSecret('binding-secret-xyz');
      ApiService.readAccessTokenForTest = () => 'stale-access-token';

      var refreshAttempts = 0;
      ApiService.tokenRefreshHandler = (_) async {
        refreshAttempts++;

        return false;
      };

      var sessionExpiredCalls = 0;
      ApiService.onSessionExpired = () async {
        sessionExpiredCalls++;
      };

      var postCalls = 0;
      when(() => mockClient.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'))).thenAnswer((_) async {
        postCalls++;

        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      });

      final result = await apiService.updateDeviceToken(
        UpdateTokenRequest(deviceToken: 'tok123', deviceType: 'android'),
      );

      // No retry: a failed refresh must not turn into a 401 hammer loop.
      expect(postCalls, 1);
      expect(refreshAttempts, 1);
      expect(sessionExpiredCalls, 1,
          reason: 'the redirect-to-login callback fires exactly once');

      expect(result, isA<GenericError<UpdateTokenResponse>>());
      final err = result as GenericError<UpdateTokenResponse>;
      expect(err.code, 401);
      expect(err.message, contains('Session expired'));
    });

    test('a 401 that survives the retry is reported without looping forever',
        () async {
      await StorageService.saveRequestBindingSecret('binding-secret-xyz');
      ApiService.readAccessTokenForTest = () => 'stale-access-token';
      ApiService.tokenRefreshHandler = (_) async => true;

      var sessionExpiredCalls = 0;
      ApiService.onSessionExpired = () async {
        sessionExpiredCalls++;
      };

      var postCalls = 0;
      when(() => mockClient.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'))).thenAnswer((_) async {
        postCalls++;

        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      });

      final result = await apiService.updateDeviceToken(
        UpdateTokenRequest(deviceToken: 'tok123', deviceType: 'android'),
      );

      // `isRetry` must cap the flow at exactly two attempts.
      expect(postCalls, 2);
      // The retry-exhausted 401 is surfaced as a 401...
      expect(result, isA<GenericError<UpdateTokenResponse>>());
      expect((result as GenericError<UpdateTokenResponse>).code, 401);
      // ...and must NOT also fire the redirect-to-login callback, which would
      // sign the user out for a transient server-side 401.
      expect(sessionExpiredCalls, 0);
    });

    test('revokeDeviceToken: a 401 never re-enters the logout callback',
        () async {
      await StorageService.saveRequestBindingSecret('binding-secret-xyz');
      ApiService.readAccessTokenForTest = () => 'stale-access-token';
      ApiService.tokenRefreshHandler = (_) async => false;

      var sessionExpiredCalls = 0;
      ApiService.onSessionExpired = () async {
        sessionExpiredCalls++;
      };

      when(() => mockClient.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'))).thenAnswer((_) async {
        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      });

      final result = await apiService.revokeDeviceToken('fcm-token-1234567890');

      // `onSessionExpired` IS `AuthState.logout()`, and the revoke is issued
      // from inside logout: escalating here would re-enter the teardown.
      expect(sessionExpiredCalls, 0);
      expect(result, isA<GenericError<Map<String, dynamic>>>());
      expect((result as GenericError).code, 401);
    });

    test('a non-401 error never triggers a refresh', () async {
      await StorageService.saveRequestBindingSecret('binding-secret-xyz');
      ApiService.readAccessTokenForTest = () => 'good-access-token';

      var refreshAttempts = 0;
      ApiService.tokenRefreshHandler = (_) async {
        refreshAttempts++;

        return true;
      };
      var sessionExpiredCalls = 0;
      ApiService.onSessionExpired = () async {
        sessionExpiredCalls++;
      };

      var postCalls = 0;
      when(() => mockClient.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'))).thenAnswer((_) async {
        postCalls++;

        return http.Response(
          jsonEncode({
            'error': {'message': 'Rate limited', 'code': 'ERR_RL'}
          }),
          429,
        );
      });

      final result = await apiService.updateDeviceToken(
        UpdateTokenRequest(deviceToken: 'tok123', deviceType: 'android'),
      );

      expect(postCalls, 1);
      expect(refreshAttempts, 0);
      expect(sessionExpiredCalls, 0);
      expect(result, isA<GenericError<UpdateTokenResponse>>());
      final err = result as GenericError<UpdateTokenResponse>;
      expect(err.code, 429);
      expect(err.message, 'Rate limited');
    });

    group('binding secret (signed endpoints)', () {
      test('a cached secret signs the very first attempt', () async {
        await StorageService.saveRequestBindingSecret('cached-secret-abc');
        trackRecovery(() => 'should-not-be-needed');

        when(() => mockClient.post(any(),
                headers: any(named: 'headers'), body: any(named: 'body')))
            .thenAnswer((_) async => http.Response(
                jsonEncode({'success': true, 'token': 'device-tok'}), 200));

        final result = await apiService.updateDeviceToken(
          UpdateTokenRequest(deviceToken: 'tok123', deviceType: 'android'),
        );

        expect(result, isA<Success<UpdateTokenResponse>>());

        final headers = verify(() => mockClient.post(any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'))).captured.last as Map<String, String>;

        expect(headers['X-Request-Signature'], isNotNull);
        expect(headers['X-Request-Timestamp'], isNotNull);
        expect(headers['X-Request-Nonce'], isNotNull);
        expect(headers['X-Request-Nonce'], isNotEmpty);
        // A cached secret needs no recovery round trip.
        expect(recoveryCalls, 0);
      });

      test('missing secret: recovery runs once and the request IS signed',
          () async {
        trackRecovery(() => 'recovered-secret-123');

        var postCalls = 0;
        final signatures = <String?>[];
        when(() => mockClient.post(any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'))).thenAnswer((invocation) async {
          postCalls++;
          final headers =
              invocation.namedArguments[#headers] as Map<String, String>;
          signatures.add(headers['X-Request-Signature']);

          return http.Response(
              jsonEncode({'success': true, 'token': 'device-tok'}), 200);
        });

        final result = await apiService.updateDeviceToken(
          UpdateTokenRequest(deviceToken: 'tok123', deviceType: 'android'),
        );

        expect(recoveryCalls, 1);
        // Recovery is *pre-flight*: the secret is fetched before the request is
        // ever sent, so the single attempt is already signed and no unsigned
        // request can leak to the API.
        expect(postCalls, 1);
        expect(signatures.single, isNotNull,
            reason: 'the recovered secret must sign the outgoing request');
        expect(result, isA<Success<UpdateTokenResponse>>());

        // The recovered secret is now cached, so a second signed call must not
        // pay for another recovery round trip.
        await apiService.updateDeviceToken(
          UpdateTokenRequest(deviceToken: 'tok456', deviceType: 'android'),
        );
        expect(postCalls, 2);
        expect(signatures.last, isNotNull);
        expect(recoveryCalls, 1);
      });

      test(
          'missing secret, unrecoverable: fails closed with ZERO network calls',
          () async {
        trackRecovery(() => null);

        final result = await apiService.updateDeviceToken(
          UpdateTokenRequest(deviceToken: 'tok123', deviceType: 'android'),
        );

        expect(recoveryCalls, 1);
        // Fail-closed means the request is never sent unauthenticated.
        verifyNever(() => mockClient.post(any(),
            headers: any(named: 'headers'), body: any(named: 'body')));
        verifyNever(
            () => mockClient.get(any(), headers: any(named: 'headers')));

        expect(result, isA<GenericError<UpdateTokenResponse>>());
        final err = result as GenericError<UpdateTokenResponse>;
        expect(err.details, isA<AppError>());
        expect((err.details as AppError).code,
            ErrorCodes.localBindingSecretMissing);
      });

      test('recovery is attempted at most once per 30s window', () async {
        trackRecovery(() => null);

        // Two signed calls in the same window: the 30s throttle must suppress
        // the second recovery round trip.
        for (var i = 0; i < 2; i++) {
          final result = await apiService.updateDeviceToken(
            UpdateTokenRequest(deviceToken: 'tok$i', deviceType: 'android'),
          );
          expect(result, isA<GenericError<UpdateTokenResponse>>());
        }

        expect(recoveryCalls, 1);
        verifyNever(() => mockClient.post(any(),
            headers: any(named: 'headers'), body: any(named: 'body')));
      });
    });
  });

  group('ApiConfig - build mode selection', () {
    test('resolves dev origin in debug/test builds', () {
      expect(ApiConfig.isDebug, isTrue);
      expect(ApiConfig.serverOrigin, 'https://justus-dev.serverfede.eu');
      expect(ApiConfig.apiOrigin, 'https://justus-dev.serverfede.eu');
      expect(ApiConfig.appOrigin, 'https://justus-dev.serverfede.eu');
    });

    test('keeps api/v1 paths intact on the selected origin', () {
      expect(
        ApiConfig.apiUri(ApiRoutes.authSessionSync).toString(),
        'https://justus-dev.serverfede.eu/api/v1/auth/session-sync',
      );
      expect(
        ApiConfig.apiUri(ApiRoutes.authDeviceToken).toString(),
        'https://justus-dev.serverfede.eu/api/v1/auth/device-token',
      );
      expect(
        ApiConfig.apiUri(ApiRoutes.appVersion).toString(),
        'https://justus-dev.serverfede.eu/api/v1/app-version',
      );
    });
  });
}
