import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/settle_helpers.dart';

class _PagedDriveRepository extends DriveRepository {
  _PagedDriveRepository({
    required this.items,
    this.favoriteItems = const [],
    this.serverCount = 0,
  });

  final List<DriveItem> items;
  final List<DriveItem> favoriteItems;
  final int serverCount;
  final List<(int, int)> ranges = [];
  int fullFetchCalls = 0;
  int favoriteFetchCalls = 0;

  @override
  Future<ResultWrapper<DriveChangeProbe>> fetchChangeProbe() async =>
      Success(DriveChangeProbe(
        maxUpdatedAt: '2026-01-31T00:00:00.000Z',
        itemCount: serverCount,
      ));

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItems({
    int limit = DriveRepository.drivePageSize,
    int offset = 0,
  }) async {
    fullFetchCalls += 1;
    ranges.add((offset, limit));

    return Success(items.skip(offset).take(limit).toList());
  }

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItemsIncremental({
    int limit = DriveRepository.drivePageSize,
    int offset = 0,
  }) async =>
      const Success<List<DriveItem>>([]);

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchFavoriteDriveItems({
    int limit = DriveRepository.drivePageSize,
    int offset = 0,
  }) async {
    favoriteFetchCalls += 1;

    return Success(favoriteItems.skip(offset).take(limit).toList());
  }
}

DriveItem _item(int id, {int isFavorite = 0}) {
  return DriveItem(
    id: id,
    type: 'image',
    content: 'uploads/$id/original.jpg',
    createdAt: DateTime.utc(2026).add(Duration(minutes: id)).toIso8601String(),
    updatedAt: '2026-01-31T00:00:00.000Z',
    isFavorite: isFavorite,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('the first page is bounded and loadMore appends until a short page',
      () async {
    final items = [for (var id = 45; id >= 1; id--) _item(id)];
    final repo = _PagedDriveRepository(
      items: items,
      serverCount: items.length,
    );

    final state = DriveState(repository: repo);
    await state.initialLoad();
    await settleMicrotasks();

    expect(state.driveItems, hasLength(DriveRepository.drivePageSize));
    expect(state.hasMore, isTrue);
    expect(repo.fullFetchCalls, 1);
    expect(repo.ranges, [(0, DriveRepository.drivePageSize)]);

    await state.initialLoad();
    await settleMicrotasks();

    expect(repo.fullFetchCalls, 1,
        reason: 'a server total above the loaded page is not a deletion');

    await state.loadMore();

    expect(state.driveItems, hasLength(45));
    expect(state.hasMore, isFalse);
    expect(repo.ranges, [
      (0, DriveRepository.drivePageSize),
      (DriveRepository.drivePageSize, DriveRepository.drivePageSize),
    ]);

    state.clear();
  });

  test('favorites page independently and stay selectable from their list',
      () async {
    final favorites = [
      for (var id = 35; id >= 1; id--) _item(id, isFavorite: 1),
    ];
    final repo = _PagedDriveRepository(
      items: const [],
      favoriteItems: favorites,
    );

    final state = DriveState(repository: repo);
    await state.loadFavorites();

    expect(state.favoriteItems, hasLength(DriveRepository.drivePageSize));
    expect(state.hasMoreFavorites, isTrue);
    expect(state.driveItems, isEmpty);

    await state.loadMoreFavorites();

    expect(state.favoriteItems, hasLength(35));
    expect(state.hasMoreFavorites, isFalse);
    expect(repo.favoriteFetchCalls, 2);

    state.loadSingleItem(favorites.last.id);
    expect(state.singleItem?.id, favorites.last.id);

    state.clear();
  });
}
