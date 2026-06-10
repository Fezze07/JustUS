// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'JustUs';

  @override
  String get example => 'Example';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitle => 'App preferences and language';

  @override
  String get languageSectionTitle => 'LANGUAGE';

  @override
  String get languageSettingTitle => 'Language';

  @override
  String get languageSettingSubtitle => 'Change language in real time';

  @override
  String get currentLanguageLabel => 'Current language';

  @override
  String get italianLanguage => 'Italian';

  @override
  String get englishLanguage => 'English';

  @override
  String get languageSavedMessage => 'Language updated';

  @override
  String get aiTranslationSectionTitle => 'AI TRANSLATIONS';

  @override
  String get aiTranslationReadyTitle => 'Ready for future translations';

  @override
  String get aiTranslationReadySubtitle =>
      'ARB keys are organized to expand new languages and AI workflows.';

  @override
  String get profileSettingsTitle => 'Profile & Settings';

  @override
  String get systemOverrideSectionTitle => 'SYSTEM';

  @override
  String get appTagline => 'Shared moments, closer hearts';

  @override
  String get common_you => 'YOU';

  @override
  String get common_youTitle => 'You';

  @override
  String get common_partner => 'Partner';

  @override
  String get common_partnerUpper => 'PARTNER';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_close => 'Close';

  @override
  String get common_retry => 'Retry';

  @override
  String get common_add => 'Add';

  @override
  String get common_delete => 'Delete';

  @override
  String get common_file => 'File';

  @override
  String get common_audio => 'Audio';

  @override
  String get auth_loginTitle => 'Welcome Back';

  @override
  String get auth_loginSubtitle => 'Login to reconnect with your partner';

  @override
  String get auth_loginNoAccount => 'Don\'t have an account?';

  @override
  String get auth_signUp => 'Sign Up';

  @override
  String get auth_emailLabel => 'EMAIL';

  @override
  String get auth_emailTitle => 'Email';

  @override
  String get auth_emailHint => 'your@email.com';

  @override
  String get auth_registerEmailHint => 'john@example.com';

  @override
  String get auth_passwordLabel => 'PASSWORD';

  @override
  String get auth_passwordTitle => 'Password';

  @override
  String get auth_passwordHint => '••••••••';

  @override
  String get auth_forgotPassword => 'Forgot Password?';

  @override
  String get auth_loginButton => 'Login';

  @override
  String get auth_registerTitle => 'Join JustUS';

  @override
  String get auth_registerSubtitle =>
      'Start your journey to a deeper connection.';

  @override
  String get auth_alreadyAccount => 'Already have an account?';

  @override
  String get auth_logIn => 'Log in';

  @override
  String get auth_nameLabel => 'YOUR NAME';

  @override
  String get auth_nameHint => 'John Doe';

  @override
  String get auth_createAccount => 'Create Account';

  @override
  String get auth_nameFieldName => 'Name';

  @override
  String get auth_confirmEmailTitle => 'Check your email';

  @override
  String get auth_goToLogin => 'Go to login';

  @override
  String get auth_changePasswordTitle => 'Change Password';

  @override
  String get auth_changePasswordSubtitle =>
      'Create a new password that is unique and secure.';

  @override
  String get auth_currentPasswordLabel => 'Current Password';

  @override
  String get auth_currentPasswordHint => 'Enter current password';

  @override
  String get auth_newPasswordLabel => 'New Password';

  @override
  String get auth_newPasswordHint => 'Enter new password';

  @override
  String get auth_confirmPasswordLabel => 'Confirm Password';

  @override
  String get auth_confirmPasswordHint => 'Re-enter new password';

  @override
  String get auth_updatePassword => 'Update Password';

  @override
  String get auth_passwordUpdated => 'Password updated successfully!';

  @override
  String get auth_captchaTitle => 'Security check';

  @override
  String get auth_captchaMessage => 'JustUs is verifying that you are human...';

  @override
  String get auth_captchaMissingConfig =>
      'Missing security configuration (Site Key).';

  @override
  String get auth_captchaFailed => 'Captcha failed';

  @override
  String get auth_loginNoUserData => 'Login failed: no user data';

  @override
  String get auth_registerUserNotCreated =>
      'Registration failed: user not created';

  @override
  String get auth_tooManyLoginAttempts =>
      'Too many login attempts. Try again shortly.';

  @override
  String get auth_validationEmailRequired => 'Email is required';

  @override
  String get auth_validationEmailInvalid => 'Enter a valid email';

  @override
  String get auth_validationPasswordRequired => 'Password is required';

  @override
  String get auth_validationPasswordMinLength =>
      'Password must be at least 8 characters';

  @override
  String get auth_validationPasswordLowercase =>
      'Must contain at least one lowercase letter';

  @override
  String get auth_validationPasswordUppercase =>
      'Must contain at least one uppercase letter';

  @override
  String get auth_validationPasswordNumber =>
      'Must contain at least one number';

  @override
  String get auth_validationPasswordSymbol =>
      'Must contain at least one symbol';

  @override
  String get home_daysTogether => 'DAYS TOGETHER';

  @override
  String get home_currentMoodTitle => 'OUR CURRENT MOOD';

  @override
  String get home_updateStatus => 'Update Status';

  @override
  String get home_quickActions => 'QUICK ACTIONS';

  @override
  String get home_viewAll => 'View All';

  @override
  String get home_moodTitle => 'Mood';

  @override
  String get home_moodSubtitle => 'Share how you feel';

  @override
  String get home_gamesTitle => 'Games';

  @override
  String get home_gamesSubtitle => 'Play a relationship quiz';

  @override
  String get home_photosTitle => 'Photos';

  @override
  String get home_photosSubtitle => 'Our Shared Gallery';

  @override
  String get home_bucketListTitle => 'Bucket List';

  @override
  String home_bucketListSubtitleDynamic(int count) {
    return '$count tasks pending';
  }

  @override
  String get home_nudgeTitle => 'Miss you...';

  @override
  String get home_nudgeSubtitle => 'Say it with a click';

  @override
  String get home_missYouSent => 'Miss you sent!';

  @override
  String get settings_notificationsTitle => 'Notifications';

  @override
  String get settings_notificationsSubtitle => 'Activity & neural reminders';

  @override
  String get settings_darkModeTitle => 'Dark Mode';

  @override
  String get settings_darkModeSubtitle => 'Violet-punk optimized';

  @override
  String get profile_connected => 'CONNECTED';

  @override
  String get profile_coreConnectionSection => 'CORE CONNECTION';

  @override
  String get profile_debugUtilitiesSection => 'DEBUG UTILITIES';

  @override
  String get profile_yourPartnerCodeTitle => 'Your Partner Code';

  @override
  String get profile_changePasswordSubtitle => 'Secure your shared space';

  @override
  String get profile_anniversaryTitle => 'Anniversary';

  @override
  String get profile_anniversaryEmpty => 'Set your special date';

  @override
  String get profile_wipeDataTitle => 'Wipe App Data';

  @override
  String get profile_wipeDataSubtitle => 'Reset everything except account';

  @override
  String get profile_wipeConfirmTitle => 'WIPE ALL DATA?';

  @override
  String get profile_wipeConfirmContent =>
      'This will permanently delete all drive items, bucket list, games, and moods.\n\nLogin and connection will be preserved.';

  @override
  String get profile_wipeCancel => 'CANCEL';

  @override
  String get profile_wipeConfirm => 'WIPE EVERYTHING';

  @override
  String get profile_dataWiped => 'Data wiped. Re-syncing...';

  @override
  String get profile_disconnectSession => 'DISCONNECT SESSION';

  @override
  String get partner_title => 'Who are you connecting\nwith today?';

  @override
  String get partner_connected => 'CONNECTED';

  @override
  String get partner_newConnection => 'New Connection';

  @override
  String get partner_addPartner => 'Add a partner';

  @override
  String get partner_receivedRequests => 'RECEIVED REQUESTS';

  @override
  String get partner_sentRequests => 'SENT REQUESTS';

  @override
  String get partner_noPendingInvites => 'No pending invites';

  @override
  String get partner_logout => 'Logout';

  @override
  String get partner_acceptError => 'Error accepting the invitation';

  @override
  String get partner_personalCodeTitle => 'YOUR PERSONAL CODE';

  @override
  String get partner_codeCopied => 'Code copied to clipboard!';

  @override
  String get partner_personalCodeSubtitle =>
      'Send this code to your partner to connect on JustUS!';

  @override
  String get partner_inviteTitle => 'Invite Partner';

  @override
  String get partner_inviteDescription =>
      'Enter your partner\'s email and code to send a request.';

  @override
  String get partner_emailLabel => 'PARTNER EMAIL';

  @override
  String get partner_emailHint => 'partner@example.com';

  @override
  String get partner_codeLabel => 'PARTNER CODE';

  @override
  String get partner_codeHint => 'ABC123';

  @override
  String get partner_send => 'Send';

  @override
  String get partner_fillAllFields => 'Fill in all fields';

  @override
  String get partner_inviteSuccess => 'Invitation sent successfully!';

  @override
  String get partner_wantsToConnect => 'Wants to connect';

  @override
  String get partner_waitingResponse => 'Waiting for response';

  @override
  String get partner_acceptTooltip => 'Accept';

  @override
  String get partner_declineTooltip => 'Decline';

  @override
  String get partner_cancelRequestTooltip => 'Cancel Request';

  @override
  String get partner_requestButton => 'Request';

  @override
  String get drive_title => 'Our Memories';

  @override
  String get drive_subtitle => 'VIOLET ARCHIVE';

  @override
  String get drive_select => 'SELECT';

  @override
  String get drive_filterAll => 'All';

  @override
  String get drive_filterPhotos => 'Photos';

  @override
  String get drive_filterVideos => 'Videos';

  @override
  String get drive_filterLikes => 'Likes';

  @override
  String get drive_latestVibes => 'LATEST VIBES';

  @override
  String get drive_emptyTitle => 'No Vibes Yet';

  @override
  String get drive_uploading => 'Uploading...';

  @override
  String get drive_invalidMediaUrl => 'Invalid media URL';

  @override
  String get drive_deleteTitle => 'Delete';

  @override
  String get drive_deleteConfirm => 'Do you want to delete this item?';

  @override
  String get drive_videoError => 'Video error';

  @override
  String get drive_audioError => 'Audio error';

  @override
  String get drive_favoritesTitle => 'Favorites';

  @override
  String get drive_noFavorites => 'No favorites';

  @override
  String get drive_noFavoritesSubtitle =>
      'Add photos and videos to favorites from Drive!';

  @override
  String get drive_takePhoto => 'Take Photo';

  @override
  String get drive_fromGallery => 'From Gallery';

  @override
  String get drive_uploadComplete => 'Upload complete!';

  @override
  String get drive_deleted => 'Deleted!';

  @override
  String get drive_uploadInProgress => 'Upload in progress…';

  @override
  String get bucket_categoryAll => 'All';

  @override
  String get bucket_categoryTravel => 'Travel';

  @override
  String get bucket_categoryDates => 'Dates';

  @override
  String get bucket_categoryGoals => 'Goals';

  @override
  String get bucket_categoryCrazy => 'Crazy';

  @override
  String get bucket_categoryAdventure => 'Adventure';

  @override
  String get bucket_categoryRomantic => 'Romantic';

  @override
  String get bucket_categoryHomemade => 'Homemade';

  @override
  String get bucket_addGoalTitle => 'Add goal';

  @override
  String get bucket_goalHint => 'What do you want to do together?';

  @override
  String get bucket_categoryLabel => 'Category:';

  @override
  String get bucket_add => 'Add';

  @override
  String get bucket_title => 'Our Bucket List';

  @override
  String get bucket_emptyAll => 'No goals in the bucket list.\nAdd one!';

  @override
  String get bucket_emptyCategory => 'No goals in this category.';

  @override
  String get bucket_enterText => 'Enter some text';

  @override
  String get bucket_addError => 'Error while adding';

  @override
  String get bucket_updateError => 'Error updating item';

  @override
  String get mood_boardTitle => 'Mood Board';

  @override
  String get mood_recents => 'YOUR RECENTS';

  @override
  String get mood_edit => 'Edit';

  @override
  String get mood_howFeeling => 'How are you feeling?';

  @override
  String get mood_timeline => 'Timeline';

  @override
  String get mood_today => 'Today';

  @override
  String get mood_sheetTitle => 'Choose your Mood';

  @override
  String get mood_enterEmoji => 'Enter an emoji';

  @override
  String get mood_enterSingleEmoji => 'Enter a single emoji';

  @override
  String get mood_emojiHint => 'Enter an emoji...';

  @override
  String get mood_duplicateTechnicalMessage =>
      'User tried to re-enter the current mood.';

  @override
  String get mood_updated => 'Mood updated!';

  @override
  String get mood_noneSet => 'No mood set';

  @override
  String get mood_showMore => 'Show more';

  @override
  String get game_historyTitle => 'HISTORY';

  @override
  String get game_noMatches => 'No matches yet. Answer the daily question!';

  @override
  String get game_statusBothAgreed => 'You both agreed!';

  @override
  String get game_statusDisagreed => 'A playful disagreement';

  @override
  String get game_statusWaiting => 'Waiting for partner';

  @override
  String get game_statusWaitingForYou => 'Waiting for your answer';

  @override
  String get game_dailyGame => 'DAILY GAME';

  @override
  String get game_generatingQuestion => 'Generating the question...';

  @override
  String get game_aiGeneratingSubtitle =>
      'AI is creating something special for you';

  @override
  String get game_questionOfDay => 'Question of the Day';

  @override
  String get game_allCaughtUp => 'You\'re all caught up!';

  @override
  String get game_tryFetchingAgain => 'Try Fetching Again';

  @override
  String get game_invalidOption => 'Error: invalid option';

  @override
  String get game_answerSent => 'Answer sent!';

  @override
  String get game_waitPartner => 'Wait for your partner to answer';

  @override
  String get game_noQuestionAvailable => 'No question available';

  @override
  String get game_noActivePartnership => 'No active partnership found';

  @override
  String get game_aiGenerationError => 'AI generation error';

  @override
  String get update_availableTitle => 'Update available!';

  @override
  String get update_newVersion => 'A new version of JustUs is available.';

  @override
  String get update_changelogTitle => 'What’s new:';

  @override
  String get update_later => 'Later';

  @override
  String get update_now => 'Update now';

  @override
  String get logout_title => 'Disconnect Session';

  @override
  String get logout_message => 'End your current session?';

  @override
  String get logout_cancel => 'Cancel';

  @override
  String get logout_confirm => 'Disconnect';

  @override
  String get error_dialogTitle => 'Error';

  @override
  String get error_codePrefix => 'Code:';

  @override
  String get error_reauthTitle => 'Session expired';

  @override
  String get error_reauthAction => 'Login again';

  @override
  String get error_unknownApi => 'Unknown API error';

  @override
  String get error_noDataReturned => 'No data returned';

  @override
  String get error_malformedResponse => 'Malformed error response';

  @override
  String get error_networkUnavailable => 'Network unavailable';

  @override
  String get error_operationTimedOut => 'Operation timed out';

  @override
  String get error_sessionExpiredLoginAgain =>
      'Session expired. Please login again.';

  @override
  String get error_requestTimeout =>
      'Request timed out. Check your connection.';

  @override
  String error_connection(String message) {
    return 'Connection error: $message';
  }

  @override
  String get error_authFail001 => 'Session expired. Please login again.';

  @override
  String get error_authFail002 => 'Invalid session. Please login.';

  @override
  String get error_authFail003 => 'Session was revoked. Please login again.';

  @override
  String get error_authFail004 => 'Access not allowed.';

  @override
  String get error_authFail005 => 'User profile not found.';

  @override
  String get error_authFail006 => 'Unrecognized device. Please login again.';

  @override
  String get error_authPermission001 =>
      'You do not have permission for this action.';

  @override
  String get error_dbRead001 => 'Error loading data.';

  @override
  String get error_dbWrite001 => 'Error while saving.';

  @override
  String get error_dbNotFound001 => 'Resource not found.';

  @override
  String get error_dbTimeout001 => 'The server is slow. Try again shortly.';

  @override
  String get error_apiValidation001 => 'The entered data is invalid.';

  @override
  String get error_apiNotFound001 => 'Service unavailable.';

  @override
  String get error_apiTimeout001 => 'The request took too long. Try again.';

  @override
  String get error_apiFail001 => 'Something went wrong. Try again.';

  @override
  String get error_secBlock001 =>
      'Too many requests. Wait before trying again.';

  @override
  String get error_secBlock002 => 'Access temporarily blocked.';

  @override
  String get error_secPermission001 => 'Access denied.';

  @override
  String get error_sysFail001 => 'Internal server error.';

  @override
  String get error_localNetworkError => 'No internet connection.';

  @override
  String get error_localTimeout001 => 'The connection is too slow. Try again.';

  @override
  String get error_localParseError => 'Invalid server response.';

  @override
  String get error_localStorageError => 'Error saving local data.';

  @override
  String get error_localConfigError => 'App configuration error.';

  @override
  String get error_localMoodDuplicate =>
      'You already set this emoji as your current mood.';

  @override
  String get error_unknown => 'An unexpected error occurred.';

  @override
  String auth_confirmEmailMessage(String email) {
    return 'We sent a confirmation link to $email.\n\nClick the link to activate your account, then come back here to sign in.';
  }

  @override
  String auth_validationRequired(String fieldName) {
    return '$fieldName is required';
  }

  @override
  String profile_shareToConnect(String code) {
    return 'Share to connect: $code';
  }

  @override
  String profile_copiedCode(String code) {
    return 'Copied: $code';
  }

  @override
  String profile_appVersion(String version) {
    return 'JustUS OS $version';
  }

  @override
  String bucket_createdOn(String date) {
    return 'Created on: $date';
  }
}
