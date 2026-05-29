// =============================================================================
// JustUs App - Partnership Models
// =============================================================================

import 'package:justus/all_imports.dart';

abstract class PartnershipModels {}

/// Represents the full partnership view returned by v_active_partnership.
/// The view returns: partnership_id, status, anniversary_date,
/// partner_id, partner_display_name, partner_profile_pic_url,
/// pending_sent (jsonb array), pending_received (jsonb array).
class PartnershipResponse {
  final bool success;
  final int? partnershipId;
  final String status; // 'accepted' | 'pending' | 'none'
  final User? partner;
  final PendingRequests? pendingRequests;
  final String? message;
  final String? error;
  final DateTime? anniversaryDate;
  final int? userIdA;
  final int? userIdB;

  PartnershipResponse({
    required this.success,
    this.partnershipId,
    this.status = 'none',
    this.partner,
    this.pendingRequests,
    this.message,
    this.error,
    this.anniversaryDate,
    this.userIdA,
    this.userIdB,
  });

  bool hasAcceptedPartner() => partner != null && status == 'accepted';

  factory PartnershipResponse.fromJson(Map<String, dynamic> json) {
    // Parse from v_active_partnership view format
    User? partner;
    if (json['partner_id'] != null) {
      partner = User(
        id: (json['partner_id'] as num).toInt(),
        displayName: json['partner_display_name'] as String?,
        profilePicUrl: json['partner_profile_pic_url'] as String?,
        bio: json['partner_bio'] as String?,
      );
    }

    // Parse pending arrays from jsonb
    List<User> received = [];
    List<User> sent = [];
    User mapPendingUser(dynamic e) {
      final m = e as Map<String, dynamic>;

      return User(
        id: (m['user_id'] as num).toInt(),
        displayName: m['display_name'] as String?,
        email: m['email'] as String?,
      );
    }

    if (json['pending_received'] != null) {
      received = (json['pending_received'] as List<dynamic>)
          .map(mapPendingUser)
          .toList();
    }
    if (json['pending_sent'] != null) {
      sent = (json['pending_sent'] as List<dynamic>)
          .map(mapPendingUser)
          .toList();
    }

    return PartnershipResponse(
      success: (json['success'] as bool?) ?? true,
      partnershipId: (json['partnership_id'] as num?)?.toInt(),
      status: (json['status'] as String?) ?? 'none',
      partner: partner,
      pendingRequests: PendingRequests(received: received, sent: sent),
      message: json['message'] as String?,
      error: json['error'] as String?,
      anniversaryDate: AppDateUtils.tryParse(json['anniversary_date'] as String?),
      userIdA: (json['user_id_a'] as num?)?.toInt(),
      userIdB: (json['user_id_b'] as num?)?.toInt(),
    );
  }

  PartnershipResponse copyWith({
    bool? success,
    int? partnershipId,
    String? status,
    User? partner,
    PendingRequests? pendingRequests,
    String? message,
    String? error,
    DateTime? anniversaryDate,
  }) {
    return PartnershipResponse(
      success: success ?? this.success,
      partnershipId: partnershipId ?? this.partnershipId,
      status: status ?? this.status,
      partner: partner ?? this.partner,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      message: message ?? this.message,
      error: error ?? this.error,
      anniversaryDate: anniversaryDate ?? this.anniversaryDate,
    );
  }
}

class PendingRequests {
  final List<User> received;
  final List<User> sent;

  PendingRequests({this.received = const [], this.sent = const []});

  PendingRequests copyWith({List<User>? received, List<User>? sent}) {
    return PendingRequests(
      received: received ?? this.received,
      sent: sent ?? this.sent,
    );
  }
}

class PartnershipInvitation {
  final int id;
  final String status;
  final DateTime createdAt;
  final int? partnerId;
  final String? partnerDisplayName;
  final String? partnerEmail;
  final bool isReceived;

  PartnershipInvitation({
    required this.id,
    required this.status,
    required this.createdAt,
    this.partnerId,
    this.partnerDisplayName,
    this.partnerEmail,
    this.isReceived = false,
  });

  factory PartnershipInvitation.fromJson(Map<String, dynamic> json) {
    final partner = json['partner'] as Map<String, dynamic>?;

    return PartnershipInvitation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'pending',
      createdAt: AppDateUtils.tryParse(json['created_at'] as String?) ?? DateTime.now(),
      partnerId: partner != null ? (partner['id'] as num?)?.toInt() : null,
      partnerDisplayName: partner != null
          ? ((partner['display_name'] ?? partner['username']) as String?)
          : null,
      partnerEmail: partner != null ? partner['email'] as String? : null,
    );
  }

  bool get isPending => status == 'pending';
  String get username => partnerDisplayName ?? partnerEmail ?? 'Partner';
}
