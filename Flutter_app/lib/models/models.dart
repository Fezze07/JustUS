// =============================================================================
// JustUs App - Data Models
// Dart equivalents of Kotlin data classes from Models.kt
// =============================================================================

// -------------------- Generic --------------------

class GenericResponse {
  final bool success;
  final String? error;

  GenericResponse({required this.success, this.error});

  factory GenericResponse.fromJson(Map<String, dynamic> json) {
    return GenericResponse(
      success: json['success'] ?? false,
      error: json['error'],
    );
  }
}

// -------------------- Auth --------------------

class LoginResponse {
  final bool success;
  final String? message;
  final String? token;
  final User? user;
  final String? error;

  LoginResponse({
    required this.success,
    this.message,
    this.token,
    this.user,
    this.error,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      success: json['success'] ?? false,
      message: json['message'],
      token: json['token'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      error: json['error'],
    );
  }
}

class User {
  final int id;
  final String username;
  final String code;
  final String? email;
  final String? bio;
  final String? profilePicUrl;

  User({
    required this.id,
    required this.username,
    required this.code,
    this.email,
    this.bio,
    this.profilePicUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      code: json['code'] ?? '',
      email: json['email'],
      bio: json['bio'],
      profilePicUrl: json['profile_pic_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'code': code,
      'email': email,
      'bio': bio,
      'profile_pic_url': profilePicUrl,
    };
  }

  User copyWith({
    int? id,
    String? username,
    String? code,
    String? email,
    String? bio,
    String? profilePicUrl,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      code: code ?? this.code,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
    );
  }
}

class LoginRequestBody {
  final String usernameWithCode;
  final String password;
  final String deviceToken;

  LoginRequestBody({
    required this.usernameWithCode,
    required this.password,
    required this.deviceToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'usernameWithCode': usernameWithCode,
      'password': password,
      'deviceToken': deviceToken,
    };
  }
}

class RegisterRequestBody {
  final String username;
  final String password;
  final String? email;
  final String deviceToken;

  RegisterRequestBody({
    required this.username,
    required this.password,
    this.email,
    required this.deviceToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'email': email,
      'deviceToken': deviceToken,
    };
  }
}

class RegisterResponse {
  final bool success;
  final String? message;
  final User? user;
  final String? error;

  RegisterResponse({
    required this.success,
    this.message,
    this.user,
    this.error,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) {
    return RegisterResponse(
      success: json['success'] ?? false,
      message: json['message'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      error: json['error'],
    );
  }
}

class RequestCodesBody {
  final String username;
  final String password;

  RequestCodesBody({required this.username, required this.password});

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
    };
  }
}

class RequestCodesResponse {
  final bool ok;
  final List<String>? codes;
  final String? msg;

  RequestCodesResponse({required this.ok, this.codes, this.msg});

  factory RequestCodesResponse.fromJson(Map<String, dynamic> json) {
    return RequestCodesResponse(
      ok: json['ok'] ?? false,
      codes: json['codes'] != null ? List<String>.from(json['codes']) : null,
      msg: json['msg'],
    );
  }
}

class UpdateTokenRequest {
  final String usernameWithCode;
  final String deviceToken;

  UpdateTokenRequest({
    required this.usernameWithCode,
    required this.deviceToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'usernameWithCode': usernameWithCode,
      'deviceToken': deviceToken,
    };
  }
}

class UpdateTokenResponse {
  final bool success;
  final String? error;

  UpdateTokenResponse({required this.success, this.error});

  factory UpdateTokenResponse.fromJson(Map<String, dynamic> json) {
    return UpdateTokenResponse(
      success: json['success'] ?? false,
      error: json['error'],
    );
  }
}

// -------------------- Profile --------------------

class ProfileResponse {
  final bool success;
  final User? profile;
  final String? message;
  final String? error;

  ProfileResponse({
    required this.success,
    this.profile,
    this.message,
    this.error,
  });

  factory ProfileResponse.fromJson(Map<String, dynamic> json) {
    return ProfileResponse(
      success: json['success'] ?? false,
      profile: json['profile'] != null ? User.fromJson(json['profile']) : null,
      message: json['message'],
      error: json['error'],
    );
  }
}

class UpdateProfileRequest {
  final String? bio;

  UpdateProfileRequest({this.bio});

  Map<String, dynamic> toJson() {
    return {'bio': bio};
  }
}

class ChangePasswordRequest {
  final String oldPassword;
  final String newPassword;

  ChangePasswordRequest({
    required this.oldPassword,
    required this.newPassword,
  });

