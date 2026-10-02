import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

class FakeMoodRepository extends MoodRepository {
  int fetchMyMoodCalls = 0;
  int fetchPartnerMoodCalls = 0;
  int fetchRecentCoupleEmojisCalls = 0;
  int fetchTimelineCalls = 0;
  final List<int> fetchTimelineOffsets = [];
  int updateMoodCalls = 0;
  int hasNewMoodsCalls = 0;

  @override
  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    fetchMyMoodCalls++;

    return Success(MoodResponse(success: true, emoji: '😄'));
  }

  @override
  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    fetchPartnerMoodCalls++;

    return Success(MoodResponse(success: true, emoji: '🥰'));
  }

  @override
  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    fetchRecentCoupleEmojisCalls++;

    return const Success<List<String>>(['😄', '🥰', '🎉']);
  }

  @override
  Future<ResultWrapper<List<MoodEntry>>> fetchTimeline(
      {int limit = 4, int offset = 0}) async {
    fetchTimelineCalls++;
    fetchTimelineOffsets.add(offset);

    return const Success<List<MoodEntry>>([]);
  }

  @override
  Future<ResultWrapper<MoodEntry>> updateMood(String emojiChar) async {
    updateMoodCalls++;

    return Success(
      MoodEntry(
        id: 1,
        userId: 42,
        emoji: emojiChar,
        createdAt: DateTime(2026, 5, 6).toIso8601String(),
      ),
    );
  }

  @override
  Future<bool> hasNewMoods(int uid, int? partnerId) async {
    hasNewMoodsCalls++;

    // Force the network path: without this the screen would only ever paint
    // whatever `SharedPreferences` happened to be seeded with.
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

  testWidgets(
      'opening the mood tab loads through the repository, not the cache',
      (tester) async {
    await StorageService.saveUserId(42);
    await StorageService.savePartner(77, 'Partner');

    // A DELIBERATELY DIFFERENT cache seed: the emojis the assertions look for
    // come from `fetchRecentCoupleEmojis`, so they cannot be satisfied by a
    // prefs fixture.
    await StorageService.saveRecentEmojis(['🤖']);

    final repo = FakeMoodRepository();
    final state = MoodState(repository: repo);

    // `TabIndexNotifier` defaults to index 0. `MoodScreen` is declared with
    // tabIndex 2, so `TabScreenMixin._tryLoadData` would never fire and
    // `loadData` would never run — the notifier is seeded to the screen's own
    // index so the screen is actually "active", as it is inside `MainShell`.
    final tabNotifier = TabIndexNotifier()..index = 2;

    await tester.pumpWidget(
      ChangeNotifierProvider<MoodState>.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          home: MoodScreen(tabIndex: 2, tabNotifier: tabNotifier),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // The screen's own load path ran…
    expect(repo.hasNewMoodsCalls, 1,
        reason: 'the active tab must run its change-detection gate');
    expect(repo.fetchRecentCoupleEmojisCalls, 1);
    expect(repo.fetchTimelineCalls, 1);

    // …and the rendered data is the repository's, not the seeded cache.
    expect(find.text('🤖'), findsNothing);
    expect(find.text('😄'), findsWidgets);
    expect(find.text('🥰'), findsWidgets);
    expect(find.text('Mood Board'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Scegli il tuo Mood'), findsOneWidget);

    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();

    // The pick must reach the repository AND be persisted, not just applied to
    // the in-memory field (which is set optimistically before the network call).
    expect(repo.updateMoodCalls, 1);
    expect(state.userMood, '😀');
    expect(await StorageService.getMood('me'), '😀');
  });

  testWidgets('tapping the already-selected emoji does not resubmit it',
      (tester) async {
    await StorageService.saveUserId(42);
    await StorageService.savePartner(77, 'Partner');

    final repo = FakeMoodRepository();
    final state = MoodState(repository: repo);

    // `fetchMyMood` is what puts the current mood into `state.userMood`, which
    // is the value the picker's duplicate guard compares against.
    await state.fetchMyMood();
    expect(state.userMood, '😄',
        reason: 'precondition for the duplicate guard');

    await tester.pumpWidget(
      ChangeNotifierProvider<MoodState>.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          home: MoodScreen(
              tabIndex: 2, tabNotifier: TabIndexNotifier()..index = 2),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Precondition: the picker grid is really on screen and hit-testable,
    // otherwise "the tap did nothing" would be indistinguishable from "the
    // duplicate guard fired".
    expect(find.text('Scegli il tuo Mood'), findsOneWidget);
    final target = find.text('😄').last;
    expect(target, findsOneWidget, reason: 'the target emoji must be rendered');
    expect(
        tester.getCenter(target).dy,
        lessThan(
            tester.view.physicalSize.height / tester.view.devicePixelRatio));

    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(repo.updateMoodCalls, 0,
        reason: 're-picking the current mood must be a no-op, not a re-post');
    expect(state.userMood, '😄',
        reason: 'the mood must be unchanged by the rejected pick');
  });
}
