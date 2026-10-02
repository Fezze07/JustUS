import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

class FakeMoodRepository extends MoodRepository {
  @override
  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    return Success(MoodResponse(success: true, emoji: '😄'));
  }

  @override
  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    return Success(MoodResponse(success: true, emoji: '🥰'));
  }

  @override
  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    return const Success<List<String>>(['😄', '🥰', '🎉']);
  }

  @override
  Future<ResultWrapper<MoodEntry>> updateMood(String emojiChar) async {
    return Success(
      MoodEntry(
        id: 1,
        userId: 42,
        emoji: emojiChar,
        createdAt: DateTime(2026, 5, 6).toIso8601String(),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('updateMood updates the local state and caches the emoji', () async {
    final state = MoodState(repository: FakeMoodRepository());

    await state.updateMood('🔥');

    expect(state.userMood, '🔥');
    expect(await StorageService.getMood('me'), '🔥');
  });

  test('updateMood on error rolls the optimistic mood back and reports nothing',
      () async {
    // Initial value.
    await StorageService.saveMood('me', '😄');
    final state = MoodState(
      repository: ConfigurableFakeMoodRepository(
        updateResult: const NetworkError(),
      ),
    );
    await state.initHome();

    expect(state.userMood, '😄');

    await state.updateMood('👿');

    // The failed update must be invisible: the previous emoji is restored and
    // no error is surfaced to the user.
    expect(state.userMood, '😄');
    expect(state.isLoading, isFalse);
    expect(state.message, isNull);
    // The cache is never written optimistically (asserted in full below).
    expect(await StorageService.getMood('me'), '😄');
  });

  test('initHome loads cached moods from storage', () async {
    await StorageService.saveMood('me', '😄');
    await StorageService.saveMood('partner', '🥰');

    final state = MoodState(repository: FakeMoodRepository());

    await state.initHome();

    expect(state.userMood, '😄');
    expect(state.partnerMood, '🥰');
  });

  test(
      'updateMood on error fully rolls back _recentEmojis/timeline and leaves '
      'the cache unchanged (F-SM12, F-SC14)', () async {
    await StorageService.saveMood('me', '😐');
    await StorageService.saveRecentEmojis(['😄', '🥰']);
    await StorageService.saveTimeline([
      MoodEntry(
        id: 7,
        userId: 42,
        emoji: '😐',
        createdAt: '2026-05-01T00:00:00.000Z',
      ),
    ]);

    final state = MoodState(
        repository: ConfigurableFakeMoodRepository(
      updateResult: const NetworkError(),
    ));
    await state.initMoodScreen();

    await state.updateMood('👿');

    // In-memory state restored completely.
    expect(state.userMood, '😐');
    expect(state.recentEmojis, ['😄', '🥰']);
    expect(state.timeline.single.id, 7);
    expect(state.timeline.single.emoji, '😐');

    // Cache was never written optimistically, so it still holds pre-update
    // data — no failed emoji, no phantom timeline entry.
    expect(await StorageService.getMood('me'), '😐');
    expect(await StorageService.getRecentEmojis(), ['😄', '🥰']);
    expect((await StorageService.getTimeline()).map((e) => e.id), [7]);
  });

  test(
      'updateMood never persists the optimistic phantom; success replaces it '
      'with the server-confirmed entry (F-SC14)', () async {
    final update = Completer<ResultWrapper<MoodEntry>>();
    final state = MoodState(repository: _GatedMoodUpdateRepository(update));

    await StorageService.saveMood('me', '😐');
    await StorageService.saveRecentEmojis(['😄']);
    await StorageService.saveTimeline([
      MoodEntry(
        id: 7,
        userId: 42,
        emoji: '😐',
        createdAt: '2026-05-01T00:00:00.000Z',
      ),
    ]);
    await state.initMoodScreen();

    final flight = state.updateMood('🔥');
    // Let the optimistic portion run; the network future is still held.
    await pumpEventQueue();

    // While in flight, the cache must still hold the pre-update state.
    expect(await StorageService.getMood('me'), '😐');
    expect(await StorageService.getRecentEmojis(), ['😄']);
    expect((await StorageService.getTimeline()).map((e) => e.id), [7]);

    update.complete(Success(MoodEntry(
      id: 1,
      userId: 42,
      emoji: '🔥',
      createdAt: '2026-05-10T00:00:00.000Z',
    )));
    await flight;

    expect(state.userMood, '🔥');
    final persisted = await StorageService.getTimeline();
    expect(persisted.map((e) => e.id), [1, 7]);
    expect(persisted.first.userId, 42);
    expect(persisted.first.emoji, '🔥');
    expect(await StorageService.getMood('me'), '🔥');
    expect(await StorageService.getRecentEmojis(), contains('🔥'));
  });

  group('timeline pagination (network path)', () {
    MoodEntry entry(int id) => MoodEntry(
          id: id,
          userId: 42,
          emoji: 'e$id',
          createdAt: DateTime.utc(2026, 5, id).toIso8601String(),
        );

    test('fetchTimeline stores a defensive copy, not the repository list',
        () async {
      final repo = _PagedMoodRepository(pageSize: 4);
      final state = MoodState(repository: repo);

      await state.fetchTimeline(epoch: CacheService.checkpointEpoch);

      // The state took its own copy, so mutating the repository's list cannot
      // corrupt the state (and vice versa).
      expect(state.timeline.map((e) => e.id), [1, 2, 3, 4]);
      expect(state.hasMoreTimeline, isTrue,
          reason: 'a full page of 4 means there may be more');

      // Feed a second page through the optimistic in-place insert path: with an
      // aliased (possibly unmodifiable) list this would throw.
      expect(() => state.loadMoreTimeline(), returnsNormally);
      await pumpEventQueue();
      expect(state.timeline.map((e) => e.id), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(repo.offsets, [0, 4],
          reason: 'the second page must request the current offset');
      expect(state.hasMoreTimeline, isTrue);
    });

    test('loadMoreTimeline appends and stops on a short page', () async {
      final repo = _PagedMoodRepository(pageSize: 2);
      final state = MoodState(repository: repo);

      await state.fetchTimeline(epoch: CacheService.checkpointEpoch);
      // 2 < 4 -> the page was short, so there is nothing left to page.
      expect(state.hasMoreTimeline, isFalse);

      await state.loadMoreTimeline();
      await pumpEventQueue();

      expect(state.timeline.map((e) => e.id), [1, 2, 3, 4]);
      expect(state.hasMoreTimeline, isFalse,
          reason: 'a short page means the timeline is exhausted');
      // Persisted state must match the in-memory list, not just the last page.
      expect(
          (await StorageService.getTimeline()).map((e) => e.id), [1, 2, 3, 4]);
    });

    test('a cached page of exactly the page size reports more, not fewer',
        () async {
      // Regression: the cache path used `>` instead of `>=`, so a cold start
      // with exactly one full page locked the user out of older entries.
      await StorageService.saveTimeline(
          [entry(1), entry(2), entry(3), entry(4)]);

      final repo = _PagedMoodRepository(pageSize: 4);
      final state = MoodState(repository: repo);
      // No user id in storage -> `_hasMoodChanges` returns false, so
      // `initMoodScreen` deterministically takes the cache path only.
      await state.initMoodScreen();

      expect(state.timeline, hasLength(4));
      expect(state.hasMoreTimeline, isTrue);
      expect(repo.offsets, isEmpty,
          reason: 'precondition: the network path must not have run');
    });

    test('a cached short page reports no more', () async {
      await StorageService.saveTimeline([entry(1), entry(2), entry(3)]);

      final state = MoodState(repository: _PagedMoodRepository(pageSize: 4));
      await state.initMoodScreen();

      expect(state.hasMoreTimeline, isFalse);
    });

    test('loadMoreTimeline continues from a cache-loaded page', () async {
      // End-to-end pagination: the cached page is followed by a network page,
      // which is the flow the `>=` fix enables on a cold start.
      await StorageService.saveTimeline(
          [entry(1), entry(2), entry(3), entry(4)]);
      final repo = _PagedMoodRepository(pageSize: 4);

      final state = MoodState(repository: repo);
      await state.initMoodScreen();
      expect(state.timeline.map((e) => e.id), [1, 2, 3, 4]);

      await state.loadMoreTimeline();
      await pumpEventQueue();

      expect(repo.offsets, [4],
          reason: 'paging must resume after the 4 cached entries');
      expect(state.timeline.map((e) => e.id), [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });
}

/// Serves deterministic, page-sized timeline slices and records the offsets it
/// was asked for, so pagination can be asserted without a live backend.
class _PagedMoodRepository extends MoodRepository {
  _PagedMoodRepository({required this.pageSize});

  /// Required rather than defaulted: every test states the page size it is
  /// asserting against instead of silently relying on a default.
  final int pageSize;
  final List<int> offsets = <int>[];

  @override
  Future<ResultWrapper<List<MoodEntry>>> fetchTimeline(
      {int limit = 4, int offset = 0}) async {
    offsets.add(offset);
    final slice = <MoodEntry>[
      for (var i = offset + 1; i <= offset + pageSize; i++)
        MoodEntry(
          id: i,
          userId: 42,
          emoji: 'e$i',
          createdAt: DateTime.utc(2026, 5, i).toIso8601String(),
        ),
    ];
    return Success<List<MoodEntry>>(slice);
  }
}

class _GatedMoodUpdateRepository extends MoodRepository {
  _GatedMoodUpdateRepository(this.updateCompletion);

  final Completer<ResultWrapper<MoodEntry>> updateCompletion;

  @override
  Future<ResultWrapper<MoodEntry>> updateMood(String emojiChar) {
    return updateCompletion.future;
  }
}

class ConfigurableFakeMoodRepository extends MoodRepository {
  final ResultWrapper<MoodResponse>? fetchResult;
  final ResultWrapper<MoodEntry>? updateResult;

  ConfigurableFakeMoodRepository({this.fetchResult, this.updateResult});

  @override
  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    return fetchResult ?? Success(MoodResponse(success: true, emoji: '😄'));
  }

  @override
  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    return Success(MoodResponse(success: true, emoji: '🥰'));
  }

  @override
  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    return const Success<List<String>>([]);
  }

  @override
  Future<ResultWrapper<MoodEntry>> updateMood(String emojiChar) async {
    return updateResult ?? const NetworkError();
  }
}
