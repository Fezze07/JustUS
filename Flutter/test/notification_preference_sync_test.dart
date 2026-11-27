import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

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

class _RecordingAuthRepository extends AuthRepository {
  final List<String> installationIds = [];

  @override
  sb.Session? get currentSession => null;

  @override
  Stream<dynamic> get onAuthStateChange => const Stream<dynamic>.empty();

  @override
  Future<ResultWrapper<void>> updateInstallationId(String installationId,
      {String? locale}) async {
    installationIds.add(installationId);
    return const Success(null);
  }
}

const String _kInstallationId = 'fid-notification-sync-test-0123456789';
const String _kRotatedInstallationId =
    'fid-notification-sync-rotated-test-0123456789';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<String> registeredInstallationIds;

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    LanguageHelper.setAppLocale(LanguageHelper.fallbackLocale);
    InstallationIdService.installationIdOverride = () async => _kInstallationId;
    registeredInstallationIds = StreamController<String>.broadcast(sync: true);
    InstallationIdService.onRegisteredOverride =
        registeredInstallationIds.stream;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    await registeredInstallationIds.close();
    InstallationIdService.installationIdOverride = null;
    InstallationIdService.onRegisteredOverride = null;
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

  test(
      'an explicit registration event is posted once and later FID changes sync',
      () async {
    final repo = _RecordingAuthRepository();
    final state = AuthState(authRepo: repo);
    await state.init();
    await state.setLoginData(
      accessToken: 'access-token',
      user: User(id: 1, email: 'user@example.com', displayName: 'Alex'),
    );

    final lookupStarted = Completer<void>();
    final installationId = Completer<String>();
    InstallationIdService.installationIdOverride = () {
      registeredInstallationIds.add(_kInstallationId);
      lookupStarted.complete();
      return installationId.future;
    };

    await StorageService.setNotificationsEnabled(false);
    final preferenceSync = state.syncNotificationPreference();
    await lookupStarted.future;
    await Future<void>.delayed(Duration.zero);
    installationId.complete(_kInstallationId);
    await preferenceSync;
    await Future<void>.delayed(Duration.zero);

    expect(repo.installationIds, [_kInstallationId]);

    registeredInstallationIds.add(_kRotatedInstallationId);
    for (var i = 0; i < 20 && repo.installationIds.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      repo.installationIds,
      [_kInstallationId, _kRotatedInstallationId],
    );
    state.dispose();
  });
}
