// =============================================================================
// AuthState - Global authentication state
// Manages token, current user, and partner info
// =============================================================================

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:justus/all_imports.dart';

/// Esito del cambio password, per distinguere il caso specifico in cui la
/// password attuale è errata dagli altri fallimenti (rete, captcha, …).
enum ChangePasswordResult {
  success,
  currentPasswordWrong,
  failure,
}

class AuthState extends BaseState with WidgetsBindingObserver {
  final AuthRepository _authRepo;
  final PartnershipRepository _partnershipRepo;
  final UserRepository _userRepo;

  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _lastSyncedLocale;
  bool _isSyncingLocale = false;
  Timer? _localeSyncDebounceTimer;

  AuthState({
    AuthRepository? authRepo,
    PartnershipRepository? partnershipRepo,
    UserRepository? userRepo,
  })  : _authRepo = authRepo ?? AuthRepository(),
        _partnershipRepo = partnershipRepo ?? PartnershipRepository(),
        _userRepo = userRepo ?? UserRepository();

  String?
      _error; // Kept for custom error logic if needed, but BaseState has _message

  String? _accessToken;
  String? _refreshToken;
  String? _username;
  int? _userId;
  int? _partnerId;
  int? _partnershipId;
  String? _partnerDisplayName;
  List<PartnershipInvitation> _sentInvitations = [];
  List<PartnershipInvitation> _receivedInvitations = [];

  User? user;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get username => _username;
  int? get userId => _userId;
  int? get partnerId => _partnerId;
  int? get partnershipId => _partnershipId;
  String? get partnerDisplayName => _partnerDisplayName;
  List<PartnershipInvitation> get sentInvitations => _sentInvitations;
  List<PartnershipInvitation> get receivedInvitations => _receivedInvitations;

  String? get error => _error;

  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  bool get hasPartner => _partnerId != null;

  /// Determines the correct redirect URL based on the platform.
  /// - Mobile apps use deep links (justus://)
  /// - Web and Desktop use the server-side callback URL
  String get _emailRedirectTo {
    if (kIsWeb) return ApiConfig.appUrl(ApiRoutes.authCallbackPath);

    // Check for native mobile platforms
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return 'justus://auth/callback';
    }

