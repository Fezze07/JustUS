import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _FakeRpc extends Mock implements sb.PostgrestFilterBuilder<dynamic> {
  _FakeRpc(this.result);

  final Object? result;

  @override
  Future<R> then<R>(Function(Object? value) onValue,
      {Function? onError}) async {
    try {
      return await onValue(result) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

class _RecordingMoodRepository extends MoodRepository {
  _RecordingMoodRepository({required super.sbClient});

  @override
  Future<void> notifyPartnerOnce({
    required String notificationKey,
    Map<String, String> params = const {},
  }) async {}
}

/// Returns a fixed server timestamp for the current mood and holds the update
/// future open, so the optimistic window can be inspected.
class _GatedMoodRepository extends MoodRepository {
  _GatedMoodRepository(this.updateCompletion);

  final Completer<ResultWrapper<MoodEntry>> updateCompletion;
  static const oldTimestamp = '2026-05-01T00:00:00.000Z';

  @override
  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    return Success(
      MoodResponse(success: true, emoji: '😐', createdAt: oldTimestamp),
    );
  }

  @override
  Future<ResultWrapper<MoodEntry>> updateMood(String emojiChar) {
    return updateCompletion.future;
  }

  @override
  Future<void> notifyPartnerOnce({
    required String notificationKey,
    Map<String, String> params = const {},
  }) async {}
}

/// Returns one timeline entry stamped by the server, far behind any
/// device-clock checkpoint.
class _TimelineMoodRepository extends MoodRepository {
  static const serverTimestamp = '2026-05-02T00:00:00.000Z';

  @override
  Future<ResultWrapper<List<MoodEntry>>> fetchTimeline({
    int limit = 4,
    int offset = 0,
  }) async {
    return Success<List<MoodEntry>>([
      MoodEntry(
        id: 1,
        userId: 42,
        emoji: '🔥',
        createdAt: serverTimestamp,
      ),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('updateMood maps created_at from the row returned by mood_set',
      () async {
    await StorageService.saveUserId(42);
    const serverTimestamp = '2026-01-02T03:04:05.000Z';
    final client = _MockClient();
    when(() => client.rpc('mood_set', params: {'p_emoji_char': '🔥'}))
        .thenAnswer((_) => _FakeRpc({
              'id': 7,
              'user_id': 42,
              'created_at': serverTimestamp,
            }));
    final repo = _RecordingMoodRepository(sbClient: client);

    final result = await repo.updateMood('🔥');

    expect(result, isA<Success<MoodEntry>>());
    final entry = (result as Success<MoodEntry>).value;
    expect(entry.id, 7);
    expect(entry.emoji, '🔥');
    expect(entry.createdAt, serverTimestamp,
        reason: 'the device clock must not supply the row timestamp');
  });

  test('the optimistic mood keeps the previous server timestamp', () async {
    await StorageService.saveUserId(42);
    final update = Completer<ResultWrapper<MoodEntry>>();
    final state = MoodState(repository: _GatedMoodRepository(update));

    await state.fetchMyMood();
    final flight = state.updateMood('🔥');
    await pumpEventQueue();

    expect(state.userMoodUpdatedAt, _GatedMoodRepository.oldTimestamp,
        reason: 'the checkpoint source must not be stamped from the device');
    expect(state.timeline.single.createdAt, _GatedMoodRepository.oldTimestamp);

    const serverTimestamp = '2026-05-10T00:00:00.000Z';
    update.complete(Success(MoodEntry(
      id: 9,
      userId: 42,
      emoji: '🔥',
      createdAt: serverTimestamp,
    )));
    await flight;

    expect(state.userMoodUpdatedAt, serverTimestamp);
    expect(
        await CacheService.getCheckpoint(CacheService.kMoods), serverTimestamp,
        reason: 'the checkpoint must equal the newest returned created_at');
  });

  test('a future checkpoint is reset to the newest returned row', () async {
    final future =
        DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
    await CacheService.saveCheckpoint(CacheService.kMoods, future);

    final state = MoodState(repository: _TimelineMoodRepository());
    await state.fetchTimeline(epoch: CacheService.checkpointEpoch);

    expect(await CacheService.getCheckpoint(CacheService.kMoods),
        _TimelineMoodRepository.serverTimestamp);
  });
}
