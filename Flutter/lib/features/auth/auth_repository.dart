import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:justus/all_imports.dart';

class AuthRepository extends BaseRepository {
  final ApiService _api;

  AuthRepository({super.sbClient, ApiService? api}) 
    : _api = api ?? ApiService();


  Future<ResultWrapper<Map<String, dynamic>>> checkLoginRisk(String email, String deviceFingerprint) async {
    return _api.checkLoginRisk({
      'email': email.trim(),
      'deviceFingerprint': deviceFingerprint,
    });
  }

  Future<ResultWrapper<Map<String, dynamic>>> reportFailedLogin(String email, String deviceFingerprint, String? reason) async {
    return _api.reportFailedLogin({
      'email': email.trim(),
      'deviceFingerprint': deviceFingerprint,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<ResultWrapper<Map<String, dynamic>>> syncSession(String deviceFingerprint, String deviceLabel) async {
    return _api.syncSession({
      'deviceFingerprint': deviceFingerprint,
      'deviceLabel': deviceLabel,
    });
  }


  Session? get currentSession => sbClient.auth.currentSession;

  Future<AuthResponse> signInWithPassword({required String email, required String password, required String captchaToken}) async {
    return sbClient.auth.signInWithPassword(email: email, password: password, captchaToken: captchaToken);
  }

  Future<AuthResponse> signUp({required String email, required String password, required Map<String, dynamic> data, required String emailRedirectTo, required String captchaToken}) async {
    return sbClient.auth.signUp(email: email, password: password, data: data, emailRedirectTo: emailRedirectTo, captchaToken: captchaToken);
  }

  Future<void> signOut() async {
    await sbClient.auth.signOut();
  }

  Future<ResultWrapper<void>> changePassword(
      String currentPassword, String newPassword) async {
    return tryCall(() async {
      await sbClient.auth.updateUser(UserAttributes(password: newPassword));
    });
  }

  Future<ResultWrapper<void>> updateDeviceToken(
    String deviceToken, {
    String? locale,
  }) async {
    final result = await _api.updateDeviceToken(UpdateTokenRequest(
      deviceToken: deviceToken,
      deviceType: defaultTargetPlatform.name,
      locale: locale,
    ));
    if (result is GenericError<UpdateTokenResponse>) {
      return GenericError(message: result.message, code: result.code);
    }
    if (result is NetworkError<UpdateTokenResponse>) {
      return NetworkError(message: result.message);
    }

    return const Success(null);
  }
}