    // Fallback for Windows, macOS, and Linux desktop apps
    return ApiConfig.appUrl(ApiRoutes.authCallbackPath);
  }

  Future<void> init() async {
    ApiService.onSessionExpired = () async {
      AnsiLogger.auth(
          'Session expired signal received from ApiService. Forcing logout.',
          tag: 'AuthState');
      await logout();
    };
    ApiService.onMissingBindingSecret = _syncBackendSession;

    // Make init idempotent (A3)
    await _authSubscription?.cancel();
    _authSubscription = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    // 1. Get local data parallelized
    final results = await Future.wait([
      StorageService.getAccessToken(),
      StorageService.getRefreshToken(),
      StorageService.getUsername(),
      StorageService.getUserId(),
      StorageService.getPartnerId(),
      StorageService.getPartnerDisplayName(),
      StorageService.getPartnershipId(),
    ]);

    _accessToken = results[0] as String?;
    _refreshToken = results[1] as String?;
    _username = results[2] as String?;
    _userId = results[3] as int?;
    _partnerId = results[4] as int?;
    _partnerDisplayName = results[5] as String?;
    _partnershipId = results[6] as int?;

    // Bind the storage namespace to the persisted partnership so feature
    // caches and checkpoints are never read under a different partnership
    // (F-SC8). No cache clearing at cold start — the same partnership.
    StorageService.setActivePartnership(_partnershipId);

    // 2. Check Supabase session
    final session = _authRepo.currentSession;
    if (session == null) {
      if (_accessToken != null) await logout();
    } else {
      if (_username == null || _username!.isEmpty) {
        final profileResult =
            await _userRepo.fetchProfileByAuthId(session.user.id);

        final user = profileResult.valueOrNull;
        if (user != null) {
          await setLoginData(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken ?? '',
            user: user,
          );
        }
      }
      await _syncBackendSession();

      // Register (or refresh) the FCM device token on every app start
      if (isLoggedIn && DeviceTokenService.supportsFcm) {
        final fcmToken = await DeviceTokenService.getDeviceToken();
        if (fcmToken != 'UNKNOWN_DEVICE_TOKEN') {
          try {
            final result = await _authRepo.updateDeviceToken(
              fcmToken,
              locale: ui.PlatformDispatcher.instance.locale.languageCode,
            );
            AnsiLogger.auth('updateDeviceToken (init): $result',
                tag: 'AuthState');
          } catch (e) {
            AnsiLogger.error('updateDeviceToken (init) ERROR: $e',
                tag: 'AuthState');
          }
        }
      }
    }

    // Sincronizza lo StorageService e gestisci il passwordRecovery da link email
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final evt = data.event;
      final currentSession = data.session;
      if (evt == AuthChangeEvent.tokenRefreshed && currentSession != null) {
        await StorageService.saveAccessToken(currentSession.accessToken);
        if (currentSession.refreshToken != null) {
          await StorageService.saveRefreshToken(currentSession.refreshToken!);
        }
        _accessToken = currentSession.accessToken;
        _refreshToken = currentSession.refreshToken;
      } else if (evt == AuthChangeEvent.passwordRecovery) {
        AnsiLogger.auth('Password recovery event received from deep link',
            tag: 'AuthState');
        final navContext = ErrorHandler.navigatorKey.currentContext;
        if (navContext != null && navContext.mounted) {
          unawaited(Navigator.push(
            navContext,
            MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          ));
        }
      }
    });
    _tokenRefreshSubscription =
        DeviceTokenService.onTokenRefresh.listen((token) async {
      if (token.isEmpty || !isLoggedIn) return;
      await _authRepo.updateDeviceToken(
        token,
        locale: ui.PlatformDispatcher.instance.locale.languageCode,
      );
    });

    // Observe app lifecycle to sync locale changes at runtime
    WidgetsBinding.instance.addObserver(this);

    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isLoggedIn) {
      _localeSyncDebounceTimer?.cancel();
      _localeSyncDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        _localeSyncDebounceTimer = null;
        unawaited(_syncDeviceLocale());
      });
    }
  }

  @override
  void didChangeLocales(List<ui.Locale>? locales) {
    if (isLoggedIn && locales != null && locales.isNotEmpty) {
      unawaited(_syncDeviceLocale(locales.first));
    }
  }

  Future<void> _syncDeviceLocale([ui.Locale? locale]) async {
    if (_isSyncingLocale) return;
    _isSyncingLocale = true;
    try {
      final currentLocale =
          (locale ?? ui.PlatformDispatcher.instance.locale).languageCode;
      if (currentLocale == _lastSyncedLocale) return;

      if (!DeviceTokenService.supportsFcm) return;
      final token = await DeviceTokenService.getDeviceToken();
      if (token.isEmpty || token == 'UNKNOWN_DEVICE_TOKEN') return;

      final result = await _authRepo.updateDeviceToken(
        token,
        locale: currentLocale,
      );
      if (result is Success<void>) {
        _lastSyncedLocale = currentLocale;
        AnsiLogger.notification('Locale synced: $currentLocale',
            tag: 'AuthState');
      } else {
        AnsiLogger.error('Locale sync failed: $result', tag: 'AuthState');
      }
    } catch (e) {
      AnsiLogger.error('Locale sync error: $e', tag: 'AuthState');
    } finally {
      _isSyncingLocale = false;
    }
  }

  Future<bool> login(String email, String password) async {
    return runSafe(() async {
      await _checkLoginRisk(email);

      // Step 0: CAPTCHA Verification
      final captchaToken = await _getCaptchaToken();

      if (captchaToken == null) {
        throw const AppError(
            code: ErrorCodes.localUnknown, message: 'Captcha failed');
      }

      // Step 1: Login to Supabase Auth
      final AuthResponse res;
      try {
        res = await _authRepo.signInWithPassword(
          email: email,
          password: password,
          captchaToken: captchaToken,
        );
      } on AuthException catch (e) {
        throw AppError(
            code: ErrorCodes.authFailCred,
            message: e.message,
            severity: ErrorSeverity.high);
      }

      if (res.user == null || res.session == null) {
        throw const AppError(
            code: ErrorCodes.authFailCred,
            message: 'Login failed: no user data');
      }

      // Step 2: Fetch public.users + user_profiles by auth_id (UUID)
      final profileResult = await _userRepo.fetchProfileByAuthId(res.user!.id);

      final user = profileResult.valueOrNull;
      if (user == null) {
        throw const AppError(
            code: ErrorCodes.dbNotFound001,
            message: 'Profilo utente non trovato nel database');
      }

      // Step 3: Set local data
      await setLoginData(
        accessToken: res.session!.accessToken,
        refreshToken: res.session!.refreshToken ?? '',
        user: user,
      );

      // Step 4: Sync session and register the device token through the backend
      await _syncBackendSession();
      final fcmToken = await DeviceTokenService.getDeviceToken();
      AnsiLogger.auth('FCM token (login): $fcmToken', tag: 'AuthState');
      try {
        final tokenResult = await _authRepo.updateDeviceToken(
          fcmToken,
          locale: ui.PlatformDispatcher.instance.locale.languageCode,
        );
        AnsiLogger.auth('updateDeviceToken (login): $tokenResult',
            tag: 'AuthState');
      } catch (e) {
        AnsiLogger.error('updateDeviceToken (login) ERROR: $e',
            tag: 'AuthState');
      }

      // Step 5: Fetch partner info via v_active_partnership (single source of truth)
      try {
        final partnershipResult = await _partnershipRepo.getPartnership();
        final partnership = partnershipResult.valueOrNull;

        if (partnership?.partner != null) {
          await setPartner(
            partnerId: partnership!.partner!.id,
            displayName: partnership.partner!.username,
            partnershipId: partnership.partnershipId,
          );
        }
      } catch (_) {}
    });
  }

  Future<bool> register(String email, String password, String name) async {
    setLoading(true);
    try {
      // Step 0: CAPTCHA Verification
      final captchaToken = await _getCaptchaToken();

      if (captchaToken == null) {
        throw const AppError(
            code: ErrorCodes.localUnknown, message: 'Captcha failed');
      }

      // 1. Supabase Auth Registration
      final AuthResponse res;
      try {
        res = await _authRepo.signUp(
          email: email,
          password: password,
          data: {
            'username': name,
          },
          emailRedirectTo: _emailRedirectTo,
          captchaToken: captchaToken,
        );
      } on AuthException catch (e) {
        throw AppError(
            code: ErrorCodes.authFailCred,
            message: e.message,
            severity: ErrorSeverity.high);
      }

      if (res.user == null) {
        throw const AppError(
            code: ErrorCodes.authFailCred,
            message: 'Registrazione fallita: utente non creato');
      }

      AnsiLogger.auth('Auth user creato: ${res.user!.id}', tag: 'Register');

      // 2. La verifica email è obbligatoria: se Supabase restituisce comunque
      //    una sessione (conferme disabilitate sul progetto), la revochiamo
      //    subito per non bypassare la conferma dell'email.
      if (res.session != null) {
        AnsiLogger.auth(
            'Sessione non attesa alla registrazione: signOut per imporre la verifica email',
            tag: 'Register');
        try {
          await _authRepo.signOut();
        } catch (e) {
          AnsiLogger.error(
              'SignOut dopo registrazione fallito: $e', tag: 'Register');
        }
      }

      AnsiLogger.auth('Email di conferma inviata a $email', tag: 'Register');
      return true;
    } catch (e, st) {
      ErrorHandler.handle(e, stackTrace: st);
      return false;
    } finally {
      setLoading(false);
    }
  }

  Future<bool> resetPassword(String email) async {
    return runSafe(() async {
      await _authRepo.resetPassword(
        email: email,
        redirectTo: _emailRedirectTo,
      );
    });
  }

  Future<bool> updatePasswordNew(String newPassword) async {
    return runSafe(() async {
      final result = await _authRepo.updatePasswordWithoutCurrent(newPassword);
      if (result is GenericError<void>) {
        throw AppError(
          code: result.code?.toString() ?? ErrorCodes.authFailCred,
          message: result.message ?? 'Password update failed',
        );
      } else if (result is NetworkError<void>) {
        throw AppError.network();
      }
    });
  }

  Future<ChangePasswordResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    setLoading(true);
    try {
      final email = _authRepo.currentSession?.user.email;
      if (email == null || email.isEmpty) {
        throw const AppError(
          code: ErrorCodes.authFail001,
          message: 'No active session',
        );
      }

      final captchaToken = await _getCaptchaToken();
      if (captchaToken == null) {
        throw const AppError(
          code: ErrorCodes.localUnknown,
          message: 'Captcha failed',
        );
      }

      final AuthResponse res;
      try {
        res = await _authRepo.signInWithPassword(
          email: email,
          password: currentPassword,
          captchaToken: captchaToken,
        );
      } on AuthException catch (e) {
        // La vecchia password è sbagliata: nessuno snackbar generico,
        // la schermata mostrerà il messaggio specifico.
        throw AppError(
          code: ErrorCodes.authFailCurrent,
          message: e.message,
          severity: ErrorSeverity.high,
        );
      }

      if (res.user == null || res.session == null) {
        throw const AppError(
          code: ErrorCodes.authFailCred,
          message: 'Re-authentication failed',
        );
      }

      final result =
          await _authRepo.changePassword(currentPassword, newPassword);
      if (result is GenericError<void>) {
        throw AppError(
          code: result.code?.toString() ?? ErrorCodes.authFailCred,
          message: result.message ?? 'Password change failed',
        );
      } else if (result is NetworkError<void>) {
        throw AppError.network();
      }

      return ChangePasswordResult.success;
    } catch (e, st) {
      if (e is AppError && e.code == ErrorCodes.authFailCurrent) {
        // Solo log, senza UI generica: il messaggio lo decide la schermata.
        ErrorHandler.handle(e, stackTrace: st, showUI: false);
        return ChangePasswordResult.currentPasswordWrong;
      }
      ErrorHandler.handle(e, stackTrace: st);
      return ChangePasswordResult.failure;
    } finally {
      setLoading(false);
    }
  }

  Future<bool> invitePartner(String email, String partnershipCode) async {
    return runSafe(() async {
      final res = await _partnershipRepo.inviteUser(email, partnershipCode);

      if (res is Success) {
        await fetchSentInvitations();
      } else {
        throw res;
      }
    });
  }

  /// Fetches pending outgoing (sent) partnership requests from Supabase.
  Future<void> fetchSentInvitations() async {
    await _fetchInvitations();
  }

  /// Fetches pending incoming (received) partnership requests from Supabase.
  Future<void> fetchReceivedInvitations() async {
    await _fetchInvitations();
  }

  Future<void> _fetchInvitations() async {
    try {
      if (_userId == null) return;

      final result = await _partnershipRepo.getPendingInvitations();
      final invitations = result.valueOrNull;
      if (invitations != null) {
        final sent = <PartnershipInvitation>[];
        final received = <PartnershipInvitation>[];
        for (final inv in invitations) {
          if (inv.isReceived) {
            received.add(inv);
          } else {
            sent.add(inv);
          }
        }
        _sentInvitations = sent;
        _receivedInvitations = received;
        notifyListeners();
      }
    } catch (e) {
      AnsiLogger.error('_fetchInvitations error: $e', tag: 'AuthState');
    }
  }

  Future<bool> acceptInvitation(int invitationId) async {
    return runSafe(() async {
      await _partnershipRepo.acceptPartnerRequest(invitationId);
      AnsiLogger.auth('RPC accept_partnership success', tag: 'AuthState');
      await fetchSentInvitations();
      await fetchReceivedInvitations();

      AnsiLogger.auth('Fetching active partnership info...', tag: 'AuthState');
      final partnershipResult = await _partnershipRepo.getPartnership();

      AnsiLogger.auth('Partnership data: $partnershipResult', tag: 'AuthState');

      final partner = partnershipResult.valueOrNull?.partner;
      if (partner != null) {
        await setPartner(
          partnerId: partner.id,
          displayName: partner.username,
        );
        AnsiLogger.auth('Partner set successfully', tag: 'AuthState');
      }
    });
  }

  Future<bool> rejectInvitation(int invitationId) async {
    return runSafe(() async {
      await _partnershipRepo.rejectPartnerRequest(invitationId);
      await fetchSentInvitations();
      await fetchReceivedInvitations();
    });
  }

  Future<void> setLoginData({
    required String accessToken,
    required String refreshToken,
    required User user,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _username = user.username;
    _userId = user.id;

    await StorageService.saveAccessToken(accessToken);
    await StorageService.saveRefreshToken(refreshToken);
    await StorageService.saveUsername(user.username);
    await StorageService.saveUserId(user.id);

    notifyListeners();
  }

  Future<void> setPartner({
    required int partnerId,
    required String displayName,
    int? partnershipId,
  }) async {
    _partnerId = partnerId;
    _partnerDisplayName = displayName;
    _partnershipId = partnershipId;

    await StorageService.savePartner(partnerId, displayName);
    if (partnershipId != null) {
      await StorageService.savePartnershipId(partnershipId);
    }
    notifyListeners();
  }

  Future<void> refreshPartnershipFromRealtime() async {
    try {
      BaseRepository.clearPartnershipCache();
      await _fetchInvitations();

      final partnershipResult = await _partnershipRepo.getPartnership();
      final partnership = partnershipResult.valueOrNull;
      if (partnership == null) return;

      final partner = partnership.partner;
      if (partner != null && partnership.status == 'accepted') {
        _partnerId = partner.id;
        _partnershipId = partnership.partnershipId;
        _partnerDisplayName = partner.username;
        await StorageService.savePartner(partner.id, partner.username);
        if (partnership.partnershipId != null) {
          await StorageService.savePartnershipId(partnership.partnershipId!);
        }
      } else {
        _partnerId = null;
        _partnershipId = null;
        _partnerDisplayName = null;
        await StorageService.clearPartner();
      }

      notifyListeners();
    } catch (e) {
      AnsiLogger.error('realtime partnership refresh error: $e',
          tag: 'AuthState');
    }
  }

  Future<void> _checkLoginRisk(String email) async {
    try {
      final deviceFingerprint = await DeviceTokenService.getDeviceFingerprint();
      final result = await _authRepo.checkLoginRisk(email, deviceFingerprint);

      if (result is GenericError<Map<String, dynamic>> && result.code == 429) {
        throw const AppError(
          code: ErrorCodes.secBlock002,
          message: 'Troppi tentativi di login. Riprova tra poco.',
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      // Other errors (network, etc) are ignored here to allow login attempt
      // but if it's a specific block, we want to stop.
    }
  }

  Future<void> _syncBackendSession() async {
    if (_authRepo.currentSession == null) {
      return;
    }

    try {
      final deviceFingerprint = await DeviceTokenService.getDeviceFingerprint();
      final result = await _authRepo.syncSession(
          deviceFingerprint, '${defaultTargetPlatform.name}-client');

      final value = result.valueOrNull;
      if (value != null) {
        final bindingSecret = value['bindingSecret'];
        if (bindingSecret is String && bindingSecret.isNotEmpty) {
          await StorageService.saveRequestBindingSecret(bindingSecret);
          AnsiLogger.auth('Session synced, binding secret saved.',
              tag: 'AuthState');
        }
      } else if (result.isError) {
        AnsiLogger.error('Session sync network error', tag: 'AuthState');
      }
    } catch (e) {
      AnsiLogger.error('_syncBackendSession exception: $e', tag: 'AuthState');
    }
  }

  Future<String?> _getCaptchaToken() => CaptchaService.getCaptchaToken();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localeSyncDebounceTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_tokenRefreshSubscription?.cancel());
    super.dispose();
  }

  Future<void> logout() async {
    await _authRepo.signOut();
    await CacheService.clearAll();
    await StorageService.clearAll();
    ApiService.clearHeadersCache();
    _accessToken = null;
    _refreshToken = null;
    _username = null;
    _userId = null;
    _partnerId = null;
    _partnershipId = null;
    _partnerDisplayName = null;
    _sentInvitations = [];
    user = null;
    notifyListeners();
  }
}
