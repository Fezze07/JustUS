import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 4.10 / F-SM14: checkpoint writes must not survive a
/// clear for the previous user. Fetch roots capture `CacheService.checkpointEpoch`
/// at operation start; a logout/wipe clear that lands while the fetch is in
/// flight bumps the epoch, so the stale write-back is dropped.
class _CheckpointHost with CheckpointMixin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('F-SM14: an in-flight fetch write-back after clearAll is dropped',
      () async {
    const ts = '2026-09-23T10:00:00.000Z';

    await CacheService.saveCheckpoint(CacheService.kMoods, ts);
    expect(await CacheService.getCheckpoint(CacheService.kMoods), ts);

    final fetchEpoch = CacheService.checkpointEpoch;
    await CacheService.clearAll();

    await CacheService.saveCheckpoint(CacheService.kMoods, ts,
        epoch: fetchEpoch);

    expect(await CacheService.getCheckpoint(CacheService.kMoods), isNull);
  });

  test('F-SM14: a write in the post-clear epoch still lands', () async {
    const ts = '2026-09-23T10:00:00.000Z';

    await CacheService.clearAll();

    await CacheService.saveCheckpoint(CacheService.kMoods, ts,
        epoch: CacheService.checkpointEpoch);

    expect(await CacheService.getCheckpoint(CacheService.kMoods), ts);
  });

  test('F-SM14: clearCheckpoints and purge also invalidate in-flight writes',
      () async {
    const ts = '2026-09-23T10:00:00.000Z';

    for (final clear in <Future<void> Function()>[
      () => CacheService.clearCheckpoints([CacheService.kGameAnswers]),
      CacheService.clearAll,
      () => CacheService.purge(oldId: 1, newId: 2),
    ]) {
      await CacheService.saveCheckpoint(CacheService.kGameAnswers, ts);
      final fetchEpoch = CacheService.checkpointEpoch;
      await clear();
      await CacheService.saveCheckpoint(CacheService.kGameAnswers, ts,
          epoch: fetchEpoch);

      expect(
          await CacheService.getCheckpoint(CacheService.kGameAnswers), isNull,
          reason: 'stale write-back must be dropped for $clear');
    }
  });

  test('F-SM14: mixin checkpoint helpers respect the epoch gate', () async {
    final host = _CheckpointHost();
    final item = BucketItem.fromJson({
      'id': 1,
      'text': 'Pot plants',
      'done': false,
      'created_at': '2026-09-23T10:00:00.000Z',
      'updated_at': '2026-09-23T10:00:00.000Z',
      'category': 'Home',
    });

    final fetchEpoch = CacheService.checkpointEpoch;
    await CacheService.clearAll();

    await host.saveMaxTimestampCheckpointFromItems(
      checkpointKey: CacheService.kBucketItems,
      items: [item],
      timestampField: (e) => (e as BucketItem).updatedAt,
      epoch: fetchEpoch,
    );

    expect(await CacheService.getCheckpoint(CacheService.kBucketItems), isNull);

    await host.saveMaxTimestampCheckpointFromItems(
      checkpointKey: CacheService.kBucketItems,
      items: [item],
      timestampField: (e) => (e as BucketItem).updatedAt,
      epoch: CacheService.checkpointEpoch,
    );

    expect(await CacheService.getCheckpoint(CacheService.kBucketItems),
        '2026-09-23T10:00:00.000Z');
  });

  testWidgets(
      'F-SM14: bucket debounced flush after a clear cannot rewrite '
      'the checkpoint', (tester) async {
    final bucket = BucketState();
    await bucket.applyRealtimeEvent(
      eventType: 'insert',
      newRecord: {
        'id': 5,
        'text': 'Skydive',
        'done': false,
        'created_at': '2026-09-23T10:00:00.000Z',
        'updated_at': '2026-09-23T10:00:00.000Z',
        'category': 'Avventura',
      },
      oldRecord: const {},
    );

    await CacheService.clearAll();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(await CacheService.getCheckpoint(CacheService.kBucketItems), isNull);
  });
}
