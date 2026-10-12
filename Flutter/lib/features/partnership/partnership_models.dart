// =============================================================================
// JustUs App - Partnership Models
// =============================================================================

import 'package:justus/all_imports.dart';

abstract class PartnershipModels {}

/// Represents the full partnership view returned by v_active_partnership.
/// The view returns: partnership_id, status, anniversary_date,
/// partner_id, partner_display_name, partner_profile_pic_url.
class PartnershipResponse {
  final bool success;
  final int? partnershipId;
  final String status; // 'accepted' | 'pending' | 'none'
  final User? partner;
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
      );
    }

    return PartnershipResponse(
      success: (json['success'] as bool?) ?? true,
      partnershipId: (json['partnership_id'] as num?)?.toInt(),
      status: (json['status'] as String?) ?? 'none',
      partner: partner,
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
    String? message,
    String? error,
    DateTime? anniversaryDate,
  }) {
    return PartnershipResponse(
      success: success ?? this.success,
      partnershipId: partnershipId ?? this.partnershipId,
      status: status ?? this.status,
      partner: partner ?? this.partner,
      message: message ?? this.message,
      error: error ?? this.error,
      anniversaryDate: anniversaryDate ?? this.anniversaryDate,
    );
  }
}

class PartnershipInvitation {
  final int id;
  final String status;
  final DateTime createdAt;
  final int? partnerId;
  final String? partnerDisplayName;
  final bool isReceived;

  PartnershipInvitation({
    required this.id,
    required this.status,
    required this.createdAt,
    this.partnerId,
    this.partnerDisplayName,
    this.isReceived = false,
  });

  factory PartnershipInvitation.fromJson(Map<String, dynamic> json) {
    return PartnershipInvitation(
      id: (json['invitation_id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'pending',
      createdAt: AppDateUtils.tryParse(json['created_at'] as String?) ?? DateTime.now(),
      partnerId: (json['partner_id'] as num?)?.toInt(),
      partnerDisplayName: json['partner_display_name'] as String?,
      isReceived: (json['is_received'] as bool?) ?? false,
    );
  }

  bool get isPending => status == 'pending';
  String get username => partnerDisplayName ?? 'Partner';
}
