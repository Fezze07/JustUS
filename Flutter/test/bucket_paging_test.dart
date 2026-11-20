import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/settle_helpers.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _MockFrom extends Mock implements sb.SupabaseQueryBuilder {}

class _MockFilter extends Mock
    implements sb.PostgrestFilterBuilder<sb.PostgrestList> {
  _MockFilter(this.rows);

  final sb.PostgrestList Function() rows;

  @override
  Future<R> then<R>(
    Function(sb.PostgrestList value) onValue, {
    Function? onError,
  }) async {
    try {
      return await onValue(rows()) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

class _TestableBucketRepository extends BucketRepository {
  _TestableBucketRepository({
    super.sbClient,
    this.mockPartnershipId = 42,
  });

  final int? mockPartnershipId;

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async {
    if (mockPartnershipId == null) return null;
    return {'partnership_id': mockPartnershipId};
  }
}

class _FakePagedBucketRepository extends BucketRepository {
  _FakePagedBucketRepository({required this.allItems});

  final List<BucketItem> allItems;
  final List<(int offset, int limit)> recordedCalls = [];
  Completer<void>? pendingGate;

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async =>
      {'partnership_id': 42};

  @override
  Future<bool> hasNewBucketItems(int partnershipId) async => true;

  @override
  Future<ResultWrapper<List<BucketItem>>> fetchBucketList({
    int limit = BucketRepository.bucketPageSize,
    int offset = 0,
  }) async {
    recordedCalls.add((offset, limit));
    if (pendingGate != null) {
      await pendingGate!.future;
    }
    if (offset >= allItems.length) {
      return const Success([]);
    }
    final end = (offset + limit < allItems.length) ? offset + limit : allItems.length;
    return Success(allItems.sublist(offset, end));
  }
}

BucketItem _makeItem(int id, {String category = 'Travel', bool done = false}) {
  return BucketItem(
    id: id,
    text: 'Bucket item $id',
    done: done,
    createdAt: '2026-05-${id.toString().padLeft(2, '0')}T00:00:00.000Z',
    updatedAt: '2026-05-${id.toString().padLeft(2, '0')}T00:00:00.000Z',
    category: category,
    partnershipId: 42,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  group('BucketRepository paging & bounding', () {
    test('fetchBucketList requests bounded page 0 ordered by created_at desc',
        () async {
      final client = _MockClient();
      final from = _MockFrom();
      final filter = _MockFilter(() => [
            {
              'id': 1,
              'text': 'Skydiving',
              'done': false,
              'created_at': '2026-05-01T00:00:00.000Z',
              'updated_at': '2026-05-01T00:00:00.000Z',
              'category': 'Adventure',
              'partnership_id': 42,
            }
          ]);

      when(() => client.from('bucket_items')).thenAnswer((_) => from);
      when(() => from.select(any())).thenAnswer((_) => filter);
      when(() => filter.eq(any(), any())).thenAnswer((_) => filter);
      when(() => filter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => filter);
      when(() => filter.range(any(), any())).thenAnswer((_) => filter);

      final repo = _TestableBucketRepository(
        sbClient: client,
      );
      final result = await repo.fetchBucketList();

      expect(result.valueOrNull, hasLength(1));
      verify(() => filter.eq('partnership_id', 42)).called(1);
      verify(() => filter.order('created_at', ascending: false)).called(1);
      verify(() => filter.range(0, BucketRepository.bucketPageSize - 1)).called(1);
    });

    test('fetchBucketList applies custom offset and limit to range', () async {
      final client = _MockClient();
      final from = _MockFrom();
      final filter = _MockFilter(() => []);

      when(() => client.from('bucket_items')).thenAnswer((_) => from);
      when(() => from.select(any())).thenAnswer((_) => filter);
      when(() => filter.eq(any(), any())).thenAnswer((_) => filter);
      when(() => filter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => filter);
      when(() => filter.range(any(), any())).thenAnswer((_) => filter);

      final repo = _TestableBucketRepository(
        sbClient: client,
      );
      await repo.fetchBucketList(limit: 20, offset: 40);

      verify(() => filter.range(40, 59)).called(1);
    });

    test('fetchBucketList returns empty list when no active partnership',
        () async {
      final repo = _TestableBucketRepository(mockPartnershipId: null);
      final result = await repo.fetchBucketList();

      expect(result.valueOrNull, isEmpty);
    });
  });

  group('BucketState pagination & loadMore', () {
    test('initial load with a full page sets hasMore true and persists to cache',
        () async {
      final items = List.generate(50, (i) => _makeItem(i + 1));
      final repo = _FakePagedBucketRepository(allItems: items);
      final state = BucketState(repository: repo);

      await state.fetchBucket(epoch: 1);

      expect(state.items, hasLength(50));
      expect(state.hasMore, isTrue);
      expect(state.offset, 50);
      expect(repo.recordedCalls, [(0, 50)]);

      final cached = await StorageService.getBucketList();
      expect(cached, hasLength(50));

      state.clear();
    });

    test('initial load with a short page sets hasMore false', () async {
      final items = List.generate(20, (i) => _makeItem(i + 1));
      final repo = _FakePagedBucketRepository(allItems: items);
      final state = BucketState(repository: repo);

      await state.fetchBucket(epoch: 1);

      expect(state.items, hasLength(20));
      expect(state.hasMore, isFalse);
      expect(state.offset, 20);

      state.clear();
    });

    test('loadMore appends the next page, updates hasMore, and ends on short page',
        () async {
      // 75 items: page 1 = 50 items, page 2 = 25 items (short page)
      final items = List.generate(75, (i) => _makeItem(i + 1));
      final repo = _FakePagedBucketRepository(allItems: items);
      final state = BucketState(repository: repo);

      await state.fetchBucket(epoch: 1);
      expect(state.items, hasLength(50));
      expect(state.hasMore, isTrue);

      await state.loadMore();

      expect(state.items, hasLength(75));
      expect(state.hasMore, isFalse);
      expect(state.offset, 75);
      expect(repo.recordedCalls, [(0, 50), (50, 50)]);

      final cached = await StorageService.getBucketList();
      expect(cached, hasLength(75));

      state.clear();
    });

    test('loadMore guards against concurrent re-entrant invocations', () async {
      final items = List.generate(100, (i) => _makeItem(i + 1));
      final repo = _FakePagedBucketRepository(allItems: items);
      final state = BucketState(repository: repo);

      await state.fetchBucket(epoch: 1);
      expect(repo.recordedCalls.length, 1);

      repo.pendingGate = Completer<void>();
      final future1 = state.loadMore();
      expect(state.isLoadingMore, isTrue);

      // Concurrent call while loading more
      final future2 = state.loadMore();

      repo.pendingGate!.complete();
      await Future.wait([future1, future2]);

      expect(state.isLoadingMore, isFalse);
      // Only one additional page call was dispatched
      expect(repo.recordedCalls.length, 2);

      state.clear();
    });

    test('cold start loads from cache, sets hasMore, and continues pagination',
        () async {
      final initial50 = List.generate(50, (i) => _makeItem(i + 1));
      await StorageService.saveBucketList(initial50);

      final total80 = List.generate(80, (i) => _makeItem(i + 1));
      final repo = _FakePagedBucketRepository(allItems: total80);
      final state = BucketState(repository: repo);

      await state.init();
      await settleMicrotasks();

      expect(state.items, hasLength(50));
      expect(state.hasMore, isTrue);
      expect(state.offset, 50);

      // loadMore continues from the loaded cache length (offset 50)
      await state.loadMore();

      expect(state.items, hasLength(80));
      expect(state.hasMore, isFalse);
      expect(state.offset, 80);
      expect(repo.recordedCalls.last, (50, 50));

      state.clear();
    });
  });

  group('Realtime mutations while paged', () {
    test('realtime insert prepends and updates offset without breaking loadMore deduplication',
        () async {
      final items = List.generate(50, (i) => _makeItem(i + 1));
      final repo = _FakePagedBucketRepository(allItems: items);
      final state = BucketState(repository: repo);

      await state.fetchBucket(epoch: 1);
      expect(state.items, hasLength(50));
      expect(state.offset, 50);

      // Partner inserts item 999
      await state.applyRealtimeEvent(
        eventType: 'insert',
        newRecord: {
          'id': 999,
          'text': 'New dream',
          'done': false,
          'created_at': '2026-06-01T00:00:00.000Z',
          'updated_at': '2026-06-01T00:00:00.000Z',
          'category': 'Travel',
          'partnership_id': 42,
        },
        oldRecord: const {},
      );

      expect(state.items, hasLength(51));
      expect(state.items.first.id, 999);
      expect(state.offset, 51);

      // loadMore uses offset 51 and dedupes
      await state.loadMore();
      expect(state.items.any((i) => i.id == 999), isTrue);

      state.clear();
    });

    test('realtime delete removes item and updates offset', () async {
      final items = List.generate(50, (i) => _makeItem(i + 1));
      final repo = _FakePagedBucketRepository(allItems: items);
      final state = BucketState(repository: repo);

      await state.fetchBucket(epoch: 1);
      expect(state.items, hasLength(50));
      expect(state.offset, 50);

      // Partner deletes item 1
      await state.applyRealtimeEvent(
        eventType: 'delete',
        newRecord: const {},
        oldRecord: {'id': 1},
      );

      expect(state.items, hasLength(49));
      expect(state.items.any((i) => i.id == 1), isFalse);
      expect(state.offset, 49);

      state.clear();
    });
  });
}
