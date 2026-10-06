import 'dart:async';

import 'package:justus/all_imports.dart';

class GameRepository extends BaseRepository {
  final GameQuestionBankRepository _bankRepo;

  GameRepository({super.sbClient})
      : _bankRepo = GameQuestionBankRepository(sbClient: sbClient);

  Future<String> _resolveQuestionText(String? code, String locale) async {
    if (code == null) return '';
    final res = await _bankRepo.fetchQuestionText(
      questionCode: code,
      locale: locale,
    );
    return res.valueOrNull ?? '';
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

  Future<ResultWrapper<GameNewQuestionResponse>> fetchNewGameQuestion() async {
    return withUser((uid) async {
      final partnershipData = await getActivePartnership();
      final partnershipId = partnershipData?['partnership_id'] as int?;
      final partnerId = partnershipData?['partner_id'] as int?;
      if (partnershipId == null || partnerId == null) {
        throw Exception('No active partnership');
      }

      final locale = await LanguageHelper.currentLocaleCode();
      final myName = await StorageService.getUsername();
      final partnerName = partnershipData?['partner_display_name'] as String?;

      String nameFor(int userId) => resolvePlayerName(
            userId: userId,
            currentUserId: uid,
            myName: myName,
            partnerName: partnerName,
          );

      final existing = await sbClient
          .from('game_questions')
          .select('id, question_code, status, user_id_a, user_id_b, created_at')
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
        final questionCode = existing['question_code'] as String?;

        final questionText = await _resolveQuestionText(questionCode, locale);

        return GameNewQuestionResponse(
          success: true,
          id: existing['id'] as int,
          question: questionText,
          questionCode: questionCode,
          status: existing['status'] as String?,
          userIdA: userIdA,
          userIdB: userIdB,
          optionA: userIdA != null ? nameFor(userIdA) : 'Opzione A',
          optionB: userIdB != null ? nameFor(userIdB) : 'Opzione B',
          hasAnswered: hasAnswered,
          partnerAnswered: partnerAnswered,
        );
      }

      // Nessuna domanda attiva per la coppia: ne creiamo una nuova dal catalogo!
      final playedQuestionsRes = await sbClient
          .from('game_questions')
          .select('question_code')
          .eq('partnership_id', partnershipId)
          .toList();

      final playedQuestionCodes = playedQuestionsRes
          .map((r) => r['question_code'] as String?)
          .whereType<String>()
          .toList();

      final bankItemRes = await _bankRepo.pickQuestionForGame(
        locale: locale,
        excludeQuestionCodes: playedQuestionCodes,
      );

      final bankItem = bankItemRes.valueOrNull;
      if (bankItem == null) {
        throw Exception(
            'Impossibile recuperare una nuova domanda dal catalogo');
      }

      // Determinazione casuale dell'ordine di User A e User B
      final isSwap = (DateTime.now().millisecondsSinceEpoch % 2) == 0;
      final userIdA = isSwap ? partnerId : uid;
      final userIdB = isSwap ? uid : partnerId;

      final inserted = await sbClient
          .from('game_questions')
          .insert({
            'partnership_id': partnershipId,
            'question_code': bankItem.questionCode,
            'status': 'pending',
            'user_id_a': userIdA,
            'user_id_b': userIdB,
          })
          .select('id, question_code, status, user_id_a, user_id_b, created_at')
          .single();

      unawaited(notifyPartnerOnce(
        notificationKey: 'newQuestion',
        params: {},
      ));

      return GameNewQuestionResponse(
        success: true,
        id: inserted['id'] as int,
        question: bankItem.text,
        questionCode: bankItem.questionCode,
        status: inserted['status'] as String?,
        userIdA: userIdA,
        userIdB: userIdB,
        optionA: nameFor(userIdA),
        optionB: nameFor(userIdB),
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
      field: 'updated_at',
      filterColumn: 'user_id',
      filterValues: [uid, partnerId],
      cacheKey: CacheService.kGameAnswers,
    );
  }

  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return withCouple((uid, partnerId) async {
      final locale = await LanguageHelper.currentLocaleCode();

      var query = sbClient.from('game_answers').select(
          'game_id, selected_option, user_id, game_questions(id, question_code, created_at)');

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

        final questionCode = questionData['question_code'] as String?;

        historyMap.putIfAbsent(
          gameId,
          () => {
            'id': gameId,
            'question_code': questionCode,
            'question': '',
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

      // Popola i testi delle domande dal catalogo per la lingua corrente
      final questionCodesToFetch = historyMap.values
          .map((m) => m['question_code'] as String?)
          .whereType<String>()
          .toSet();

      final Map<String, String> questionTextsMap = {};
      if (questionCodesToFetch.isNotEmpty) {
        // Catalogo parzialmente tradotto: i codici ancora assenti si
        // riprovano sul locale predefinito dell'app invece di restare vuoti.
        for (final localeCode in LanguageHelper.localeChain(locale)) {
          final bankItemsRes =
              await _bankRepo.fetchQuestionsByLocale(localeCode);
          final bankItems = switch (bankItemsRes) {
            Success(value: final v) => v,
            GenericError(:final message) =>
              throw Exception('Bank fetch failed ($localeCode): $message'),
            NetworkError(:final message) =>
              throw Exception('Bank network error ($localeCode): $message'),
          };

          for (final item in bankItems) {
            if (questionCodesToFetch.contains(item.questionCode)) {
              questionTextsMap[item.questionCode] = item.text;
            }
          }

          if (questionTextsMap.length == questionCodesToFetch.length) break;
        }
      }

      for (final item in historyMap.values) {
        final code = item['question_code'] as String?;
        if (code != null && questionTextsMap.containsKey(code)) {
          item['question'] = questionTextsMap[code];
        } else if (code != null && !questionTextsMap.containsKey(code)) {
          item['question'] = await _resolveQuestionText(code, locale);
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
