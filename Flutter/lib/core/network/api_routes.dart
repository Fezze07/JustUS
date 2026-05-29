class ApiRoutes {
  ApiRoutes._();

  static const String apiPrefix = '/api/v1';

  static const String root = apiPrefix;
  static const String ping = '$apiPrefix/ping';
  static const String appVersion = '$apiPrefix/app-version';

  static const String authCallbackPath = '/auth/callback';
  static const String inviteCallbackPath = '/auth/invite-callback';
  static const String authDeviceToken = '$apiPrefix/auth/device-token';
  static const String authInvite = '$apiPrefix/auth/invite';
  static const String authLoginRiskCheck = '$apiPrefix/auth/login-risk-check';
  static const String authLoginAttempt = '$apiPrefix/auth/login-attempt';
  static const String authSessionSync = '$apiPrefix/auth/session-sync';
  static const String authRefresh = '$apiPrefix/auth/refresh';

  static const String mediaUploadUrl = '$apiPrefix/media/upload-url';
  static const String mediaComplete = '$apiPrefix/media/complete';
  static const String mediaFile = '$apiPrefix/media/file';

  static const String aiQuestion = '$apiPrefix/ai/question';

  static const String notifyPartner = '$apiPrefix/notify/partner';

  static const String userWipe = '$apiPrefix/users/wipe';
}
