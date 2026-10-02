import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 4.9 / F-SM7: logout must reset the six feature states
/// in memory after storage + checkpoints are cleared, so the next login never
/// shows the previous session's data during the refetch window.
class _NoopAuthRepository extends AuthRepository {
  @override
  Future<void> signOut() async {}
}

class _CacheOnlyGameRepository extends GameRepository {
  @override
  Future<bool> hasNewGameActivity(int uid, int partnerId) async => false;

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async => null;

  @override
  Future<ResultWrapper<GameStatsResponse>> fetchGameStats() async =>
      Success(GameStatsResponse(success: true, totalMatches: 0));

  @override
  Future<ResultWrapper<List<GameHistoryItem>>> fetchGameHistory() async =>
      const Success<List<GameHistoryItem>>([]);

  @override
  Future<String?> fetchMaxTimestamp({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
  }) async =>
      null;
}

/// Overrides EVERY network entry point of [DriveRepository].
///
/// A partial fake is not enough here: `initialLoad` fans out to
/// `syncDriveItems`, and any method left un-stubbed falls through to
/// `Supabase.instance` — which throws in a unit test and is swallowed by the
/// `unawaited(...catchError)` in `loadWithChangeDetection`. The test then
/// passes for the wrong reason (verified while writing this file).
class _CacheOnlyDriveRepository extends DriveRepository {
  _CacheOnlyDriveRepository({required this.count});

  final int count;
  int probeCalls = 0;
  int itemFetchCalls = 0;

  @override
  Future<ResultWrapper<DriveChangeProbe>> fetchChangeProbe() async {
    probeCalls += 1;
    return Success(DriveChangeProbe(
      maxUpdatedAt: '2026-01-01T00:00:00.000Z',
      itemCount: count,
    ));
  }

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItems() async {
    itemFetchCalls += 1;

    return const Success<List<DriveItem>>([]);
  }

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItemsIncremental() async {
    itemFetchCalls += 1;

    return const Success<List<DriveItem>>([]);
  }
}

class _FakeMoodRepository extends MoodRepository {
  @override
  Future<ResultWrapper<MoodResponse>> fetchMyMood() async =>
      Success(MoodResponse(
        success: true,
        emoji: '😀',
        createdAt: '2026-09-22T10:00:00.000Z',
      ));

  @override
  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async =>
      Success(MoodResponse(
        success: true,
        emoji: '🥺',
        createdAt: '2026-09-22T11:00:00.000Z',
      ));

  @override
  Future<ResultWrapper<List<MoodEntry>>> fetchTimeline(
          {int limit = 4, int offset = 0}) async =>
      const Success<List<MoodEntry>>([]);

  @override
  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async =>
      const Success<List<String>>([]);

  @override
  Future<bool> hasNewMoods(int uid, int? partnerId) async => false;
}

class _FakeUserRepository extends UserRepository {
  @override
  Future<ResultWrapper<User>> fetchProfile() async {
    return Success(User(id: 1, email: 'user@example.com', displayName: 'Alex'));
  }
}