  Map<String, dynamic> toJson() {
    return {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    };
  }
}

// -------------------- Partnership --------------------

class PartnershipResponse {
  final bool success;
  final User? partner;
  final PendingRequests? pendingRequests;
  final String? message;
  final String? error;

  PartnershipResponse({
    required this.success,
    this.partner,
    this.pendingRequests,
    this.message,
    this.error,
  });

  bool hasAcceptedPartner() => partner != null;

  factory PartnershipResponse.fromJson(Map<String, dynamic> json) {
    return PartnershipResponse(
      success: json['success'] ?? false,
      partner: json['partner'] != null ? User.fromJson(json['partner']) : null,
      pendingRequests: json['pendingRequests'] != null
          ? PendingRequests.fromJson(json['pendingRequests'])
          : null,
      message: json['message'],
      error: json['error'],
    );
  }

  PartnershipResponse copyWith({
    bool? success,
    User? partner,
    PendingRequests? pendingRequests,
    String? message,
    String? error,
  }) {
    return PartnershipResponse(
      success: success ?? this.success,
      partner: partner ?? this.partner,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      message: message ?? this.message,
      error: error ?? this.error,
    );
  }
}

class PendingRequests {
  final List<User> received;
  final List<User> sent;

  PendingRequests({this.received = const [], this.sent = const []});

  factory PendingRequests.fromJson(Map<String, dynamic> json) {
    return PendingRequests(
      received: json['received'] != null
          ? (json['received'] as List).map((e) => User.fromJson(e)).toList()
          : [],
      sent: json['sent'] != null
          ? (json['sent'] as List).map((e) => User.fromJson(e)).toList()
          : [],
    );
  }

  PendingRequests copyWith({
    List<User>? received,
    List<User>? sent,
  }) {
    return PendingRequests(
      received: received ?? this.received,
      sent: sent ?? this.sent,
    );
  }
}

class PartnerRequestBody {
  final String partnerUsername;
  final String partnerCode;

  PartnerRequestBody({
    required this.partnerUsername,
    required this.partnerCode,
  });

  Map<String, dynamic> toJson() {
    return {
      'partner_username': partnerUsername,
      'partner_code': partnerCode,
    };
  }
}

class SearchPartnerResponse {
  final bool success;
  final List<User> users;

  SearchPartnerResponse({required this.success, required this.users});

  factory SearchPartnerResponse.fromJson(Map<String, dynamic> json) {
    return SearchPartnerResponse(
      success: json['success'] ?? false,
      users: json['users'] != null
          ? (json['users'] as List).map((e) => User.fromJson(e)).toList()
          : [],
    );
  }
}

class AcceptRequestBody {
  final int requesterId;

  AcceptRequestBody({required this.requesterId});

  Map<String, dynamic> toJson() {
    return {'requester_id': requesterId};
  }
}

// -------------------- MissYou / Mood --------------------

class MissYouResponse {
  final bool success;
  final int total;

  MissYouResponse({required this.success, required this.total});

  factory MissYouResponse.fromJson(Map<String, dynamic> json) {
    return MissYouResponse(
      success: json['success'] ?? false,
      total: json['total'] ?? 0,
    );
  }
}

class MoodResponse {
  final bool success;
  final String? emoji;

  MoodResponse({required this.success, this.emoji});

  factory MoodResponse.fromJson(Map<String, dynamic> json) {
    return MoodResponse(
      success: json['success'] ?? false,
      emoji: json['emoji'],
    );
  }
}

class MoodRequest {
  final String emoji;

  MoodRequest({required this.emoji});

  Map<String, dynamic> toJson() {
    return {'emoji': emoji};
  }
}

class EmojiResponse {
  final List<String> emojis;

  EmojiResponse({required this.emojis});

  factory EmojiResponse.fromJson(Map<String, dynamic> json) {
    return EmojiResponse(
      emojis: json['emojis'] != null ? List<String>.from(json['emojis']) : [],
    );
  }
}

// -------------------- Bucket List --------------------

class BucketItem {
  final int id;
  final String text;
  final int done;
  final String createdAt;

  BucketItem({
    required this.id,
    required this.text,
    required this.done,
    required this.createdAt,
  });

  factory BucketItem.fromJson(Map<String, dynamic> json) {
    return BucketItem(
      id: json['id'] ?? 0,
      text: json['text'] ?? '',
      done: json['done'] ?? 0,
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'done': done,
      'created_at': createdAt,
    };
  }

