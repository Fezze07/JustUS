class ApiRoutes {
  ApiRoutes._();

  static const String apiPrefix = '/api/v1';

  static const String appVersion = '$apiPrefix/app-version';

  static const String authCallbackPath = '/auth/callback';
  static const String authInstallationId = '$apiPrefix/auth/installation-id';
  static const String authInstallationIdRevoke =
      '$apiPrefix/auth/installation-id-revoke';
  static const String authInstallationIdRevokeAll =
      '$apiPrefix/auth/installation-id-revoke-all';
  static const String authInvite = '$apiPrefix/auth/invite';
  static const String authInviteUser = '$apiPrefix/auth/invite-user';
  static const String authLoginRiskCheck = '$apiPrefix/auth/login-risk-check';
  static const String authLoginAttempt = '$apiPrefix/auth/login-attempt';
  static const String authSessionBind = '$apiPrefix/auth/session-bind';

  static const String mediaUploadUrl = '$apiPrefix/media/upload-url';
  static const String mediaComplete = '$apiPrefix/media/complete';
  static const String mediaFile = '$apiPrefix/media/file';
  static const String mediaDelete = '$apiPrefix/media/delete';

  static const String notifyPartner = '$apiPrefix/notify/partner';

  static const String partnershipCancelAccept =
      '$apiPrefix/partnership/cancel/accept';

  static const String userWipe = '$apiPrefix/users/wipe';
}
