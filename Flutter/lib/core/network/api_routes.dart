class ApiRoutes {
  ApiRoutes._();

  static const String apiPrefix = '/api/v1';

  static const String root = apiPrefix;
  static const String ping = '$apiPrefix/ping';
  static const String appVersion = '$apiPrefix/app-version';

  static const String authCallbackPath = '/auth/callback';
  static const String inviteCallbackPath = '/auth/invite-callback';
  static const String authDeviceToken = '$apiPrefix/auth/device-token';
  static const String authDeviceTokenRevoke =
      '$apiPrefix/auth/device-token-revoke';
  static const String authDeviceTokenRevokeAll =
      '$apiPrefix/auth/device-token-revoke-all';
  static const String authInvite = '$apiPrefix/auth/invite';
  static const String authLoginRiskCheck = '$apiPrefix/auth/login-risk-check';
  static const String authLoginAttempt = '$apiPrefix/auth/login-attempt';
  static const String authSessionBind = '$apiPrefix/auth/session-bind';

  static const String mediaUploadUrl = '$apiPrefix/media/upload-url';
  static const String mediaComplete = '$apiPrefix/media/complete';
  static const String mediaFile = '$apiPrefix/media/file';
  static const String mediaDelete = '$apiPrefix/media/delete';

  static const String notifyPartner = '$apiPrefix/notify/partner';

  static const String userWipe = '$apiPrefix/users/wipe';
}
