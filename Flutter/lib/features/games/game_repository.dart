import 'dart:async';

import 'package:justus/all_imports.dart';

class GameRepository extends BaseRepository {
  final ApiService _api;

  GameRepository({super.sbClient, ApiService? api})
      : _api = api ?? ApiService();

  Future<ResultWrapper<GameQuestion>> fetchDailyQuestion() async {
    return tryCall(() async {
      final partnershipData = await getActivePartnership();
      final partnershipId = partnershipData?['partnership_id'] as int?;

      var query = sbClient
          .from('game_questions')
          .select('id, question, created_at, partnership_id')
          .maybeEq('partnership_id', partnershipId)
          .order('created_at', ascending: false)
          .limit(1);

      final data = await query.maybeSingle();
      if (data == null) throw Exception('Nessuna domanda disponibile');

      return GameQuestion.fromJson(data);
    });
  }

  Future<ResultWrapper<List<GameAnswer>>> fetchQuestionAnswers(
      int questionId) async {
    return tryCall(() async {
      final data = await sbClient
          .from('game_answers')
          .select('game_id, user_id, selected_option, created_at')
          .eq('game_id', questionId)
          .toList();

      return data.map((a) => GameAnswer.fromJson(a)).toList();
    });
  }

  Future<ResultWrapper<void>> submitAnswer(
      int questionId, int selectedOption) async {
    final uid = await getUserId();
    if (uid == null) {
      return const GenericError(message: 'User not logged in');
    }

    return tryCall(() async {
      await sbClient.from('game_answers').upsert([{
        'game_id': questionId,
        'user_id': uid,
        'selected_option': selectedOption,
      }], onConflict: 'game_id,user_id');

      unawaited(notifyPartnerOnce(
        notificationKey: 'answerSubmitted',
        params: {'partnerName': await StorageService.getUsername() ?? ''},
      ));
    });
  }

  Future<ResultWrapper<GameNewQuestionResponse>> fetchNewGameQuestion() async {
    final uid = await getUserId();
    if (uid == null) {
      return const GenericError(message: 'User not logged in');
    }

    return tryCall(() async {
      final partnershipData = await getActivePartnership();
      final partnershipId = partnershipData?['partnership_id'] as int?;
      final partnerId = partnershipData?['partner_id'] as int?;
      if (partnershipId == null || partnerId == null) {
        throw Exception('No active partnership');
      }

      final myName = await StorageService.getUsername();
      final partnerName = partnershipData?['partner_display_name'] as String?;

      String nameFor(int userId) =>
          userId == uid ? (myName ?? 'Tu') : (partnerName ?? 'Partner');

      final existing = await sbClient
          .from('game_questions')
          .select('id, question, status, user_id_a, user_id_b, created_at')
          .eq('partnership_id', partnershipId)
          .neq('status', 'both_answered')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        final answers = await sbClient
            .from('game_answers')
            .select('user_id')
            .eq('game_id', existing['id'] as int)
            .toList();
        final hasAnswered = answers.any((a) => a['user_id'] == uid);
        final partnerAnswered = answers.any((a) => a['user_id'] == partnerId);

        final userIdA = existing['user_id_a'] as int?;
        final userIdB = existing['user_id_b'] as int?;

        return GameNewQuestionResponse(
          success: true,
          id: existing['id'] as int,
          question: existing['question'] as String,
          status: existing['status'] as String?,
          userIdA: userIdA,
          userIdB: userIdB,
          optionA: userIdA != null ? nameFor(userIdA) : 'Opzione A',
          optionB: userIdB != null ? nameFor(userIdB) : 'Opzione B',
          hasAnswered: hasAnswered,
          partnerAnswered: partnerAnswered,
        );
      }

      final aiResponse = await _api.generateAiQuestion();

      final aiResult = aiResponse.valueOrNull;
      if (aiResult == null) throw Exception('Failed to generate question');

      final questionText = aiResult['question'] as String?;
      if (questionText == null || questionText.isEmpty) {
        throw Exception('Invalid AI response');
      }

      final inserted = await sbClient.from('game_questions').insert({
        'partnership_id': partnershipId,
        'question': questionText,
        'status': 'pending',
        'user_id_a': uid,
        'user_id_b': partnerId,
      }).select('id, question, status, user_id_a, user_id_b, created_at').single();

      unawaited(notifyPartnerOnce(
        notificationKey: 'newQuestion',
        params: {},
      ));

      final userIdA = inserted['user_id_a'] as int?;
      final userIdB = inserted['user_id_b'] as int?;

      return GameNewQuestionResponse(
        success: true,
        id: inserted['id'] as int,
        question: inserted['question'] as String,
        status: inserted['status'] as String?,
        userIdA: userIdA,
        userIdB: userIdB,
        optionA: userIdA != null ? nameFor(userIdA) : 'Opzione A',
        optionB: userIdB != null ? nameFor(userIdB) : 'Opzione B',
      );
    });
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

  Future<ResultWrapper<GameStatsResponse>> fetchGameStats() async {
    return withCouple((uid, partnerId) async {
      if (partnerId == null) {
        return GameStatsResponse(success: true, totalMatches: 0);
      }

      final response = await sbClient.rpc(
        'get_game_stats',
        params: {
          'p_uid': uid,
          'p_partner_id': partnerId,
        },
      );

      final matches = response as int? ?? 0;

      return GameStatsResponse(success: true, totalMatches: matches);
    });
  }

  Future<bool> hasNewGameActivity(int uid, int partnerId) {
    return hasChanges(
      table: 'game_answers',
      field: 'created_at',
      filterColumn: 'user_id',
      filterValues: [uid, partnerId],
      cacheKey: CacheService.kGameAnswers,
    );
  }

  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return withCouple((uid, partnerId) async {
      var query = sbClient.from('game_answers').select(
          'game_id, selected_option, user_id, game_questions(id, question, created_at)');

      if (partnerId != null) {
        query = query.inFilter('user_id', [uid, partnerId]);
      } else {
        query = query.eq('user_id', uid);
      }

      final data = await query.order('created_at', ascending: false).toList();

      final Map<int, Map<String, dynamic>> historyMap = {};

      for (final row in data) {
        final gameId = row['game_id'] as int;
        final questionData = row['game_questions'];
        if (questionData == null) continue;

        historyMap.putIfAbsent(
          gameId,
          () => {
            'id': gameId,
            'question': questionData['question'] ?? '',
            'created_at': questionData['created_at'],
            'user_option': null,
            'partner_option': null,
          },
        );

        final answerUserId = row['user_id'] as int;
        if (answerUserId == uid) {
          historyMap[gameId]!['user_option'] = row['selected_option'];
        } else if (answerUserId == partnerId) {
          historyMap[gameId]!['partner_option'] = row['selected_option'];
        }
      }

      final history = historyMap.values
          .map((item) => GameHistoryItem.fromJson(item))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return history;
    });
  }

  Future<ResultWrapper<void>> updateQuestionStatus(int questionId, String status) {
    return tryCall(() async {
      await sbClient
          .from('game_questions')
          .update({'status': status})
          .eq('id', questionId);
    });
  }

}
