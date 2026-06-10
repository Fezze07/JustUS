// =============================================================================
// JustUs App - Mood Models
// =============================================================================

abstract class MoodModels {}

class MissYouResponse {
  final bool success;
  final int total;

  MissYouResponse({required this.success, required this.total});

  factory MissYouResponse.fromJson(Map<String, dynamic> json) {
    return MissYouResponse(
      success: (json['success'] as bool?) ?? false,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class MoodResponse {
  final bool success;
  /// The emoji character (dynamic, any Unicode emoji).
  final String? emoji;
  final String? createdAt;

  MoodResponse({required this.success, this.emoji, this.createdAt});

  factory MoodResponse.fromJson(Map<String, dynamic> json) {
    // RPC set_mood returns void; fetching mood returns emoji_char from emojis table
    return MoodResponse(
      success: (json['success'] as bool?) ?? true,
      emoji: (json['emoji_char'] ?? json['emoji']) as String?,
      createdAt: (json['created_at'] ?? json['createdAt']) as String?,
    );
  }
}

class MoodEntry {
  final int id;
  final int? userId;
  /// Dynamic emoji character string (any Unicode emoji)
  final String emoji;
  final String? note;
  final String createdAt;
  final bool isMine;

  MoodEntry({
    required this.id,
    this.userId,
    required this.emoji,
    this.note,
    required this.createdAt,
    this.isMine = false,
  });

  factory MoodEntry.fromJson(Map<String, dynamic> json, {int? currentUserId}) {
    // Support both direct emoji field and joined emojis.emoji_char
    final emojiChar = (json['emoji_char'] ??
        (json['emojis'] as Map<String, dynamic>?)?['emoji_char'] ??
        json['emoji'] ??
        '') as String;
    final userId = (json['user_id'] as num?)?.toInt();
    final mine = json['is_mine'] as bool? ??
        (currentUserId != null && userId == currentUserId);

    return MoodEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: userId,
      emoji: emojiChar,
      note: json['note'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      isMine: mine,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'emoji': emoji,
      'note': note,
      'created_at': createdAt,
      'is_mine': isMine,
    };
  }
}