  BucketItem copyWith({
    int? id,
    String? text,
    int? done,
    String? createdAt,
  }) {
    return BucketItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class BucketListResponse {
  final bool success;
  final List<BucketItem> items;

  BucketListResponse({required this.success, required this.items});

  factory BucketListResponse.fromJson(Map<String, dynamic> json) {
    return BucketListResponse(
      success: json['success'] ?? false,
      items: json['items'] != null
          ? (json['items'] as List).map((e) => BucketItem.fromJson(e)).toList()
          : [],
    );
  }
}

class AddBucketRequest {
  final String text;

  AddBucketRequest({required this.text});

  Map<String, dynamic> toJson() {
    return {'text': text};
  }
}

// -------------------- Game --------------------

class GameAnswerRequest {
  final int questionId;
  final String votedFor; // "A" or "B"

  GameAnswerRequest({required this.questionId, required this.votedFor});

  Map<String, dynamic> toJson() {
    return {
      'questionId': questionId,
      'votedFor': votedFor,
    };
  }
}

class GameStatsResponse {
  final bool success;
  final int totalMatches;

  GameStatsResponse({required this.success, required this.totalMatches});

  factory GameStatsResponse.fromJson(Map<String, dynamic> json) {
    return GameStatsResponse(
      success: json['success'] ?? false,
      totalMatches: json['totalMatches'] ?? 0,
    );
  }
}

class GameNewQuestionResponse {
  final bool success;
  final int id;
  final String question;
  final String optionA;
  final String optionB;
  final String? status;
  final String? message;

  GameNewQuestionResponse({
    required this.success,
    required this.id,
    required this.question,
    required this.optionA,
    required this.optionB,
    this.status,
    this.message,
  });

  factory GameNewQuestionResponse.fromJson(Map<String, dynamic> json) {
    return GameNewQuestionResponse(
      success: json['success'] ?? false,
      id: json['id'] ?? 0,
      question: json['question'] ?? '',
      optionA: json['optionA'] ?? '',
      optionB: json['optionB'] ?? '',
      status: json['status'],
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'id': id,
      'question': question,
      'optionA': optionA,
      'optionB': optionB,
      'status': status,
      'message': message,
    };
  }

  GameNewQuestionResponse copyWith({
    bool? success,
    int? id,
    String? question,
    String? optionA,
    String? optionB,
    String? status,
    String? message,
  }) {
    return GameNewQuestionResponse(
      success: success ?? this.success,
      id: id ?? this.id,
      question: question ?? this.question,
      optionA: optionA ?? this.optionA,
      optionB: optionB ?? this.optionB,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

// -------------------- Drive --------------------

class DriveItem {
  final int id;
  final String type;
  final String content;
  final Map<String, String>? metadata;
  final List<String> reactions;
  final String createdAt;
  final String updatedAt;
  final int isFavorite; // 0 or 1

  DriveItem({
    required this.id,
    required this.type,
    required this.content,
    this.metadata,
    this.reactions = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.isFavorite,
  });

  factory DriveItem.fromJson(Map<String, dynamic> json) {
    return DriveItem(
      id: json['id'] ?? 0,
      type: json['type'] ?? '',
      content: json['content'] ?? '',
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
              .map((key, value) => MapEntry(key, value.toString()))
          : null,
      reactions: json['reactions'] != null
          ? List<String>.from(json['reactions'])
          : [],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      isFavorite: json['is_favorite'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'content': content,
      'metadata': metadata,
      'reactions': reactions,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_favorite': isFavorite,
    };
  }

  DriveItem copyWith({
    int? id,
    String? type,
    String? content,
    Map<String, String>? metadata,
    List<String>? reactions,
    String? createdAt,
    String? updatedAt,
    int? isFavorite,
  }) {
    return DriveItem(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class DriveItemRequest {
  final String type;
  final String? content;
  final Map<String, dynamic>? metadata;

  DriveItemRequest({
    required this.type,
    this.content,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'content': content,
      'metadata': metadata,
    };
  }
}

class DriveListResponse {
  final bool success;
  final List<DriveItem> items;

  DriveListResponse({required this.success, required this.items});

  factory DriveListResponse.fromJson(Map<String, dynamic> json) {
    return DriveListResponse(
      success: json['success'] ?? false,
      items: json['items'] != null
          ? (json['items'] as List).map((e) => DriveItem.fromJson(e)).toList()
          : [],
    );
  }
}

class DriveSingleResponse {
  final bool success;
  final DriveItem item;

  DriveSingleResponse({required this.success, required this.item});

  factory DriveSingleResponse.fromJson(Map<String, dynamic> json) {
    return DriveSingleResponse(
      success: json['success'] ?? false,
      item: DriveItem.fromJson(json['item'] ?? {}),
    );
  }
}

class FileUploadResponse {
  final bool success;
  final String url;
  final String? originalName;
  final int? size;
  final String? mime;

  FileUploadResponse({
    required this.success,
    required this.url,
    this.originalName,
    this.size,
    this.mime,
  });

  factory FileUploadResponse.fromJson(Map<String, dynamic> json) {
    return FileUploadResponse(
      success: json['success'] ?? false,
      url: json['url'] ?? '',
      originalName: json['originalName'],
      size: json['size'],
      mime: json['mime'],
    );
  }
}

class DriveChange {
  final int id;
  final String action; // "create", "update", "delete"
  final DriveItem? item;

  DriveChange({
    required this.id,
    required this.action,
    this.item,
  });

  factory DriveChange.fromJson(Map<String, dynamic> json) {
    return DriveChange(
      id: json['id'] ?? 0,
      action: json['action'] ?? '',
      item: json['item'] != null ? DriveItem.fromJson(json['item']) : null,
    );
  }
}

class DriveSyncResponse {
  final bool success;
  final List<DriveChange> changes;
  final String lastSync;

  DriveSyncResponse({
    required this.success,
    required this.changes,
    required this.lastSync,
  });

  factory DriveSyncResponse.fromJson(Map<String, dynamic> json) {
    return DriveSyncResponse(
      success: json['success'] ?? false,
      changes: json['changes'] != null
          ? (json['changes'] as List)
              .map((e) => DriveChange.fromJson(e))
              .toList()
          : [],
      lastSync: json['lastSync'] ?? '',
    );
  }
}

class DriveItemReaction {
  final String emoji;

  DriveItemReaction({required this.emoji});

  Map<String, dynamic> toJson() {
    return {'emoji': emoji};
  }

  factory DriveItemReaction.fromJson(Map<String, dynamic> json) {
    return DriveItemReaction(emoji: json['emoji'] ?? '');
  }
}

class DriveItemReactionCount {
  final String emoji;
  final int total;

  DriveItemReactionCount({required this.emoji, required this.total});

  factory DriveItemReactionCount.fromJson(Map<String, dynamic> json) {
    return DriveItemReactionCount(
      emoji: json['emoji'] ?? '',
      total: json['total'] ?? 0,
    );
  }
}

class DriveItemReactionResponse {
  final bool success;
  final List<DriveItemReactionCount> counts;

  DriveItemReactionResponse({required this.success, required this.counts});

  factory DriveItemReactionResponse.fromJson(Map<String, dynamic> json) {
    return DriveItemReactionResponse(
      success: json['success'] ?? false,
      counts: json['counts'] != null
          ? (json['counts'] as List)
              .map((e) => DriveItemReactionCount.fromJson(e))
              .toList()
          : [],
    );
  }
}

class DriveItemReactionsListResponse {
  final bool success;
  final List<DriveItemReaction> reactions;

  DriveItemReactionsListResponse({
    required this.success,
    required this.reactions,
  });

  factory DriveItemReactionsListResponse.fromJson(Map<String, dynamic> json) {
    return DriveItemReactionsListResponse(
      success: json['success'] ?? false,
      reactions: json['reactions'] != null
          ? (json['reactions'] as List)
              .map((e) => DriveItemReaction.fromJson(e))
              .toList()
          : [],
    );
  }
}

// -------------------- Notifications --------------------

class NotificationRequest {
  final int receiverId;
  final String title;
  final String body;

  NotificationRequest({
    required this.receiverId,
    required this.title,
    required this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'receiverId': receiverId,
      'title': title,
      'body': body,
    };
  }
}

class PartnerNotificationRequest {
  final String type;
  final String username;
  final String code;
  final String title;
  final String body;

  PartnerNotificationRequest({
    required this.type,
    required this.username,
    required this.code,
    required this.title,
    required this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'username': username,
      'code': code,
      'title': title,
      'body': body,
    };
  }
}

class NotificationResponse {
  final bool success;
  final String? message;
  final String? error;

  NotificationResponse({required this.success, this.message, this.error});

  factory NotificationResponse.fromJson(Map<String, dynamic> json) {
    return NotificationResponse(
      success: json['success'] ?? false,
      message: json['message'],
      error: json['error'],
    );
  }
}

// -------------------- App Version --------------------

class AppVersionResponse {
  final String version;
  final String apkUrl;
  final String changelog;

  AppVersionResponse({
    required this.version,
    required this.apkUrl,
    required this.changelog,
  });

  factory AppVersionResponse.fromJson(Map<String, dynamic> json) {
    return AppVersionResponse(
      version: json['version'] ?? '',
      apkUrl: json['apk_url'] ?? '',
      changelog: json['changelog'] ?? '',
    );
  }
}
