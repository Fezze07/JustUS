import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/settle_helpers.dart';

/// Regression tests for 4.4 / F-SC7: incremental drive sync must detect
/// server-side deletions via a row-count comparison, falling back to a full
/// refetch whose merge drops the stale local rows.
class _FakeDriveRepository extends DriveRepository {
  int serverCount = 0;
  int probeCalls = 0;
  int fullFetchCalls = 0;
  int incrementalFetchCalls = 0;
  String maxUpdatedAt = '2026-01-31T00:00:00.000Z';
  List<DriveItem> fullSnapshot = [];
  List<DriveItem> incrementalResult = [];

  @override
  Future<ResultWrapper<DriveChangeProbe>> fetchChangeProbe() async {
    probeCalls += 1;
    return Success(DriveChangeProbe(
      maxUpdatedAt: maxUpdatedAt,
      itemCount: serverCount,
    ));
  }

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItems() async {
    fullFetchCalls += 1;
    return Success(fullSnapshot);
  }

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItemsIncremental() async {
    incrementalFetchCalls += 1;
    return Success(incrementalResult);
  }

  @override
  Future<ResultWrapper<void>> toggleFavorite(
      int driveItemId, bool isFavorite) async {
    return const Success<void>(null);
  }

  @override
  Future<ResultWrapper<void>> addReaction(int driveItemId, String emoji) async {
    return const Success<void>(null);
  }

  ResultWrapper<void> deleteResult = const Success<void>(null);
  final List<int> deletedIds = [];

  @override
  Future<ResultWrapper<void>> deleteDriveItem(int id) async {
    deletedIds.add(id);
    return deleteResult;
  }
}

