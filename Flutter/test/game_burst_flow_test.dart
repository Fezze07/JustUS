import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

class GameBurstFakeRepository extends GameRepository {
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

/// F-RT1 acceptance: when both-answered game events are applied (i.e. nothing
/// is dropped by the debounce), the partner answer INSERT updates history and
/// the subsequent question UPDATE clears the question.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  Future<GameState> readyState() async {
    await StorageService.saveUserId(42);
    final state = GameState(repository: GameBurstFakeRepository());
    await state.fetchNewQuestion();
    expect(state.currentQuestion?.id, 101);
    return state;
  }

  test('partner answer INSERT then both-answered UPDATE keeps history entry',
      () async {
    final state = await readyState();

    await state.handleAnswerInsert({
      'game_id': 101,
      'user_id': 77,
      'selected_option': 42,
    });

    expect(state.currentQuestion?.partnerAnswered, isTrue);
    expect(state.history.length, 1);
    expect(state.history.first.questionId, 101);
    expect(state.history.first.partnerOption, 42);

    await state.handleQuestionUpdate({'id': 101, 'status': 'both_answered'});

    expect(state.currentQuestion, isNull);
    expect(state.history.length, 1);
    expect(state.history.first.partnerOption, 42);
    expect(await StorageService.getGameHistory(), isNotEmpty);
  });

  test('submitAnswer after partner answer clears the question', () async {
    final state = await readyState();

    await state.handleAnswerInsert({
      'game_id': 101,
      'user_id': 77,
      'selected_option': 42,
    });

    await state.submitAnswer('A');

    expect(state.currentQuestion, isNull);
    expect(state.history.first.userOption, 42);
    expect(state.history.first.partnerOption, 42);
  });
}
