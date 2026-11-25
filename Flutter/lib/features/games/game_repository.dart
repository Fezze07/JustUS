import 'dart:async';
import 'package:flutter/widgets.dart';

import 'package:justus/all_imports.dart';

/// Shared prelude for the active-question flows (partnership + locale +
/// display names). Throws when there is no active partnership.
typedef _GameFetchContext = ({
  int uid,
  int partnershipId,
  int partnerId,
  String locale,
  String Function(int userId) nameFor,
  String optionALabel,
  String optionBLabel,
});

class GameRepository extends BaseRepository {
  /// Games loaded per history page. History is paged on demand so the query
  /// never grows with the couple's full lifetime of answers.
  static const int historyPageSize = 5;

  final GameQuestionBankRepository _bankRepo;

  GameRepository({super.sbClient})
      : _bankRepo = GameQuestionBankRepository(sbClient: sbClient);

  Future<String> _resolveQuestionText(String? code, String locale) async {
    if (code == null) {
      throw const AppError(
        code: ErrorCodes.dbNotFound001,
        message: 'Question code is null',
      );
    }
    final res = await _bankRepo.fetchQuestionText(
      questionCode: code,
      locale: locale,
    );
    final text = res.valueOrNull;
    if (text == null || text.isEmpty) {
      throw AppError(
        code: ErrorCodes.dbNotFound001,
        message: 'Failed to resolve question text for code: $code',
      );
    }
    return text;
  }

  Future<ResultWrapper<void>> submitAnswer(
      int questionId, int selectedOption) async {
    return withUser((uid) async {
      await sbClient.from('game_answers').upsert([
        {
          'game_id': questionId,
          'user_id': uid,
          'selected_option': selectedOption,
        }
      ], onConflict: 'game_id,user_id');

      unawaited(notifyPartnerOnce(
        notificationKey: 'answerSubmitted',
        params: {'partnerName': await StorageService.getUsername() ?? ''},
      ));
    });
  }

  /// Nudges the partner to answer the active question. The backend enforces a
  /// per-user cooldown on this key; the caller gates it on the waiting state.
  Future<ResultWrapper<Map<String, dynamic>>> sendAnswerReminder() async {
    return ApiService().notifyPartner(
      notificationKey: 'answerReminder',
      params: {'partnerName': await StorageService.getUsername() ?? ''},
    );
  }

  /// Read-only: returns the active question for the couple, or `Success(null)`
  /// when none exists. Never inserts and never notifies the partner — the
  /// "create if missing" behaviour lives in [fetchNewGameQuestion].
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchActiveQuestion() {
    return withUser((uid) async {
      final ctx = await _buildGameFetchContext(uid);
      return _fetchActiveQuestionFor(ctx);
    });
  }

  Future<ResultWrapper<GameNewQuestionResponse?>> fetchNewGameQuestion() async {
    return withUser((uid) async {
      final ctx = await _buildGameFetchContext(uid);
      final row = await sbClient.rpc('game_get_or_create_question', params: {
        'p_partnership_id': ctx.partnershipId,
        'p_locales': LanguageHelper.localeChain(ctx.locale),
      });

      if (row == null) return null;
      final data = row as Map<String, dynamic>;
      final questionCode = data['question_code'] as String?;
      final questionText = (data['question'] as String?) ??
          await _resolveQuestionText(questionCode, ctx.locale);
      if (questionText.isEmpty) {
        throw AppError(
          code: ErrorCodes.dbNotFound001,
          message: 'Failed to resolve question text for code: $questionCode',
        );
      }

      if (data['created'] == true) {
        unawaited(notifyPartnerOnce(
          notificationKey: 'newQuestion',
          params: {},
        ));
      }

      final userIdA = (data['user_id_a'] as num?)?.toInt();
      final userIdB = (data['user_id_b'] as num?)?.toInt();

      return GameNewQuestionResponse(
        id: (data['id'] as num).toInt(),
        question: questionText,
        questionCode: questionCode,
        status: data['status'] as String?,
        userIdA: userIdA,
        userIdB: userIdB,
        optionA: optionLabelFor(userIdA, ctx.optionALabel, ctx.nameFor),
        optionB: optionLabelFor(userIdB, ctx.optionBLabel, ctx.nameFor),
        hasAnswered: (data['has_answered'] as bool?) ?? false,
        partnerAnswered: (data['partner_answered'] as bool?) ?? false,
      );
    });
  }

  Future<_GameFetchContext> _buildGameFetchContext(int uid) async {
    final partnershipData = await getActivePartnership();
    final partnershipId = partnershipData?['partnership_id'] as int?;
    final partnerId = partnershipData?['partner_id'] as int?;
    if (partnershipId == null || partnerId == null) {
      throw const AppError(
        code: ErrorCodes.apiValidation007,
        message: 'No active partnership',
      );
    }

    final locale = await LanguageHelper.currentLocaleCode();
    final loc = await AppLocalizations.delegate.load(Locale(locale));
    final myName = await StorageService.getUsername();
    final partnerName = partnershipData?['partner_display_name'] as String?;

    return (
      uid: uid,
      partnershipId: partnershipId,
      partnerId: partnerId,
      locale: locale,
      nameFor: (int userId) => resolvePlayerName(
            userId: userId,
            currentUserId: uid,
            myName: myName,
            partnerName: partnerName,
            youFallback: loc.common_youTitle,
            partnerFallback: loc.common_partner,
          ),
      optionALabel: loc.game_optionA,
      optionBLabel: loc.game_optionB,
    );
  }