DriveItem _item(int id, String name, String updatedAt,
    {List<String> reactions = const []}) {
  return DriveItem.fromJson({
    'id': id,
    'name': name,
    'type': 'image',
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': updatedAt,
    'is_favorite': 0,
    'reactions': reactions,
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
      'F-SC7: a server-side deletion is detected on refresh and the stale '
      'local row is dropped by a full refetch', () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 1
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..fullSnapshot = [_item(1, 'kept.png', '2026-02-01T00:00:00.000Z')]
      ..incrementalResult = [];
    await StorageService.saveDriveItems([
      _item(1, 'kept.png', '2026-01-31T00:00:00.000Z'),
      _item(2, 'deleted-by-partner.png', '2026-01-31T00:00:00.000Z'),
    ]);
    // The cursor is up to date, so only the row count can reveal the deletion.
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-01-31T00:00:00.000Z');

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await settleMicrotasks();

    // The count mismatch triggered a full refetch inside the initial load,
    // whose wholesale replace dropped the locally-deleted row.
    expect(state.driveItems.map((i) => i.id), [1]);
    expect(repo.fullFetchCalls, 1);
    expect(repo.incrementalFetchCalls, 0);
    final persisted = await StorageService.getDriveItems();
    expect(persisted.map((i) => i.id), [1]);
    // The revalidation gate and the deletion check share ONE probe.
    expect(repo.probeCalls, 1);

    state.clear();
  });

  test(
      'F-SC7: matching row counts keep the incremental cursor path '
      '(no full refetch)', () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 2
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..incrementalResult = [
        _item(2, 'updated.png', '2026-02-02T00:00:00.000Z')
      ]
      ..fullSnapshot = [];
    await StorageService.saveDriveItems([
      _item(1, 'one.png', '2026-01-01T00:00:00.000Z'),
      _item(2, 'two.png', '2026-01-01T00:00:00.000Z'),
    ]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-01-31T00:00:00.000Z');

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await state.syncDriveItems();

    expect(state.driveItems.map((i) => i.id).toSet(), {1, 2});
    expect(
      state.driveItems.firstWhere((i) => i.id == 2).content,
      'updated.png',
    );
    expect(repo.incrementalFetchCalls, 1);
    expect(repo.fullFetchCalls, 0);
    // initialLoad + syncDriveItems share the memoized probe: one round trip.
    expect(repo.probeCalls, 1);

    state.clear();
  });

  test(
      're-entering the drive tab within the probe TTL does not re-probe, and a '
      'local mutation invalidates the probe at once', () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 2
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..incrementalResult = []
      ..fullSnapshot = [];
    await StorageService.saveDriveItems([
      _item(1, 'one.png', '2026-01-31T00:00:00.000Z'),
      _item(2, 'two.png', '2026-01-31T00:00:00.000Z'),
    ]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-01-31T00:00:00.000Z');

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await state.initialLoad();
    expect(repo.probeCalls, 1, reason: 'the second visit is throttled');

    // An optimistic local write makes the memoized probe stale immediately.
    await state.toggleFavorite(1);
    await state.initialLoad();
    expect(repo.probeCalls, 2);

    state.clear();
  });

  test('a successful delete returns true and raises the confirmation message',
      () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 1
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..fullSnapshot = [_item(1, 'a.png', '2026-01-01T00:00:00.000Z')]
      ..incrementalResult = [];
    await StorageService.saveDriveItems([
      _item(1, 'a.png', '2026-01-01T00:00:00.000Z'),
    ]);

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await settleMicrotasks();

    final deleted = await state.deleteItem(1);

    expect(deleted, isTrue);
    expect(repo.deletedIds, [1]);
    expect(state.driveItems, isEmpty);
    expect(state.message, LanguageHelper.appLoc.drive_deleted);

    state.clear();
  });

  test('a failed delete rolls the item back and returns false', () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 1
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..fullSnapshot = [_item(1, 'a.png', '2026-01-01T00:00:00.000Z')]
      ..incrementalResult = []
      ..deleteResult = const GenericError<void>(message: 'nope', code: 500);
    await StorageService.saveDriveItems([
      _item(1, 'a.png', '2026-01-01T00:00:00.000Z'),
    ]);

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await settleMicrotasks();

    final deleted = await state.deleteItem(1);

    expect(deleted, isFalse);
    expect(state.driveItems.map((i) => i.id), [1],
        reason: 'the optimistic removal must be rolled back on failure');

    state.clear();
  });

  test('the open detail item follows the grid through sync and vanishes with it',
      () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 1
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..incrementalResult = [
        _item(1, 'a.png', '2026-02-02T00:00:00.000Z', reactions: ['❤️'])
      ];
    await StorageService.saveDriveItems([
      _item(1, 'a.png', '2026-01-31T00:00:00.000Z'),
    ]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-01-31T00:00:00.000Z');

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await settleMicrotasks();
    state.loadSingleItem(1);
    expect(state.singleItem?.reactions, isEmpty);

    // A partner reaction arrives through the incremental merge.
    await state.syncDriveItems();

    expect(state.singleItem, same(state.driveItems.single),
        reason: 'the detail item must be derived from the grid list, not a copy');
    expect(state.singleItem?.reactions, ['❤️']);

    // A partner delete arrives through the full realtime refresh.
    repo
      ..serverCount = 0
      ..fullSnapshot = [];
    await state.refreshFromRealtime();

    expect(state.driveItems, isEmpty);
    expect(state.singleItem, isNull,
        reason: 'a vanished row must clear the detail view');

    state.clear();
  });

  test('adding a reaction confirms it and shows on the item', () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 1
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..fullSnapshot = [_item(1, 'a.png', '2026-01-01T00:00:00.000Z')]
      ..incrementalResult = [];
    await StorageService.saveDriveItems([
      _item(1, 'a.png', '2026-01-01T00:00:00.000Z'),
    ]);

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await settleMicrotasks();

    await state.addReaction(1, '❤️');

    expect(state.message, LanguageHelper.appLoc.drive_reactionAdded);
    expect(state.driveItems.first.reactions, ['❤️']);

    state.clear();
  });

  test('toggling favorite confirms added, then removed', () async {
    final repo = _FakeDriveRepository()
      ..serverCount = 1
      ..maxUpdatedAt = '2026-01-31T00:00:00.000Z'
      ..fullSnapshot = [_item(1, 'a.png', '2026-01-01T00:00:00.000Z')]
      ..incrementalResult = [];
    await StorageService.saveDriveItems([
      _item(1, 'a.png', '2026-01-01T00:00:00.000Z'),
    ]);

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await settleMicrotasks();

    await state.toggleFavorite(1);
    expect(state.message, LanguageHelper.appLoc.drive_favoriteAdded);
    expect(state.favoriteItems.map((i) => i.id), [1]);

    await state.toggleFavorite(1);
    expect(state.message, LanguageHelper.appLoc.drive_favoriteRemoved);
    expect(state.favoriteItems, isEmpty);

    state.clear();
  });
}
