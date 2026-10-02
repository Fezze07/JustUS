import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/settle_helpers.dart';

/// Regression test for 4.x / F-SC12: after an optimistic mutation overlaps a
/// full refresh, the persisted cache must equal the final in-memory list.
///
/// SCOPE NOTE: this test does NOT prove the ordering of concurrent cache writes.
/// Every `_persistDriveCache()` caller awaits its own enqueued future, so the
/// two writes here are never in flight simultaneously and removing the
/// serialization (CacheWriteQueue) leaves this file green — confirmed by
/// mutation. The queue's own ordering contract is pinned directly in
/// `cache_write_queue_test.dart`; what is verified here is that the
/// refresh/mutation interleave converges on a consistent cache.
class _GatedSerialDriveRepository extends DriveRepository {
  _GatedSerialDriveRepository({
    required this.gate,
    required this.serverSnapshot,
  });

  final Completer<void> gate;
  final List<DriveItem> serverSnapshot;

  @override
  Future<ResultWrapper<DriveChangeProbe>> fetchChangeProbe() async =>
      const Success(DriveChangeProbe(
        maxUpdatedAt: '2026-02-01T00:00:00.000Z',
        itemCount: 1,
      ));

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItems() async {
    await gate.future;
    return Success(serverSnapshot);
  }

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItemsIncremental() async =>
      const Success<List<DriveItem>>([]);

  @override
  Future<ResultWrapper<void>> addReaction(
      int driveItemId, String emojiChar) async {
    return const Success<void>(null);
  }
}

DriveItem _item(int id, String name) {
  return DriveItem.fromJson({
    'id': id,
    'name': name,
    'type': 'image',
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-02-0${id}T00:00:00.000Z',
    'is_favorite': 0,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test(
      'F-SC12: after a refresh overlaps an optimistic mutation the cache ends '
      'up exactly equal to the final in-memory list', () async {
    final gate = Completer<void>();
    final itemA = _item(1, 'a.png');
    final itemB = _item(2, 'b.png');
    final repo = _GatedSerialDriveRepository(
      gate: gate,
      serverSnapshot: [itemA, itemB],
    );

    await StorageService.saveDriveItems([itemA]);
    // The cached single item is up to date: initialLoad must not refetch, the
    // scenario under test starts from a full refresh.
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-02-01T00:00:00.000Z');
    final state = DriveState(repository: repo);
    await state.initialLoad();

    // A full refresh starts and is suspended before the server snapshot is
    // returned (it predates the optimistic reaction below).
    final refreshFuture = state.refreshFromRealtime();

    // Optimistic mutation: item A gains a reaction and the cache is written.
    await state.addReaction(itemA.id, '❤️');

    // The refresh completes afterwards, replacing _driveItems with [A, B] and
    // writing the NEWER snapshot.
    gate.complete();
    await refreshFuture;
    await settleMicrotasks();

    expect(state.driveItems.map((i) => i.id), [1, 2]);

    // The cache must exactly equal the final in-memory list.
    final persisted = await StorageService.getDriveItems();
    expect(
      persisted.map((i) => i.toJson()),
      state.driveItems.map((i) => i.toJson()),
    );
    // The server snapshot is authoritative and carries no reaction, so the
    // server value wins — proving the cache was not left holding the stale
    // pre-refresh optimistic state.
    expect(
      persisted.firstWhere((i) => i.id == itemA.id).reactions,
      isEmpty,
    );

    state.clear();
  });
}
