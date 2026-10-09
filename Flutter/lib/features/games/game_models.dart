// =============================================================================
// JustUs App - Game Models
// =============================================================================

/// Resolves a display name for [userId] given the current user's names.
///
/// Returns [myName] when [userId] matches [currentUserId], otherwise
/// [partnerName]. Falls back to [youFallback] / [partnerFallback] when the
/// name is null. Single source of truth — replaces the duplicated local
/// closures that previously existed in both GameRepository and GameState (D5).
String resolvePlayerName({
  required int userId,
  required int currentUserId,
  required String? myName,
  required String? partnerName,
  required String youFallback,
  required String partnerFallback,
}) =>
    userId == currentUserId
        ? (myName ?? youFallback)
        : (partnerName ?? partnerFallback);

/// Resolves an option display label for a nullable user ID, falling back to
/// [fallbackLabel]. Single source of truth for option fallback (D9).
String optionLabelFor(
        int? userId, String fallbackLabel, String Function(int) nameFor) =>
    userId != null ? nameFor(userId) : fallbackLabel;

class GameQuestionBankItem {
  final String questionCode;
  final String locale;
  final String text;

  GameQuestionBankItem({
    required this.questionCode,
    required this.locale,
    required this.text,
  });

  factory GameQuestionBankItem.fromJson(Map<String, dynamic> json) {
    return GameQuestionBankItem(
      questionCode: (json['question_code'] as String?) ?? '',
      locale: (json['locale'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
    );
  }
}

class GameNewQuestionResponse {
  final int id;
  final String question;
  final String? questionCode;
  final String optionA;
  final String optionB;
  final String? status;
  final int? userIdA;
  final int? userIdB;
  final bool hasAnswered;
  final bool partnerAnswered;

  GameNewQuestionResponse({
    required this.id,
    required this.question,
    this.questionCode,
    required this.optionA,
    required this.optionB,
    this.userIdA,
    this.userIdB,
    this.status,
    this.hasAnswered = false,
    this.partnerAnswered = false,
  });

  factory GameNewQuestionResponse.fromJson(Map<String, dynamic> json) {
    return GameNewQuestionResponse(
      id: (json['id'] as num?)?.toInt() ?? 0,
      question: (json['question'] as String?) ?? '',
      questionCode: json['question_code'] as String?,
      optionA: (json['optionA'] as String?) ?? '',
      optionB: (json['optionB'] as String?) ?? '',
      userIdA: (json['userIdA'] as num?)?.toInt(),
      userIdB: (json['userIdB'] as num?)?.toInt(),
      status: json['status'] as String?,
      hasAnswered: (json['hasAnswered'] as bool?) ?? false,
      partnerAnswered: (json['partnerAnswered'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      if (questionCode != null) 'question_code': questionCode,
      'optionA': optionA,
      'optionB': optionB,
      'userIdA': userIdA,
      'userIdB': userIdB,
      'status': status,
      'hasAnswered': hasAnswered,
      'partnerAnswered': partnerAnswered,
    };
  }

  GameNewQuestionResponse copyWith({
    int? id,
    String? question,
    String? questionCode,
    String? optionA,
    String? optionB,
    int? userIdA,
    int? userIdB,
    String? status,
    bool? hasAnswered,
    bool? partnerAnswered,
  }) {
    return GameNewQuestionResponse(
      id: id ?? this.id,
      question: question ?? this.question,
      questionCode: questionCode ?? this.questionCode,
      optionA: optionA ?? this.optionA,
      optionB: optionB ?? this.optionB,
      userIdA: userIdA ?? this.userIdA,
      userIdB: userIdB ?? this.userIdB,
      status: status ?? this.status,
      hasAnswered: hasAnswered ?? this.hasAnswered,
      partnerAnswered: partnerAnswered ?? this.partnerAnswered,
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

  factory GameHistoryItem.fromJson(Map<String, dynamic> json) {
    return GameHistoryItem(
      questionId: (json['id'] as num?)?.toInt() ?? 0,
      question: (json['question'] as String?) ?? '',
      userOption: (json['user_option'] as num?)?.toInt(),
      partnerOption: (json['partner_option'] as num?)?.toInt(),
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': questionId,
      'question': question,
      'user_option': userOption,
      'partner_option': partnerOption,
      'created_at': createdAt,
    };
  }
}
