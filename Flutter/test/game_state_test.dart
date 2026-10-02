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

    await state.submitAnswer('A');

    expect(state.message, 'Risposta inviata! ✨');
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

  test(
      'fetchNewQuestion sets currentQuestion to null on GenericError("No questions")',
      () async {
    // If we have an existing question...
    final state = GameState(
        repository: ConfigurableFakeGameRepository(
      fetchResult: const GenericError(message: 'No questions'),
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

    // Now fetch, which returns 'No questions'
    await state.fetchNewQuestion();

    expect(state.currentQuestion, isNull);
    expect(state.isLoading, isFalse);
  });

  test('submitAnswer with invalid option aborts and sets error message',
      () async {
    final state = GameState(repository: FakeGameRepository());
    await state.fetchNewQuestion(); // Sets currentQuestion to 101

    // Pass an invalid option 'C'
    await state.submitAnswer('C');

    expect(state.message, 'Errore: opzione non valida');
    expect(state.isLoading, isFalse);
    expect(
        state.currentQuestion?.status, 'pending'); // Did not change to waiting
  });
}

class ConfigurableFakeGameRepository extends GameRepository {
  final ResultWrapper<GameNewQuestionResponse>? fetchResult;

  ConfigurableFakeGameRepository({this.fetchResult});

  @override
  Future<ResultWrapper<GameNewQuestionResponse>> fetchNewGameQuestion() async {
    return fetchResult ?? const NetworkError();
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
