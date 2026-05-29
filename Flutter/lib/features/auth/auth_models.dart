// =============================================================================
// JustUs App - Auth Models
// =============================================================================

abstract class AuthModels {}

class User {
  final int id;
  final String? email;
  final String? authId;
  final String? createdAt;
  // Joined from user_profiles (via v_active_partnership or explicit join)
  final String? displayName;
  final String? profilePicUrl;
  final String? bio;
  final String? partnershipCode;

  User({
    required this.id,
    this.email,
    this.authId,
    this.createdAt,
    this.displayName,
    this.profilePicUrl,
    this.bio,
    this.partnershipCode,
  });

  /// Convenience getter: display name falls back to email prefix
  String get username => displayName ?? email?.split('@').first ?? 'User';

  factory User.fromJson(Map<String, dynamic> json) {
    // Support both flat (joined) and nested (profile sub-object) formats
    final profile = json['user_profiles'] as Map<String, dynamic>?;

    return User(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email'] as String?,
      authId: json['auth_id'] as String?,
      createdAt: json['created_at'] as String?,
      displayName: (profile?['display_name'] ??
          json['display_name'] ??
          json['username']) as String?,
      profilePicUrl:
          (profile?['profile_pic_url'] ?? json['profile_pic_url']) as String?,
      bio: (profile?['bio'] ?? json['bio']) as String?,
      partnershipCode:
          (profile?['partnership_code'] ?? json['partnership_code']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'auth_id': authId,
      'created_at': createdAt,
      'display_name': displayName,
      'profile_pic_url': profilePicUrl,
      'bio': bio,
      'partnership_code': partnershipCode,
    };
  }

  User copyWith({
    int? id,
    String? email,
    String? authId,
    String? createdAt,
    String? displayName,
    String? profilePicUrl,
    String? bio,
    String? partnershipCode,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      authId: authId ?? this.authId,
      createdAt: createdAt ?? this.createdAt,
      displayName: displayName ?? this.displayName,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      bio: bio ?? this.bio,
      partnershipCode: partnershipCode ?? this.partnershipCode,
    );
  }
}

class UpdateTokenRequest {
  final String deviceToken;
  final String? deviceType;

  UpdateTokenRequest({required this.deviceToken, this.deviceType});

  Map<String, dynamic> toJson() => {
        'deviceToken': deviceToken,
        'deviceType': deviceType,
      };
}

class UpdateTokenResponse {
  final bool success;
  final String? error;

  UpdateTokenResponse({required this.success, this.error});

  factory UpdateTokenResponse.fromJson(Map<String, dynamic> json) {
    return UpdateTokenResponse(
      success: (json['success'] as bool?) ?? false,
      error: json['error'] as String?,
    );
  }
}
