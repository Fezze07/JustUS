import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

class _HistoryGameRepository extends GameRepository {
  final List<int> historyOffsets = [];

  @override
  Future<ResultWrapper<GameNewQuestionResponse?>> fetchActiveQuestion() async {
    return Success(GameNewQuestionResponse(
      id: 101,
      question: 'Current question',
      optionA: 'Me',
      optionB: 'Partner',
      userIdA: 42,
      userIdB: 77,
      status: 'pending',
    ));
  }

  @override
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory(
      {int limit = GameRepository.historyPageSize, int offset = 0}) async {
    historyOffsets.add(offset);

    final all = List.generate(
      7,
      (i) => GameHistoryItem(
        questionId: i + 1,
        question: 'Question ${i + 1}',
        userOption: 42,
        partnerOption: 77,
        createdAt: '2026-05-0${i + 1}T00:00:00Z',
      ),
    );

    return Success(all.skip(offset).take(limit).toList());
  }

  @override
  Future<bool> hasNewGameActivity(
      int uid, int partnerId, int? partnershipId) async {
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  Future<(_HistoryGameRepository, GameState)> pumpGame(
      WidgetTester tester) async {
    await StorageService.saveUserId(42);
    await StorageService.savePartner(77, 'Partner');

    final repository = _HistoryGameRepository();
    final state = GameState(repository: repository);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameState>.value(value: state),
          ChangeNotifierProvider<ProfileState>(create: (_) => ProfileState()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: GameScreen(
            tabIndex: 1,
            tabNotifier: TabIndexNotifier()..index = 1,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    return (repository, state);
  }

  testWidgets('"Show more" fetches and appends the next history page',
      (tester) async {
    final (repository, state) = await pumpGame(tester);

    for (var i = 1; i <= 5; i++) {
      expect(find.text('Question $i'), findsOneWidget);
    }
    expect(find.text('Question 6'), findsNothing);
    expect(repository.historyOffsets, [0]);

    await tester.ensureVisible(find.text('Show more'));
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    // Let the async page load and its cache write settle.
    await tester.pump();
    await tester.pump();

    expect(repository.historyOffsets, [0, 5],
        reason: 'the page offset comes from the entries already loaded');
    expect(state.history, hasLength(7),
        reason: 'the second page is appended to the loaded list');
    expect(find.text('Question 6'), findsOneWidget);
    expect(find.text('Question 7'), findsOneWidget);
    expect(find.text('Show more'), findsNothing,
        reason: 'the whole history is visible now');
  });

  testWidgets('the dead "View All" header action is gone', (tester) async {
    await pumpGame(tester);

    expect(find.text('View All'), findsNothing);
  });
}
