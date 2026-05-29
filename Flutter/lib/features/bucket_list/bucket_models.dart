// =============================================================================
// JustUs App - Bucket List Models
// =============================================================================

abstract class BucketModels {}

class BucketItem {
  final int id;
  final String text;
  final bool done;
  final String createdAt;
  final String category;
  final int? partnershipId;

  BucketItem({
    required this.id,
    required this.text,
    required this.done,
    required this.createdAt,
    required this.category,
    this.partnershipId,
  });

  factory BucketItem.fromJson(Map<String, dynamic> json) {
    return BucketItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      text: (json['text'] as String?) ?? '',
      done: json['done'] == true || json['done'] == 1,
      createdAt: (json['created_at'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'Tutti',
      partnershipId: (json['partnership_id'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'done': done,
      'created_at': createdAt,
      'category': category,
      if (partnershipId != null) 'partnership_id': partnershipId,
    };
  }

  BucketItem copyWith({
    int? id,
    String? text,
    bool? done,
    String? createdAt,
    String? category,
    int? partnershipId,
  }) {
    return BucketItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
      category: category ?? this.category,
      partnershipId: partnershipId ?? this.partnershipId,
    );
  }
}
