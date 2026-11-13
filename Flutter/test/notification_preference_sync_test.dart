import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression test for 19.7: the toggle is an absolute-value upsert, so an
/// identical retry is harmless. A double tap, however, can leave two requests
/// in flight with different values; the sync must be serialized so the last
/// switch position is also the last server write.
class _GatedApi extends ApiService {
  final List<bool?> preferences = [];
  Completer<void>? gate;
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<ResultWrapper<UpdateInstallationResponse>> updateInstallationId(
      UpdateInstallationRequest body) async {
    preferences.add(body.notificationsEnabled);
    _inFlight += 1;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      final pending = gate;
      if (pending != null) await pending.future;
    } finally {
      _inFlight -= 1;
    }
    return Success(UpdateInstallationResponse(success: true));
  }
}

const String _kInstallationId = 'fid-notification-sync-test-0123456789';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    LanguageHelper.setAppLocale(LanguageHelper.fallbackLocale);
    InstallationIdService.installationIdOverride = () async => _kInstallationId;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    InstallationIdService.installationIdOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test('a double tap sends the latest value last and never runs concurrently',
      () async {
    final api = _GatedApi();
    final state = AuthState(authRepo: AuthRepository(api: api));
    await state.setLoginData(
      accessToken: 'access-token',
      user: User(id: 1, email: 'user@example.com', displayName: 'Alex'),
    );

    await StorageService.setNotificationsEnabled(false);
    final gate = Completer<void>();
    api.gate = gate;

    final first = state.syncNotificationPreference();
    for (var i = 0; i < 20 && api.preferences.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(api.preferences, [false]);

    // Second tap while the first registration is still in flight.
    await StorageService.setNotificationsEnabled(true);
    final second = state.syncNotificationPreference();
    expect(api.preferences, [false]);

    api.gate = null;
    gate.complete();
    await Future.wait([first, second]);

    expect(api.preferences, [false, true]);
    expect(api.maxInFlight, 1);
  });
}
