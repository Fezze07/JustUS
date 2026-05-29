// =============================================================================
// JustUs App - Drive Models
// =============================================================================

abstract class DriveModels {}

class DriveItem {
  final int id;
  final String type;
  /// filename / storage key
  final String content;
  final Map<String, String>? metadata;
  /// Aggregated emoji reactions from v_drive_dashboard (list of emoji chars)
  final List<String> reactions;
  final String createdAt;
  final String updatedAt;
  final int isFavorite; // 0 or 1
  final int? partnershipId;

  DriveItem({
    required this.id,
    required this.type,
    required this.content,
    this.metadata,
    this.reactions = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.isFavorite,
    this.partnershipId,
  });

  factory DriveItem.fromJson(Map<String, dynamic> json) {
    // reactions from v_drive_dashboard come as jsonb array of emoji_char strings
    List<String> parsedReactions = [];
    if (json['reactions'] != null) {
      final raw = json['reactions'];
      if (raw is List) {
        parsedReactions = raw.map((e) {
          if (e is String) return e;
          if (e is Map) return e['emoji_char']?.toString() ?? e.toString();

          return e.toString();
        }).toList();
      }
    }

    return DriveItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: (json['type'] as String?) ?? '',
      content: ((json['name'] ?? json['filename'] ?? json['content']) as String?) ?? '',
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
              .map((key, value) => MapEntry(key, value.toString()))
          : null,
      reactions: parsedReactions,
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      isFavorite: json['is_favorite'] is bool
          ? (json['is_favorite'] as bool ? 1 : 0)
          : ((json['is_favorite'] as num?)?.toInt() ?? 0),
      partnershipId: (json['partnership_id'] as num?)?.toInt(),
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
      if (partnershipId != null) 'partnership_id': partnershipId,
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
    int? partnershipId,
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
      partnershipId: partnershipId ?? this.partnershipId,
    );
  }
}

class DriveItemReaction {
  /// Dynamic emoji character
  final String reaction;

  DriveItemReaction({required this.reaction});

  Map<String, dynamic> toJson() => {'reaction': reaction};

  factory DriveItemReaction.fromJson(Map<String, dynamic> json) {
    return DriveItemReaction(
      reaction: ((json['emoji_char'] ?? json['reaction'] ?? json['emoji']) as String?) ?? '',
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
      success: (json['success'] as bool?) ?? false,
      reactions: json['reactions'] != null
          ? (json['reactions'] as List<dynamic>)
              .map((e) => DriveItemReaction.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}