  Future<GameNewQuestionResponse?> _fetchActiveQuestionFor(
      _GameFetchContext ctx) async {
    final existing = await sbClient
        .from('game_questions')
        .select('id, question_code, status, user_id_a, user_id_b, created_at')
        .eq('partnership_id', ctx.partnershipId)
        .neq('status', 'both_answered')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existing == null) return null;

    final answers = await sbClient
        .from('game_answers')
        .select('user_id')
        .eq('game_id', existing['id'] as int)
        .toList();
    final hasAnswered = answers.any((a) => a['user_id'] == ctx.uid);
    final partnerAnswered = answers.any((a) => a['user_id'] == ctx.partnerId);

    final userIdA = existing['user_id_a'] as int?;
    final userIdB = existing['user_id_b'] as int?;
    final questionCode = existing['question_code'] as String?;

    final questionText = await _resolveQuestionText(questionCode, ctx.locale);

    return GameNewQuestionResponse(
      id: existing['id'] as int,
      question: questionText,
      questionCode: questionCode,
      status: existing['status'] as String?,
      userIdA: userIdA,
      userIdB: userIdB,
      optionA: optionLabelFor(userIdA, ctx.optionALabel, ctx.nameFor),
      optionB: optionLabelFor(userIdB, ctx.optionBLabel, ctx.nameFor),
      hasAnswered: hasAnswered,
      partnerAnswered: partnerAnswered,
    );
  }

  Future<
      ResultWrapper<
          ({
            bool hasAnswered,
            bool partnerAnswered,
            int? userOption,
            int? partnerOption
          })>> fetchAnswerStatus(int questionId) async {
    return withUser((uid) async {
      final answers = await sbClient
          .from('game_answers')
          .select('user_id, selected_option')
          .eq('game_id', questionId)
          .toList();

      int? userOpt;
      int? partnerOpt;
      for (final a in answers) {
        final aid = a['user_id'] as int?;
        final opt = a['selected_option'] as int?;
        if (aid == uid) {
          userOpt = opt;
        } else {
          partnerOpt = opt;
        }
      }

      return (
        hasAnswered: userOpt != null,
        partnerAnswered: partnerOpt != null,
        userOption: userOpt,
        partnerOption: partnerOpt,
      );
    });
  }

  /// True when either the couple's answers or the couple's questions are
  /// newer than the local checkpoints. Watching `game_questions` too keeps a
  /// partner-created question visible on the next cold start: `created_at` is
  /// bumped by the INSERT, while `game_answers` may have no new row yet and
  /// Realtime never replays the offline-created event (B1).
  Future<bool> hasNewGameActivity(
      int uid, int partnerId, int? partnershipId) async {
    final answersChanged = await hasChanges(
      table: 'game_answers',
      field: 'updated_at',
      filterColumn: 'user_id',
      filterValues: [uid, partnerId],
      cacheKey: CacheService.kGameAnswers,
    );
    if (answersChanged || partnershipId == null) {
      return answersChanged;
    }

    return hasChanges(
      table: 'game_questions',
      field: 'created_at',
      filterColumn: 'partnership_id',
      filterValues: [partnershipId],
      cacheKey: CacheService.kGameQuestions,
    );
  }

  /// One page of the couple's game history, newest first.
  ///
  /// The page unit is the game (a `game_questions` row), not the answer: an
  /// answer-row page could split a game across two pages. Each call therefore
  /// reads at most [limit] games, plus their catalog texts.
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory({
    int limit = historyPageSize,
    int offset = 0,
  }) async {
    return withCouple((uid, partnerId) async {
      final locale = await LanguageHelper.currentLocaleCode();

      final data = await sbClient
          .from('game_questions')
          .select(
              'id, question_code, created_at, game_answers(selected_option, user_id)')
          .inFilter('user_id_a', [uid, if (partnerId != null) partnerId])
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final Map<int, Map<String, dynamic>> historyMap = {};

      for (final row in data) {
        final gameId = row['id'] as int;
        final answers = (row['game_answers'] as List?) ?? const [];

        int? userOption;
        int? partnerOption;
        for (final answer in answers.cast<Map<String, dynamic>>()) {
          final answerUserId = answer['user_id'] as int;
          if (answerUserId == uid) {
            userOption = answer['selected_option'] as int?;
          } else if (answerUserId == partnerId) {
            partnerOption = answer['selected_option'] as int?;
          }
        }

        historyMap[gameId] = {
          'id': gameId,
          'question_code': row['question_code'],
          'question': '',
          'created_at': row['created_at'],
          'user_option': userOption,
          'partner_option': partnerOption,
        };
      }

      // Popola i testi delle domande dal catalogo per la lingua corrente:
      // una sola query per locale della chain, filtrata sui codici richiesti —
      // niente risoluzioni per-codice ridondanti (G4). I codici che nessun
      // locale traduce restano vuoti.
      final questionCodesToFetch = historyMap.values
          .map((m) => m['question_code'] as String?)
          .whereType<String>()
          .toSet();

      final Map<String, String> questionTextsMap = {};
      if (questionCodesToFetch.isNotEmpty) {
        final res = await _bankRepo.fetchTextsForCodes(
          codes: questionCodesToFetch,
          locale: locale,
        );
        questionTextsMap.addAll(switch (res) {
          Success(value: final v) => v,
          GenericError() => throw ErrorHandler.toAppError(res),
          NetworkError() => throw AppError.network(),
        });
      }

      for (final item in historyMap.values) {
        final code = item['question_code'] as String?;
        if (code != null) {
          item['question'] = questionTextsMap[code] ?? '';
        }
      }

      final history = historyMap.values
          .map((item) => GameHistoryItem.fromJson(item))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return history;
    });
  }
}
