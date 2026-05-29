// =============================================================================
// JustUs App - Game Models
// =============================================================================

abstract class GameModels {}

class GameStatsResponse {
  final bool success;
  final int totalMatches;

  GameStatsResponse({required this.success, required this.totalMatches});

  factory GameStatsResponse.fromJson(Map<String, dynamic> json) {
    return GameStatsResponse(
      success: (json['success'] as bool?) ?? false,
      totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
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
  final int? userIdA;
  final int? userIdB;

  GameNewQuestionResponse({
    required this.success,
    required this.id,
    required this.question,
    required this.optionA,
    required this.optionB,
    this.userIdA,
    this.userIdB,
    this.status,
    this.message,
  });

  factory GameNewQuestionResponse.fromJson(Map<String, dynamic> json) {
    return GameNewQuestionResponse(
      success: (json['success'] as bool?) ?? false,
      id: (json['id'] as num?)?.toInt() ?? 0,
      question: (json['question'] as String?) ?? '',
      optionA: ((json['option_a'] ?? json['optionA']) as String?) ?? '',
      optionB: ((json['option_b'] ?? json['optionB']) as String?) ?? '',
      userIdA: ((json['user_id_a'] ?? json['userIdA']) as num?)?.toInt(),
      userIdB: ((json['user_id_b'] ?? json['userIdB']) as num?)?.toInt(),
      status: json['status'] as String?,
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'id': id,
      'question': question,
      'optionA': optionA,
      'optionB': optionB,
      'userIdA': userIdA,
      'userIdB': userIdB,
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
    int? userIdA,
    int? userIdB,
    String? status,
    String? message,
  }) {
    return GameNewQuestionResponse(
      success: success ?? this.success,
      id: id ?? this.id,
      question: question ?? this.question,
      optionA: optionA ?? this.optionA,
      optionB: optionB ?? this.optionB,
      userIdA: userIdA ?? this.userIdA,
      userIdB: userIdB ?? this.userIdB,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

class GameQuestion {
  final int id;
  final String question;
  final String createdAt;
  final int? partnershipId;

  GameQuestion({
    required this.id,
    required this.question,
    required this.createdAt,
    this.partnershipId,
  });

  factory GameQuestion.fromJson(Map<String, dynamic> json) {
    return GameQuestion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      question: ((json['question'] ?? json['question_text'] ?? json['text']) as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
      partnershipId: (json['partnership_id'] as num?)?.toInt(),
    );
  }
}

class GameAnswer {
  final int gameId;
  final int userId;
  final int? selectedOption;
  final String createdAt;

  GameAnswer({
    required this.gameId,
    required this.userId,
    this.selectedOption,
    required this.createdAt,
  });

  factory GameAnswer.fromJson(Map<String, dynamic> json) {
    return GameAnswer(
      gameId: (json['game_id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      selectedOption: (json['selected_option'] as num?)?.toInt(),
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

class GameHistoryItem {
  final int questionId;
  final String question;
  final int? userOption;
  final int? partnerOption;
  final String createdAt;

  GameHistoryItem({
    required this.questionId,
    required this.question,
    this.userOption,
    this.partnerOption,
    required this.createdAt,
  });

  bool get isMatched =>
      userOption != null &&
      partnerOption != null &&
      userOption == partnerOption;
  bool get isDisagreed =>
      userOption != null &&
      partnerOption != null &&
      userOption != partnerOption;
  bool get isPending => userOption == null || partnerOption == null;

  factory GameHistoryItem.fromJson(Map<String, dynamic> json) {
    return GameHistoryItem(
      questionId: (json['id'] as num?)?.toInt() ?? 0,
      question: ((json['question'] ?? json['text'] ?? json['question_text']) as String?) ?? '',
      userOption: (json['user_option'] as num?)?.toInt(),
      partnerOption: (json['partner_option'] as num?)?.toInt(),
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}
