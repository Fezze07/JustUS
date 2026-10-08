import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

class FakeGameRepository extends GameRepository {
  @override
  Future<ResultWrapper<GameNewQuestionResponse>> fetchNewGameQuestion() async {
    return Success(
      GameNewQuestionResponse(
        success: true,
        id: 101,
        question: 'Chi dei due organizza meglio i test?',
        optionA: 'Fede',
        optionB: 'Claretta',
        userIdA: 42,
        userIdB: 77,
        status: 'pending',
      ),
    );
  }

  @override
  Future<ResultWrapper<GameStatsResponse>> fetchGameStats() async {
    return Success(GameStatsResponse(success: true, totalMatches: 3));
  }

  @override
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return const Success<List<GameHistoryItem>>([]);
  }

  @override
  Future<ResultWrapper<void>> submitAnswer(
      int questionId, int selectedOption) async {
    return const Success<void>(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('fetchNewQuestion caches the current question', () async {
    final state = GameState(repository: FakeGameRepository());

    await state.fetchNewQuestion();

    expect(state.currentQuestion?.id, 101);
    expect(await StorageService.getCachedGameQuestion(), isNotNull);
    expect((await StorageService.getCachedGameQuestion())?.question,
        'Chi dei due organizza meglio i test?');
  });

  test('submitAnswer updates the local question state', () async {
    final state = GameState(repository: FakeGameRepository());
    await state.fetchNewQuestion();

    final loc = await AppLocalizations.delegate.load(
      Locale(await LanguageHelper.currentLocaleCode()),
    );

    await state.submitAnswer('A');

    expect(state.message, loc.game_answerSent);
    expect(state.currentQuestion?.status, 'waiting');
  });

  test('fetchNewQuestion resets isLoading on NetworkError', () async {
    final state = GameState(
        repository: ConfigurableFakeGameRepository(
      fetchResult: const NetworkError(),
    ));

    await state.fetchNewQuestion();

    expect(state.isLoading, isFalse);
    // currentQuestion remains null since we didn't fetch one successfully
    expect(state.currentQuestion, isNull);
  });

  test('fetchNewQuestion clears current question when no question is available',
      () async {
    // If we have an existing question...
    final state = GameState(
        repository: ConfigurableFakeGameRepository(
      fetchResult: const Success<GameNewQuestionResponse?>(null),
    ));

    // Let's force a previous question to ensure it gets cleared.
    await StorageService.saveGameQuestion(GameNewQuestionResponse(
        success: true,
        id: 999,
        question: 'Old',
        optionA: 'A',
        optionB: 'B',
        userIdA: 1,
        userIdB: 2,
        status: 'pending'));
    await state.init(); // This will load the cached question
    expect(state.currentQuestion?.id, 999);

    // Now fetch, which reports an empty catalogue (no question available)
    await state.fetchNewQuestion();

    expect(state.currentQuestion, isNull);
    expect(state.noQuestionAvailable, isTrue);
    expect(state.isLoading, isFalse);
    expect(await StorageService.getCachedGameQuestion(), isNull);
  });

  test('submitAnswer with invalid option aborts and sets error message',
      () async {
    final state = GameState(repository: FakeGameRepository());
    await state.fetchNewQuestion(); // Sets currentQuestion to 101

    final loc = await AppLocalizations.delegate.load(
      Locale(await LanguageHelper.currentLocaleCode()),
    );

    // Pass an invalid option 'C'
    await state.submitAnswer('C');

    expect(state.message, loc.game_invalidOption);
    expect(state.isLoading, isFalse);
    expect(
        state.currentQuestion?.status, 'pending'); // Did not change to waiting
  });

  test(
      'setLocale refetches question and history in the new language without '
      'restart and without inserting/notifying the partner', () async {
    final languageProvider = LanguageProvider();
    await languageProvider.loadSavedLocale();
    final repo = LocaleRefreshGameRepository();
    final state =
        GameState(repository: repo, languageProvider: languageProvider);

    // Cache an active question in the old language.
    await StorageService.saveGameQuestion(GameNewQuestionResponse(
        success: true,
        id: 101,
        question: 'Chi dei due organizza meglio i test?',
        optionA: 'Fede',
        optionB: 'Claretta',
        userIdA: 42,
        userIdB: 77,
        status: 'pending'));
    await StorageService.saveUserId(42);
    await StorageService.savePartner(77, 'Claretta');

    await state.init();
    expect(state.currentQuestion?.id, 101);

    // Change locale: the GameState listener refetches the active question in
    // the new language. No insert and no partner notification happen.
    await languageProvider.setLocale(const Locale('en'));

    for (var i = 0; i < 50; i++) {
      final cached = await StorageService.getCachedGameQuestion();
      if (cached?.question == _enQuestion) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(repo.activeQuestionFetches, greaterThan(0));
    expect(repo.inserts, 0);
    expect(state.currentQuestion?.id, 101);
    expect(state.currentQuestion?.question, _enQuestion);
    expect((await StorageService.getCachedGameQuestion())?.question,
        _enQuestion);

    // setLocale cleared the history cache; the next game-tab activation
    // (simulated by init()) refetches the history in English, no restart.
    expect(await StorageService.getGameHistory(), isEmpty);
    repo.refetchHistory = true;
    await state.init();
    for (var i = 0; i < 50 && state.history.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.history.single.question, _enQuestion);
  });
}

const _enQuestion = 'Which one plans dates better?';

class LocaleRefreshGameRepository extends GameRepository {
  int activeQuestionFetches = 0;
  int inserts = 0;
  bool refetchHistory = false;

  @override
  Future<bool> hasNewGameActivity(int uid, int partnerId) async =>
      refetchHistory;

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async {
    return {
      'partnership_id': 9001,
      'partner_id': 77,
      'partner_display_name': 'Claretta',
    };
  }

  @override
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchActiveQuestion() async {
    activeQuestionFetches++;
    return Success<GameNewQuestionResponse?>(
      GameNewQuestionResponse(
        success: true,
        id: 101,
        question: _enQuestion,
        optionA: 'Fede',
        optionB: 'Claretta',
        userIdA: 42,
        userIdB: 77,
        status: 'pending',
      ),
    );
  }

  @override
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchNewGameQuestion() async {
    inserts++;
    return Success<GameNewQuestionResponse?>(
      GameNewQuestionResponse(
        success: true,
        id: 101,
        question: _enQuestion,
        optionA: 'Fede',
        optionB: 'Claretta',
        userIdA: 42,
        userIdB: 77,
        status: 'pending',
      ),
    );
  }

  @override
  Future<ResultWrapper<GameStatsResponse>> fetchGameStats() async {
    return Success(GameStatsResponse(success: true, totalMatches: 3));
  }

  @override
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return Success<List<GameHistoryItem>>([
      GameHistoryItem(
        questionId: 101,
        question: _enQuestion,
        userOption: 1,
        partnerOption: 2,
        createdAt: '2026-01-01T00:00:00Z',
      ),
    ]);
  }

  @override
  Future<String?> fetchMaxTimestamp({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
  }) async {
    return DateTime.now().toUtc().toIso8601String();
  }
}

class ConfigurableFakeGameRepository extends GameRepository {
  final ResultWrapper<GameNewQuestionResponse?>? fetchResult;

  ConfigurableFakeGameRepository({this.fetchResult});

  @override
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchNewGameQuestion() async {
    return fetchResult ?? const NetworkError<GameNewQuestionResponse?>();
  }

  @override
  Future<ResultWrapper<GameStatsResponse>> fetchGameStats() async {
    return Success(GameStatsResponse(success: true, totalMatches: 0));
  }

  @override
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return const Success<List<GameHistoryItem>>([]);
  }
}
