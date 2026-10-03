import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

/// BaseState exposes every helper under test publicly, so no re-export shim is
/// needed here.
class _TestState extends BaseState {}

/// Stubs only the server-timestamp probe, so `hasChanges` runs its real
/// checkpoint comparison against a mocked SharedPreferences and never touches
/// Supabase.
class _RecordingRepository extends BaseRepository {
  _RecordingRepository({required this.serverMax});

  final String? serverMax;
  int fetchCalls = 0;

  @override
  Future<String?> fetchMaxTimestamp({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
  }) async {
    fetchCalls++;
    return serverMax;
  }
}

/// Repository whose only job is the `hasNewMoods` change probe used by
/// `MoodState.initHome`, plus counters that show whether the init actually went
/// to the network.
class _MoodChangeProbeRepository extends MoodRepository {
  _MoodChangeProbeRepository({required this.changed});

  bool changed;
  int hasNewMoodsCalls = 0;
  int fetchMyMoodCalls = 0;
  int fetchPartnerMoodCalls = 0;
  int fetchRecentCoupleEmojisCalls = 0;
  int fetchTimelineCalls = 0;

  @override
  Future<bool> hasNewMoods(int uid, int? partnerId) async {
    hasNewMoodsCalls++;
    return changed;
  }

  @override
  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    fetchMyMoodCalls++;
    return Success(MoodResponse(success: true, emoji: 'me'));
  }

  @override
  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    fetchPartnerMoodCalls++;
    return Success(MoodResponse(success: true, emoji: 'partner'));
  }

  @override
  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    fetchRecentCoupleEmojisCalls++;
    return const Success<List<String>>([]);
  }

  @override
  Future<ResultWrapper<List<MoodEntry>>> fetchTimeline({
    int limit = 4,
    int offset = 0,
  }) async {
    fetchTimelineCalls++;
    return const Success<List<MoodEntry>>([]);
  }
}

final List<String> _printed = <String>[];
final List<Object> _uncaught = <Object>[];

/// Draws one frame so pending post-frame callbacks run.
///
/// `tester.pump()` only draws a frame when one is already scheduled, and
/// `addPostFrameCallback` does not schedule one - without this every coalesced
/// notification would stay undelivered and each assertion below would see 0.
Future<void> _pumpFrame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
}

