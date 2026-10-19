import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:justus/all_imports.dart';

class AuthRepository extends BaseRepository {
  final ApiService _api;

  AuthRepository({super.sbClient, ApiService? api})
      : _api = api ?? ApiService();

  Future<ResultWrapper<Map<String, dynamic>>> checkLoginRisk(
      String email, String deviceFingerprint) async {
    return _api.checkLoginRisk({
      'email': email.trim(),
      'deviceFingerprint': deviceFingerprint,
    });
  }

  Future<ResultWrapper<Map<String, dynamic>>> reportFailedLogin(
      String email, String deviceFingerprint, String? reason) async {
    return _api.reportFailedLogin({
      'email': email.trim(),
      'deviceFingerprint': deviceFingerprint,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<ResultWrapper<Map<String, dynamic>>> bindSession(
      String deviceFingerprint) async {
    return _api.bindSession({
      'deviceFingerprint': deviceFingerprint,
    });
  }

  Session? get currentSession => sbClient.auth.currentSession;

  Future<AuthResponse> signInWithPassword(
      {required String email,
      required String password,
      required String captchaToken}) async {
    return sbClient.auth.signInWithPassword(
        email: email, password: password, captchaToken: captchaToken);
  }

  Future<AuthResponse> signUp(
      {required String email,
      required String password,
      required Map<String, dynamic> data,
      required String emailRedirectTo,
      required String captchaToken}) async {
    return sbClient.auth.signUp(
        email: email,
        password: password,
        data: data,
        emailRedirectTo: emailRedirectTo,
        captchaToken: captchaToken);
  }

  Future<void> resetPassword({
    required String email,
    required String redirectTo,
  }) async {
    await sbClient.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
    );
  }

  Future<ResultWrapper<void>> updatePasswordWithoutCurrent(
      String newPassword) async {
    return tryCall(() async {
      await sbClient.auth.updateUser(UserAttributes(
        password: newPassword,
      ));
    });
  }

  Future<ResultWrapper<Map<String, dynamic>>> revokeInstallationId(
      String installationId) async {
    return _api.revokeInstallationId(installationId);
  }

  /// Drops every other push registration of the account, keeping [keepInstallationId]'s.
  Future<ResultWrapper<Map<String, dynamic>>> revokeOtherInstallations(
      String keepInstallationId) async {
    return _api.revokeOtherInstallations(keepInstallationId);
  }

  Future<void> signOut() async {
    await sbClient.auth.signOut();
  }

  /// Revokes every session of this account except the live one, so a token
  /// stolen from another device dies with the password change. `others` keeps
  /// the current session and emits no `signedOut` event.
  Future<void> revokeOtherSessions() async {
    await sbClient.auth.signOut(scope: SignOutScope.others);
  }

  Future<ResultWrapper<void>> changePassword(
      String currentPassword, String newPassword) async {
    return tryCall(() async {
      await sbClient.auth.updateUser(UserAttributes(
        password: newPassword,
        currentPassword: currentPassword,
      ));
    });
  }

  Future<ResultWrapper<void>> updateInstallationId(
    String installationId, {
    String? locale,
  }) async {
    final result =
        await _api.updateInstallationId(UpdateInstallationRequest(
      installationId: installationId,
      deviceType: defaultTargetPlatform.name,
      locale: locale,
    ));
    if (result is GenericError<UpdateInstallationResponse>) {
      return GenericError(message: result.message, code: result.code);
    }
    if (result is NetworkError<UpdateInstallationResponse>) {
      return NetworkError(message: result.message);
    }

    return const Success(null);
  }
}