class _FakePartnershipRepository extends PartnershipRepository {
  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return Success(PartnershipResponse(
      success: true,
      status: 'accepted',
      partner: User(id: 7, displayName: 'Alex'),
      anniversaryDate: DateTime(2026),
    ));
  }

  @override
  Future<ResultWrapper<User>> fetchPartnerProfile() async {
    return Success(User(id: 7, displayName: 'Alex'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test(
      'logout clears storage + checkpoints and runs the registered '
      'feature-state clears', () async {
    final auth = AuthState(authRepo: _NoopAuthRepository());
    final mood = MoodState();
    final homepage = HomepageState();
    final bucket = BucketState();
    final game = GameState(repository: _CacheOnlyGameRepository());
    final drive = DriveState(repository: _CacheOnlyDriveRepository(count: 1));
    final profile = ProfileState(
      userRepo: _FakeUserRepository(),
      partnershipRepo: _FakePartnershipRepository(),
    );

    var callbackCalls = 0;
    auth.onClearFeatureStates = () {
      callbackCalls += 1;
      mood.clear();
      homepage.clear();
      bucket.clear();
      game.clear();
      drive.clear();
      profile.clear();
    };

    await StorageService.saveUserId(1);
    await StorageService.savePartner(7, 'Alex');
    await StorageService.saveMood('me', '😀');
    await StorageService.saveMood('partner', '🥺');
    await StorageService.saveRecentEmojis(['😀']);
    await StorageService.saveTotalMissYou(5);
    await CacheService.saveCheckpoint(
        CacheService.kMissYou, DateTime.now().toUtc().toIso8601String());
    await StorageService.saveGameMatches(3);
    await StorageService.saveGameHistory([
      GameHistoryItem(
        questionId: 101,
        question: 'Q',
        userOption: 1,
        partnerOption: 2,
        createdAt: '2026-09-22T00:00:00.000Z',
      ),
    ]);
    await StorageService.saveDriveItems([
      DriveItem(
        id: 1,
        type: 'image',
        content: 'a.jpg',
        createdAt: '2026-09-01T00:00:00.000Z',
        updatedAt: '2026-09-01T00:00:00.000Z',
        // A favourite, so `favoriteItems` is actually populated before the
        // logout and the post-logout assertion is falsifiable.
        isFavorite: 1,
      ),
    ]);

    await mood.loadCache();
    await homepage.init();
    await game.init();
    await bucket.applyRealtimeEvent(
      eventType: 'insert',
      newRecord: {
        'id': 5,
        'text': 'Skydive',
        'done': false,
        'created_at': '2026-09-01T00:00:00.000Z',
        'updated_at': '2026-09-01T00:00:00.000Z',
        'category': 'Avventura',
      },
      oldRecord: const {},
    );
    await drive.initialLoad();
    await profile.loadProfile(force: true);

    expect(callbackCalls, 0);
    expect(mood.userMood, '😀');
    expect(homepage.totalMissYou, 5);
    expect(bucket.items, isNotEmpty);
    expect(game.gameStats, 3);
    expect(game.history, isNotEmpty);
    expect(drive.driveItems, isNotEmpty);
    // Precondition: favourites were actually built, so the post-logout
    // `favoriteItems isEmpty` below can actually fail.
    expect(drive.favoriteItems, hasLength(1));
    expect(profile.userProfile?.username, 'Alex');

    await auth.logout();

    expect(callbackCalls, 1);
    expect(mood.userMood, '😐');
    expect(mood.partnerMood, '😐');
    expect(mood.recentEmojis, isEmpty);
    expect(homepage.totalMissYou, 0);
    expect(bucket.items, isEmpty);
    expect(game.gameStats, 0);
    expect(game.history, isEmpty);
    expect(drive.driveItems, isEmpty);
    expect(drive.favoriteItems, isEmpty);
    expect(profile.userProfile, isNull);
    expect(profile.partnerProfile, isNull);

    expect(auth.isLoggedIn, isFalse);
    expect(await StorageService.getMood('me'), isNull);
    expect(await StorageService.getUserId(), isNull);
    expect(await StorageService.getTotalMissYou(), isNull);
    expect(await CacheService.getCheckpoint(CacheService.kMissYou), isNull);
  });

  test('mood.clear() resets timeline and updated-at timestamps', () async {
    final mood = MoodState(repository: _FakeMoodRepository());
    await StorageService.saveRecentEmojis(['😀', '🥺']);
    // Five entries — more than one page — so `hasMoreTimeline` is genuinely
    // true before the clear.
    await StorageService.saveTimeline([
      for (var i = 0; i < 5; i++)
        MoodEntry(
          id: 9 + i,
          userId: i.isEven ? 1 : 7,
          isMine: i.isEven,
          emoji: i.isEven ? '😀' : '🥺',
          createdAt: DateTime(2026, 9, 22 - i).toIso8601String(),
        ),
    ]);

    await mood.initMoodScreen();
    // The updated-at timestamps are only assigned by the network fetches, so
    // they must be loaded explicitly for the reset assertions to mean anything.
    await mood.fetchMyMood();
    await mood.fetchPartnerMood();

    expect(mood.recentEmojis, ['😀', '🥺']);
    expect(mood.timeline, isNotEmpty);

    // Preconditions — without these the reset assertions below are vacuous.
    expect(mood.userMoodUpdatedAt, isNotNull);
    expect(mood.partnerMoodUpdatedAt, isNotNull);
    expect(mood.hasMoreTimeline, isTrue);

    mood.clear();

    expect(mood.userMood, '😐');
    expect(mood.partnerMood, '😐');
    expect(mood.recentEmojis, isEmpty);
    expect(mood.userMoodUpdatedAt, isNull);
    expect(mood.partnerMoodUpdatedAt, isNull);
    expect(mood.timeline, isEmpty);
    expect(mood.hasMoreTimeline, isFalse);
  });

  test('game.clear() resets cached data and session identity', () async {
    await StorageService.saveUserId(1);
    await StorageService.savePartner(7, 'Alex');
    await StorageService.saveUsername('Alex');
    await StorageService.saveGameMatches(3);
    await StorageService.saveGameHistory([
      GameHistoryItem(
        questionId: 101,
        question: 'Q',
        userOption: 1,
        createdAt: '2026-09-22T00:00:00.000Z',
      ),
    ]);
    // A cached question must actually exist, otherwise `currentQuestion isNull`
    // below would hold before the clear and prove nothing.
    await StorageService.saveGameQuestion(GameNewQuestionResponse(
      success: true,
      id: 101,
      question: 'Chi dei due organizza meglio i test?',
      optionA: 'Fede',
      optionB: 'Claretta',
      userIdA: 1,
      userIdB: 7,
      status: 'pending',
    ));

    final game = GameState(repository: _CacheOnlyGameRepository());
    await game.init();

    // Preconditions.
    expect(game.currentQuestion, isNotNull);
    expect(game.currentQuestion?.id, 101);
    expect(game.gameStats, 3);
    expect(game.history, isNotEmpty);
    expect(await StorageService.getUserId(), 1);

    game.clear();

    expect(game.currentQuestion, isNull);
    expect(game.history, isEmpty);
    expect(game.gameStats, 0);
    expect(game.isFetchingQuestion, isFalse);
  });

  test('profile.clear() resets all in-memory profile data', () async {
    final profile = ProfileState(
      userRepo: _FakeUserRepository(),
      partnershipRepo: _FakePartnershipRepository(),
    );

    await profile.loadProfile(force: true);

    expect(profile.userProfile?.username, 'Alex');
    expect(profile.partnerProfile?.username, 'Alex');
    expect(profile.anniversaryDate, DateTime(2026));

    profile.clear();

    expect(profile.userProfile, isNull);
    expect(profile.partnerProfile, isNull);
    expect(profile.localProfileImagePath, isNull);
    expect(profile.anniversaryDate, isNull);
    expect(profile.isUploading, isFalse);
  });

  test('drive.clear() drops the memoized change probe', () async {
    final repo = _CacheOnlyDriveRepository(count: 1);
    final drive = DriveState(repository: repo);
    final item = DriveItem(
      id: 1,
      type: 'image',
      content: 'a.jpg',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      isFavorite: 0,
    );
    await StorageService.saveDriveItems([item]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-01-01T00:00:00.000Z');

    await drive.initialLoad();
    expect(repo.probeCalls, 1);

    // A second visit inside the TTL reuses the memoized probe…
    await drive.initialLoad();
    expect(repo.probeCalls, 1);

    // …but after a logout the next user must never inherit it.
    drive.clear();
    await StorageService.saveDriveItems([item]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-01-01T00:00:00.000Z');
    await drive.initialLoad();

    expect(repo.probeCalls, 2);
  });
}