/// Runs [body] in a zone that captures everything `ErrorHandler` logs (it goes
/// through `AnsiLogger`, which is `print`) and everything that would otherwise
/// become an unhandled async error.
Future<void> _captured(Future<void> Function() body) async {
  await runZonedGuarded(
    body,
    (error, stack) => _uncaught.add(error),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => _printed.add(line),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    _printed.clear();
    _uncaught.clear();
  });

  group('BaseState frame coalescing', () {
    testWidgets(
        'N mutations in one frame produce exactly one notification', (tester) async {
      final state = _TestState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.setLoading(true);
      state.setMessage('a');
      state.setMessage('b');
      state.clearMessage();
      state.setLoading(false);

      expect(notifications, 0,
          reason: 'delivery is deferred to the end of the frame');

      await _pumpFrame(tester);

      expect(notifications, 1);
    });

    testWidgets('a mutation in a later frame notifies again', (tester) async {
      final state = _TestState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.setLoading(true);
      await _pumpFrame(tester);
      expect(notifications, 1);

      state.setLoading(false);
      await _pumpFrame(tester);

      expect(notifications, 2,
          reason: '_pendingNotify must be reset inside the frame callback');
    });

    testWidgets('coalescing defers the notification, not the mutation',
        (tester) async {
      final state = _TestState();

      state.setLoading(true);
      state.setMessage('kept');

      expect(state.isLoading, isTrue);
      expect(state.message, 'kept');

      await _pumpFrame(tester);
    });

    testWidgets('the pending flag resets even when nothing is listening',
        (tester) async {
      final state = _TestState();
      var notifications = 0;

      state.setLoading(true);
      await _pumpFrame(tester);
      expect(notifications, 0, reason: 'no listener was attached');

      state.addListener(() => notifications++);
      state.setLoading(false);
      await _pumpFrame(tester);

      expect(notifications, 1,
          reason: '_pendingNotify must reset before the hasListeners check, '
              'otherwise a later attach is swallowed');
    });
  });

  group('BaseState.runSafe', () {
    test('returns true and clears loading after the action', () async {
      final state = _TestState();
      final observed = <bool>[];

      final ok = await state.runSafe(() async {
        observed.add(state.isLoading);
      });

      expect(ok, isTrue);
      expect(observed, [true], reason: 'showLoading defaults to true');
      expect(state.isLoading, isFalse,
          reason: 'the finally block must clear loading on success');
    });

    test('returns false and forwards the error instead of rethrowing',
        () async {
      final state = _TestState();
      var ok = true;

      await _captured(() async {
        ok = await state.runSafe(() async => throw StateError('runSafe boom'));
      });

      expect(ok, isFalse);
      expect(_printed.join('\n'), contains('runSafe boom'));
      expect(_uncaught, isEmpty);
    });

    test('clears loading on the failure path too', () async {
      final state = _TestState();

      await _captured(() async {
        await state.runSafe(() async => throw StateError('runSafe boom'));
      });

      expect(state.isLoading, isFalse);
    });

    testWidgets('showLoading: true coalesces the two setLoading calls into one '
        'notification', (tester) async {
      final state = _TestState();
      var notifications = 0;
      state.addListener(() => notifications++);

      final ok = await state.runSafe(() async {});

      expect(ok, isTrue);
      await _pumpFrame(tester);
      expect(notifications, 1);
    });

    testWidgets('showLoading: false skips setLoading but still notifies once',
        (tester) async {
      final state = _TestState();
      var notifications = 0;
      state.addListener(() => notifications++);

      final ok = await state.runSafe(() async {}, showLoading: false);

      expect(ok, isTrue);
      expect(state.isLoading, isFalse);
      await _pumpFrame(tester);
      expect(notifications, 1,
          reason: 'the else branch must still notify so listeners see the '
              'completed action');
    });

    test('resets a pre-existing message on every call', () async {
      final state = _TestState();

      state.setMessage('stale');
      await state.runSafe(() async {});
      expect(state.message, isNull);

      state.setMessage('stale again');
      await _captured(() async {
        await state.runSafe(() async => throw StateError('runSafe boom'));
      });
      expect(state.message, isNull,
          reason: 'the reset must run on the failure path too');
    });

    test('the message reset happens before the action, so a message set by the '
        'action survives', () async {
      final state = _TestState();
      state.setMessage('stale');

      await state.runSafe(() async {
        state.setMessage('saved');
      });

      expect(state.message, 'saved');
    });
  });

  group('BaseState.handleResult', () {
    test('Success awaits onSuccess and hands it the value', () async {
      final state = _TestState();
      final seen = <int>[];

      await state.handleResult(const Success<int>(7),
          onSuccess: (int value) async => seen.add(value));

      expect(seen, [7]);
    });

    testWidgets(
        'Success does not notify unless notifyOnSuccess is true', (tester) async {
      final state = _TestState();
      var notifications = 0;
      state.addListener(() => notifications++);

      await state.handleResult(const Success<int>(1));
      await _pumpFrame(tester);
      expect(notifications, 0,
          reason: 'notifyOnSuccess defaults to false, so a Success is silent');

      await state.handleResult(const Success<int>(2), notifyOnSuccess: true);
      await _pumpFrame(tester);
      expect(notifications, 1);
    });

    testWidgets('notifyOnSuccess fires only after onSuccess completes',
        (tester) async {
      final state = _TestState();
      final gate = Completer<void>();
      var onSuccessDone = false;
      var notifications = 0;
      state.addListener(() => notifications++);

      final pending = state.handleResult(
        const Success<int>(1),
        onSuccess: (int value) => gate.future.then((_) {
          onSuccessDone = true;
        }),
        notifyOnSuccess: true,
      );

      await _pumpFrame(tester);
      expect(notifications, 0,
          reason: 'the notification must wait for onSuccess so listeners see '
              'the post-action state');

      gate.complete();
      await pending;
      await _pumpFrame(tester);

      expect(notifications, 1);
      expect(onSuccessDone, isTrue);
    });

    testWidgets('GenericError notifies and forwards the error', (tester) async {
      final state = _TestState();
      var notifications = 0;
      state.addListener(() => notifications++);

      await _captured(() async {
        await state.handleResult(
            const GenericError<int>(message: 'generic boom'));
      });
      await _pumpFrame(tester);

      expect(notifications, 1);
      expect(_printed.join('\n'), contains('generic boom'));
    });

    testWidgets(
        'NetworkError notifies and forwards AppError.network(), not the raw result',
        (tester) async {
      final state = _TestState();
      var notifications = 0;
      state.addListener(() => notifications++);

      await _captured(() async {
        await state.handleResult(
            const NetworkError<int>(message: 'raw network detail'));
      });
      await _pumpFrame(tester);

      expect(notifications, 1);
      final log = _printed.join('\n');
      expect(log, contains(ErrorCodes.localNetworkError));
      expect(log, contains('Network unavailable'));
      expect(log, isNot(contains('raw network detail')),
          reason: 'the raw NetworkError must be replaced by AppError.network()');
    });
  });

  group('BaseState.loadWithChangeDetection', () {
    test('runs loadFromCache before hasChanges', () async {
      final state = _TestState();
      final order = <String>[];

      await state.loadWithChangeDetection(
        loadFromCache: () async => order.add('cache'),
        hasChanges: () async {
          order.add('hasChanges');
          return false;
        },
        fetchFromNetwork: () async => order.add('network'),
      );

      expect(order, ['cache', 'hasChanges'],
          reason: 'the cache must be in memory before it is checkpointed, '
              'otherwise the checkpoint advances past unsynced data');
    });

    test('hasChanges == false never calls fetchFromNetwork', () async {
      final state = _TestState();
      var networkCalls = 0;

      await state.loadWithChangeDetection(
        loadFromCache: () async {},
        hasChanges: () async => false,
        fetchFromNetwork: () async {
          networkCalls++;
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(networkCalls, 0,
          reason: 'an unchanged checkpoint must not trigger a refetch');
    });

    test('hasChanges == true fetches, but the returned future does not wait for '
        'it', () async {
      final state = _TestState();
      var networkCalls = 0;
      var networkFinished = false;

      await state.loadWithChangeDetection(
        loadFromCache: () async {},
        hasChanges: () async => true,
        fetchFromNetwork: () async {
          networkCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          networkFinished = true;
        },
      );

      expect(networkCalls, 1);
      expect(networkFinished, isFalse,
          reason: 'the network refresh is fire-and-forget by design');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(networkFinished, isTrue);
    });

    test('a fetchFromNetwork throw is absorbed by ErrorHandler, not left as an '
        'unhandled async error', () async {
      final state = _TestState();

      await _captured(() async {
        await state.loadWithChangeDetection(
          loadFromCache: () async {},
          hasChanges: () async => true,
          fetchFromNetwork: () async => throw StateError('fetch boom'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });

      expect(_printed.join('\n'), contains('fetch boom'));
      expect(_uncaught, isEmpty);
    });
  });

  group('BaseRepository.hasChanges', () {
    const key = 'base_state_test_chk';
    final checkpoint = DateTime.utc(2026, 3, 1, 12);

    Future<bool> hasChanges(String? saved, String? serverMax) async {
      if (saved != null) await CacheService.saveCheckpoint(key, saved);
      final repo = _RecordingRepository(serverMax: serverMax);

      final result = await repo.hasChanges(
        table: 'moods',
        field: 'updated_at',
        cacheKey: key,
      );

      return result;
    }

    test('an absent checkpoint refetches without querying the server', () async {
      final repo = _RecordingRepository(serverMax: checkpoint.toIso8601String());

      final result = await repo.hasChanges(
        table: 'moods',
        field: 'updated_at',
        cacheKey: key,
      );

      expect(result, isTrue);
      expect(repo.fetchCalls, 0,
          reason: 'a missing checkpoint must short-circuit before the query');
    });

    test('an unchanged server timestamp does not refetch', () async {
      expect(await hasChanges(checkpoint.toIso8601String(),
          checkpoint.toIso8601String()), isFalse);
    });

    test('a strictly newer server timestamp refetches', () async {
      expect(
          await hasChanges(
              checkpoint.toIso8601String(),
              checkpoint.add(const Duration(seconds: 1)).toIso8601String()),
          isTrue);
    });

    test('an older server timestamp does not refetch', () async {
      expect(
          await hasChanges(
              checkpoint.toIso8601String(),
              checkpoint.subtract(const Duration(seconds: 1)).toIso8601String()),
          isFalse,
          reason: 'the comparison is strict, so a server clock that moves back '
              'must not cause a refetch loop');
    });

    test('the EMPTY sentinel against a populated server refetches', () async {
      expect(await hasChanges(CacheService.kCheckpointEmpty,
          checkpoint.toIso8601String()), isTrue);
    });

    test('an emptied table behind a real checkpoint is read as a deletion',
        () async {
      expect(await hasChanges(checkpoint.toIso8601String(), null), isTrue);
    });

    test('an emptied table behind the EMPTY sentinel is not a change', () async {
      expect(await hasChanges(CacheService.kCheckpointEmpty, null), isFalse);
    });

    test('an unparseable server timestamp refetches', () async {
      expect(await hasChanges(checkpoint.toIso8601String(), 'not-a-date'),
          isTrue);
    });

    test('an unparseable checkpoint refetches', () async {
      expect(await hasChanges('garbage', checkpoint.toIso8601String()), isTrue);
    });
  });

  group('update detection: an unchanged checkpoint costs no fetch and no write',
      () {
    const key = 'update_blindness_chk';
    final checkpoint = DateTime.utc(2026, 4, 1, 9);
    final newer = DateTime.utc(2026, 4, 2, 9);

    /// Runs the real `loadWithChangeDetection` + `BaseRepository.hasChanges`
    /// pair and counts both sides of the decision: network fetches and
    /// checkpoint writes.
    Future<({int fetches, int writes})> loadOnce({
      required String serverMax,
      required String? saved,
    }) async {
      if (saved != null) await CacheService.saveCheckpoint(key, saved);
      final state = _TestState();
      final repo = _RecordingRepository(serverMax: serverMax);
      var fetches = 0;
      var writes = 0;

      await state.loadWithChangeDetection(
        loadFromCache: () async {},
        hasChanges: () => repo.hasChanges(
          table: 'moods',
          field: 'updated_at',
          cacheKey: key,
        ),
        fetchFromNetwork: () async {
          fetches++;
          writes++;
          await CacheService.saveCheckpoint(key, newer.toIso8601String());
        },
      );
      // The refresh is fire-and-forget, so let it drain before counting.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      return (fetches: fetches, writes: writes);
    }

    test('the server timestamp is probed but the fetch and the checkpoint write '
        'are skipped', () async {
      final result = await loadOnce(
        serverMax: checkpoint.toIso8601String(),
        saved: checkpoint.toIso8601String(),
      );

      expect(result.fetches, 0,
          reason: 'a checkpoint that already covers the newest server row must '
              'not trigger a refetch');
      expect(result.writes, 0,
          reason: 'an unchanged round must not rewrite the checkpoint');
      expect(await CacheService.getCheckpoint(key),
          checkpoint.toIso8601String(),
          reason: 'the stored checkpoint must stay byte-identical');
    });

    test('positive control: a newer server row fetches once and advances the '
        'checkpoint', () async {
      final result = await loadOnce(
        serverMax: newer.toIso8601String(),
        saved: checkpoint.toIso8601String(),
      );

      expect(result.fetches, 1,
          reason: 'the writer above must be reachable, otherwise the zero in '
              'the previous test would prove nothing');
      expect(result.writes, 1);
      expect(await CacheService.getCheckpoint(key), newer.toIso8601String());
    });
  });

  group('MoodState.initHome change gate', () {
    test('an unchanged moods checkpoint keeps the network untouched and the '
        'checkpoint intact', () async {
      final checkpoint = DateTime.utc(2026, 4, 3, 10).toIso8601String();
      await StorageService.saveUserId(42);
      await StorageService.savePartner(77, 'Partner');
      await CacheService.saveCheckpoint(CacheService.kMoods, checkpoint);

      final repo = _MoodChangeProbeRepository(changed: false);
      final state = MoodState(repository: repo);

      await state.initHome();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.hasNewMoodsCalls, 1,
          reason: 'the probe itself always runs');
      expect(repo.fetchMyMoodCalls, 0);
      expect(repo.fetchPartnerMoodCalls, 0);
      expect(await CacheService.getCheckpoint(CacheService.kMoods), checkpoint,
          reason: 'no fetch means no checkpoint churn');

      state.clear();
    });

    test('a changed moods checkpoint fetches both moods and advances the '
        'checkpoint', () async {
      final checkpoint = DateTime.utc(2026, 4, 3, 10).toIso8601String();
      await StorageService.saveUserId(42);
      await StorageService.savePartner(77, 'Partner');
      await CacheService.saveCheckpoint(CacheService.kMoods, checkpoint);

      final repo = _MoodChangeProbeRepository(changed: true);
      final state = MoodState(repository: repo);

      await state.initHome();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.fetchMyMoodCalls, 1);
      expect(repo.fetchPartnerMoodCalls, 1);
      expect(state.userMood, 'me');
      expect(state.partnerMood, 'partner');
      expect(await CacheService.getCheckpoint(CacheService.kMoods),
          isNot(checkpoint),
          reason: 'a completed fetch must advance the checkpoint');

      state.clear();
    });

    test('without a signed-in user the gate stays closed', () async {
      final repo = _MoodChangeProbeRepository(changed: true);
      final state = MoodState(repository: repo);

      await state.initHome();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.hasNewMoodsCalls, 0,
          reason: 'without a user id there is nothing to compare against');
      expect(repo.fetchMyMoodCalls, 0);

      state.clear();
    });
  });
}