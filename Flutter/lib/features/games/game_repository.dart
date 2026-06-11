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
          .select()
          .order('created_at', ascending: false)
          .limit(1);

      if (partnershipId != null) {
        query = sbClient
            .from('game_questions')
            .select()
            .eq('partnership_id', partnershipId)
            .order('created_at', ascending: false)
            .limit(1);
      }

      final data = await query.maybeSingle();
      if (data == null) throw Exception('Nessuna domanda disponibile');

      return GameQuestion.fromJson(data);
    });
  }

  Future<ResultWrapper<List<GameAnswer>>> fetchQuestionAnswers(
      int questionId) async {
    return tryCall(() async {
      final List<dynamic> data = await sbClient
          .from('game_answers')
          .select()
          .eq('game_id', questionId);

      return data
          .map((a) => GameAnswer.fromJson(a as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ResultWrapper<void>> submitAnswer(
      int questionId, int selectedOption) async {
    return withUser((uid) async {
      await sbClient.from('game_answers').insert({
        'game_id': questionId,
        'user_id': uid,
        'selected_option': selectedOption,
      });
    });
  }

  Future<ResultWrapper<GameNewQuestionResponse>> fetchNewGameQuestion() async {
    return tryCall(() async {
      final partnershipData = await getActivePartnership();
      final partnershipId = partnershipData?['partnership_id'] as int?;
      if (partnershipId == null) {
        throw Exception('Nessuna partnership attiva trovata');
      }

      final nameA = partnershipData?['user_a_name'] ?? 'Partner A';
      final nameB = partnershipData?['user_b_name'] ?? 'Partner B';

      final existing = await sbClient
          .from('game_questions')
          .select()
          .eq('partnership_id', partnershipId)
          .neq('status', 'both_answered')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final uid = await getUserId();
      bool hasAnswered = false;
      bool partnerAnswered = false;
      if (existing != null && uid != null) {
        final List<dynamic> answers = await sbClient
            .from('game_answers')
            .select('user_id')
            .eq('game_id', existing['id'] as Object);

        hasAnswered = answers.any((a) => a['user_id'] == uid);
        partnerAnswered = answers.any((a) => a['user_id'] != uid);
      }

      if (existing != null) {
        return GameNewQuestionResponse.fromJson({
          ...existing,
          'success': true,
          'option_a': nameA,
          'option_b': nameB,
          'has_answered': hasAnswered,
          'partner_answered': partnerAnswered,
        });
      }

      final aiResult = await _api.fetchNewGameQuestion();
      if (aiResult is Success<GameNewQuestionResponse>) {
        final generatedText = aiResult.value.question;
        final inserted = await sbClient
            .from('game_questions')
            .insert({
              'partnership_id': partnershipId,
              'question': generatedText,
              'status': 'pending',
              'user_id_a': partnershipData?['user_id_a'],
              'user_id_b': partnershipData?['user_id_b'],
            })
            .select()
            .single();

        return GameNewQuestionResponse.fromJson({
          ...inserted,
          'success': true,
          'option_a': nameA,
          'option_b': nameB,
          'has_answered': false,
          'partner_answered': false,
        });
      } else {
        throw Exception('Errore generazione AI');
      }
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

      final List<dynamic> data =
          await query.order('created_at', ascending: false);

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
}
