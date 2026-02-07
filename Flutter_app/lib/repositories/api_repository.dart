// =============================================================================
// ApiRepository - Repository layer for API calls
// Dart equivalent of ApiRepository.kt
// =============================================================================

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/result_wrapper.dart';

class ApiRepository {
  final ApiService _api = ApiService();

  // -------------------- Auth / User --------------------

  Future<ResultWrapper<LoginResponse>> loginUser(
    String usernameWithCode,
    String password,
    String deviceToken,
  ) async {
    return _api.login(LoginRequestBody(
      usernameWithCode: usernameWithCode,
      password: password,
      deviceToken: deviceToken,
    ));
  }

  Future<ResultWrapper<RegisterResponse>> registerUser(
    String username,
    String password,
    String? email,
    String deviceToken,
  ) async {
    return _api.register(RegisterRequestBody(
      username: username,
      password: password,
      email: email,
      deviceToken: deviceToken,
    ));
  }

  Future<ResultWrapper<RequestCodesResponse>> requestUserCodes(
    String username,
    String password,
  ) async {
    return _api.requestUserCodes(RequestCodesBody(
      username: username,
      password: password,
    ));
  }

  Future<ResultWrapper<void>> updateDeviceToken(
    String usernameWithCode,
    String deviceToken,
  ) async {
    final result = await _api.updateDeviceToken(UpdateTokenRequest(
      usernameWithCode: usernameWithCode,
      deviceToken: deviceToken,
    ));

    return switch (result) {
      Success() => const Success(null),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  // -------------------- Profile --------------------

  Future<ResultWrapper<User>> fetchProfile() async {
    final result = await _api.getProfile();
    return switch (result) {
      Success(:final value) => value.profile != null
          ? Success(value.profile!)
          : const GenericError(message: 'Profilo non trovato'),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<User>> fetchPartnerProfile() async {
    final result = await _api.getPartnerProfile();
    return switch (result) {
      Success(:final value) => value.profile != null
          ? Success(value.profile!)
          : const GenericError(message: 'Profilo partner non trovato'),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<void>> updateProfileBio(String? bio) async {
    final result = await _api.updateProfile(UpdateProfileRequest(bio: bio));
    return switch (result) {
      Success() => const Success(null),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<void>> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    final result = await _api.changePassword(ChangePasswordRequest(
      oldPassword: oldPassword,
      newPassword: newPassword,
    ));
    return switch (result) {
      Success() => const Success(null),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  // -------------------- Partnership --------------------

  Future<ResultWrapper<void>> sendPartnerRequest(
    String partnerUsername,
    String partnerCode,
  ) async {
    final result = await _api.sendPartnerRequest(PartnerRequestBody(
      partnerUsername: partnerUsername,
      partnerCode: partnerCode,
    ));
    return switch (result) {
      Success() => const Success(null),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<void>> acceptPartnerRequest(int requesterId) async {
    final result = await _api.acceptPartnerRequest(AcceptRequestBody(requesterId: requesterId));
    return switch (result) {
      Success() => const Success(null),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<void>> rejectPartnerRequest(int requesterId) async {
    final result = await _api.rejectPartnerRequest(AcceptRequestBody(requesterId: requesterId));
    return switch (result) {
      Success() => const Success(null),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<List<User>>> searchPartner(String? username, String? code) async {
    final result = await _api.searchPartner(username: username, code: code);
    return switch (result) {
      Success(:final value) => Success(value.users),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return _api.getPartnership();
  }

  // -------------------- MissYou / Mood --------------------

  Future<ResultWrapper<int>> sendMissYou() async {
    final result = await _api.sendMissYou();
    return switch (result) {
      Success(:final value) => Success(value.total),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<int>> fetchMissYouTotal() async {
    final result = await _api.getMissYouTotal();
    return switch (result) {
      Success(:final value) => Success(value.total),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<MoodResponse>> setMood(String emoji) async {
    return _api.setMood(MoodRequest(emoji: emoji));
  }

  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    return _api.getMood('me');
  }

  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    return _api.getMood('partner');
  }

  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    final result = await _api.getRecentGlobalEmojis();
    return switch (result) {
      Success(:final value) => Success(value.emojis),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  // -------------------- BucketList --------------------

  Future<ResultWrapper<BucketListResponse>> fetchBucketList() async {
    return _api.getBucket();
  }

  Future<ResultWrapper<GenericResponse>> addBucketItem(String text) async {
    return _api.addBucketItem(AddBucketRequest(text: text));
  }

  Future<ResultWrapper<GenericResponse>> toggleBucketDone(int id) async {
    return _api.toggleBucketDone(id);
  }

  Future<ResultWrapper<GenericResponse>> deleteBucketItem(int id) async {
    return _api.deleteBucketItem(id);
  }

  // -------------------- Game --------------------

  Future<ResultWrapper<GameNewQuestionResponse>> fetchNewGameQuestion() async {
    return _api.getNewQuestion();
  }

  Future<ResultWrapper<void>> submitGameAnswer(int questionId, String votedFor) async {
    final result = await _api.submitAnswer(GameAnswerRequest(
      questionId: questionId,
      votedFor: votedFor,
    ));
    return switch (result) {
      Success() => const Success(null),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<GameStatsResponse>> fetchGameStats() async {
    return _api.getGameStats();
  }

  // -------------------- Drive / Upload --------------------

  Future<ResultWrapper<DriveListResponse>> fetchDriveItems() async {
    return _api.getDriveItems();
  }

  Future<ResultWrapper<DriveSingleResponse>> createDriveItem(
    String type,
    String? content,
    Map<String, dynamic>? metadata,
  ) async {
    return _api.addDriveItem(DriveItemRequest(
      type: type,
      content: content,
      metadata: metadata,
    ));
  }

  Future<ResultWrapper<GenericResponse>> deleteDriveItem(int id) async {
    return _api.deleteDriveItem(id);
  }

  Future<ResultWrapper<DriveSyncResponse>> fetchDriveChanges(String? lastSync) async {
    return _api.getDriveChanges(lastSync: lastSync);
  }

  // -------------------- Reactions --------------------

  Future<ResultWrapper<DriveItemReactionResponse>> addReaction(int itemId, String emoji) async {
    return _api.addDriveReaction(itemId, DriveItemReaction(emoji: emoji));
  }

  Future<ResultWrapper<DriveItemReactionsListResponse>> fetchReactions(int itemId) async {
    return _api.getDriveReactions(itemId);
  }

  // -------------------- Favorite --------------------

  Future<ResultWrapper<GenericResponse>> addFavorite(int itemId) async {
    return _api.addFavorite(itemId);
  }

  Future<ResultWrapper<GenericResponse>> removeFavorite(int itemId) async {
    return _api.removeFavorite(itemId);
  }

  // -------------------- Upload --------------------

  Future<ResultWrapper<String>> uploadProfile(
    List<int> fileBytes,
    String fileName,
    String mimeType,
  ) async {
    final result = await _api.uploadFile(
      route: '/upload/profile',
      fileBytes: fileBytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    return switch (result) {
      Success(:final value) => Success(value.url),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  Future<ResultWrapper<String>> uploadDiary(
    List<int> fileBytes,
    String fileName,
    String mimeType,
  ) async {
    final result = await _api.uploadFile(
      route: '/upload/diary',
      fileBytes: fileBytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    return switch (result) {
      Success(:final value) => Success(value.url),
      GenericError(:final code, :final message) => GenericError(code: code, message: message),
      NetworkError() => const NetworkError(),
    };
  }

  // -------------------- App Version --------------------

  Future<ResultWrapper<AppVersionResponse>> checkAppVersion() async {
    return _api.getAppVersion();
  }

  void dispose() {
    _api.dispose();
  }
}
