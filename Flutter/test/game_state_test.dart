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
    expect(
        (await StorageService.getCachedGameQuestion())?.question, _enQuestion);

    // B2: the history is already in English in memory right after setLocale —
    // no game-tab re-activation (init()) needed.
    for (var i = 0;
        i < 50 &&
            !(state.history.isNotEmpty &&
                state.history.single.question == _enQuestion);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.history, hasLength(1));
    expect(state.history.single.question, _enQuestion);
    expect(repo.historyFetches, greaterThan(0));
  });

  test(
      'init() restores a partner-created active question from the server '
      '(B1, clean cache)', () async {
    await StorageService.saveUserId(42);
    await StorageService.savePartner(77, 'Claretta');
    await StorageService.savePartnershipId(9001);

    final repo = ColdStartGameRepository();
    final state = GameState(repository: repo);

    // init() fans the network fetch out async (loadWithChangeDetection), so
    // poll until the background sync lands.
    await state.init();
    GameNewQuestionResponse? cached;
    for (var i = 0; i < 50; i++) {
      cached = await StorageService.getCachedGameQuestion();
      if (cached?.id == 101) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    // Read-only: the server question is fetched, never re-created.
    expect(repo.activeQuestionFetches, 1);
    expect(repo.inserts, 0);
    expect(state.currentQuestion?.id, 101);
    expect(state.currentQuestion?.question, _coldQuestion);
    expect(state.noQuestionAvailable, isFalse);
    expect(cached, isNotNull);
    expect(await CacheService.getCheckpoint(CacheService.kGameQuestions),
        isNotNull);
  });

  test(
      'init() drops a stale cached question when the server has none active '
      '(B1)', () async {
    await StorageService.saveGameQuestion(GameNewQuestionResponse(
      id: 999,
      question: 'Old',
      optionA: 'A',
      optionB: 'B',
      userIdA: 1,
      userIdB: 2,
      status: 'pending',
    ));
    await StorageService.saveUserId(42);
    await StorageService.savePartner(77, 'Claretta');
    await StorageService.savePartnershipId(9001);

    final repo = ColdStartGameRepository(
        active: const Success<GameNewQuestionResponse?>(null));
    final state = GameState(repository: repo);

    await state.init();
    for (var i = 0; i < 50; i++) {
      if ((await StorageService.getCachedGameQuestion()) == null &&
          state.noQuestionAvailable) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(repo.inserts, 0);
    expect(repo.activeQuestionFetches, 1);
    expect(state.currentQuestion, isNull);
    expect(state.noQuestionAvailable, isTrue);
    expect(await StorageService.getCachedGameQuestion(), isNull);
  });

  test(
      'handleQuestionInsert ignores the echo of our own insert (same id) and '
      'still refetches a partner-created one (new id)', () async {
    final repo = CountingGameRepository();
    final state = GameState(repository: repo);

    await state.fetchNewQuestion();
    expect(state.currentQuestion?.id, 101);
    expect(repo.newQuestionFetches, 1);

    // Our own insert echoes back over Realtime with the same id: no second
    // active-question round trip and no second repaint.
    await state.handleQuestionInsert({'id': 101, 'partnership_id': 9001});
    expect(repo.newQuestionFetches, 1);
    expect(state.currentQuestion?.id, 101);

    // A partner-created question carries a new id: it must still be fetched.
    await state.handleQuestionInsert({'id': 202, 'partnership_id': 9001});
    expect(repo.newQuestionFetches, 2);
  });
}

const _enQuestion = 'Which one plans dates better?';

const _coldQuestion = 'Chi dei due organizza meglio i test?';

class ColdStartGameRepository extends GameRepository {
  ColdStartGameRepository({
    ResultWrapper<GameNewQuestionResponse?>? active,
  }) : activeResult =
            active ?? Success<GameNewQuestionResponse?>(_coldActiveQuestion);

  final ResultWrapper<GameNewQuestionResponse?> activeResult;

  int activeQuestionFetches = 0;
  int inserts = 0;

  static final _coldActiveQuestion = GameNewQuestionResponse(
    id: 101,
    question: _coldQuestion,
    optionA: 'Fede',
    optionB: 'Claretta',
    userIdA: 42,
    userIdB: 77,
    status: 'pending',
  );

  @override
  Future<bool> hasNewGameActivity(
      int uid, int partnerId, int? partnershipId) async {
    return true;
  }

  @override
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchActiveQuestion() async {
    activeQuestionFetches++;
    return activeResult;
  }

  @override
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchNewGameQuestion() async {
    inserts++;
    return const Success<GameNewQuestionResponse?>(null);
  }

  @override
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return const Success<List<GameHistoryItem>>([]);
  }

  @override
  Future<String?> fetchMaxTimestamp({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
  }) async {
    return '2026-10-08T00:00:00.000Z';
  }
}

class LocaleRefreshGameRepository extends GameRepository {
  int activeQuestionFetches = 0;
  int inserts = 0;
  int historyFetches = 0;

  @override
  Future<bool> hasNewGameActivity(
          int uid, int partnerId, int? partnershipId) async =>
      false;

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
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    historyFetches++;
    // The server serves question texts in the CURRENT app locale, so switch
    // between the two variants to reproduce the stale-history-not-refetched
    // bug (B2): before setLocale the history is Italian.
    final locale = await LanguageHelper.currentLocaleCode();
    return Success<List<GameHistoryItem>>([
      GameHistoryItem(
        questionId: 101,
        question: locale == 'en' ? _enQuestion : _coldQuestion,
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
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return const Success<List<GameHistoryItem>>([]);
  }
}

class CountingGameRepository extends GameRepository {
  int newQuestionFetches = 0;

  @override
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchNewGameQuestion() async {
    newQuestionFetches++;
    return Success<GameNewQuestionResponse?>(
      GameNewQuestionResponse(
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
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async {
    return const Success<List<GameHistoryItem>>([]);
  }
}
