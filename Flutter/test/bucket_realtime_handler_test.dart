import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/realtime_payload_factory.dart';

/// Records the exact arguments the handler forwards, so the routing contract
/// (event type name + which record each event type reads) is pinned.
class _MockBucketState extends Mock implements BucketState {}

/// Real repository with no network: `bucket_items` is only ever read through
/// these three calls, and the count proves the handler never falls back to a
/// full refetch.
class _FakeBucketRepository extends BucketRepository {
  _FakeBucketRepository({required this.partnershipId});

  final int? partnershipId;
  int fetchBucketListCalls = 0;

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async {
    final id = partnershipId;
    return id == null ? null : {'partnership_id': id};
  }

  @override
  Future<ResultWrapper<List<BucketItem>>> fetchBucketList() async {
    fetchBucketListCalls++;
    return const Success<List<BucketItem>>([]);
  }
}

Map<String, dynamic> _row(int id, {int? partnershipId = 9001, bool done = false}) =>
    {
      'id': id,
      'text': 'bucket row $id',
      'done': done,
      'created_at': '2026-05-01T00:00:00.000Z',
      'updated_at': '2026-05-02T00:00:00.000Z',
      'category': 'Personal',
      'partnership_id': partnershipId,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  group('BucketRealtimeHandler (immediate granular apply, no debounce)',
      () {
    late RealtimeSyncSession session;
    late _MockBucketState bucket;
    late BucketRealtimeHandler handler;

    setUp(() {
      session = RealtimeSyncSession()
        ..userId = 42
        ..partnerId = 77
        ..partnershipId = 9001;
      bucket = _MockBucketState();
      when(() => bucket.applyRealtimeEvent(
            eventType: any(named: 'eventType'),
            newRecord: any(named: 'newRecord'),
            oldRecord: any(named: 'oldRecord'),
          )).thenAnswer((_) async {});
      handler = BucketRealtimeHandler(session: session, bucketState: bucket);
    });

    test('an insert is forwarded immediately, with the new record', () {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(1),
        commitTimestamp: DateTime.utc(2026),
      ));

      // No timer elapses: the immediate strategy must not be debounced.
      verify(() => bucket.applyRealtimeEvent(
            eventType: 'insert',
            newRecord: any(named: 'newRecord'),
            oldRecord: const {},
          )).called(1);
    });

    test('an update forwards the post-update record, not the old one', () {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.update,
        newRecord: _row(1, done: true),
        oldRecord: _row(1),
        commitTimestamp: DateTime.utc(2026, 1, 2),
      ));

      final captured = verify(() => bucket.applyRealtimeEvent(
            eventType: 'update',
            newRecord: captureAny(named: 'newRecord'),
            oldRecord: any(named: 'oldRecord'),
          )).captured;
      expect((captured[0] as Map<String, dynamic>)['done'], isTrue,
          reason: 'the toggle must be applied from the post-update row');
    });

    test('a delete is forwarded immediately, with the old record', () {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.delete,
        oldRecord: {'id': 1},
        commitTimestamp: DateTime.utc(2026, 1, 3),
      ));

      final captured = verify(() => bucket.applyRealtimeEvent(
            eventType: 'delete',
            newRecord: any(named: 'newRecord'),
            oldRecord: captureAny(named: 'oldRecord'),
          )).captured;
      expect((captured[0] as Map<String, dynamic>)['id'], 1,
          reason: 'a delete carries the row only in oldRecord');
    });

    test("another partnership's row is dropped by the relevance filter", () {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(1, partnershipId: 4),
        commitTimestamp: DateTime.utc(2026, 1, 4),
      ));

      verifyNever(() => bucket.applyRealtimeEvent(
            eventType: any(named: 'eventType'),
            newRecord: any(named: 'newRecord'),
            oldRecord: any(named: 'oldRecord'),
          ));
    });

    test('a sparse delete (primary key only) is still applied', () {
      // Supabase sends only the PK in oldRecord on delete, so the payload
      // carries no partnership_id at all. `isPartnershipRecord` keeps deletes
      // for exactly this case instead of dropping them.
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.delete,
        oldRecord: {'id': 9},
        commitTimestamp: DateTime.utc(2026, 1, 5),
      ));

      verify(() => bucket.applyRealtimeEvent(
            eventType: 'delete',
            newRecord: any(named: 'newRecord'),
            oldRecord: any(named: 'oldRecord'),
          )).called(1);
    });

    test('a replayed payload is dropped before the state is touched', () {
      final payload = realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(2),
        commitTimestamp: DateTime.utc(2026, 1, 6),
      );

      handler.handle(payload);
      handler.handle(payload);

      verify(() => bucket.applyRealtimeEvent(
            eventType: any(named: 'eventType'),
            newRecord: any(named: 'newRecord'),
            oldRecord: any(named: 'oldRecord'),
          )).called(1);
    });
  });

  group('BucketRealtimeHandler into a real BucketState', () {
    late _FakeBucketRepository repository;
    late BucketState state;
    late BucketRealtimeHandler handler;

    setUp(() {
      repository = _FakeBucketRepository(partnershipId: 9001);
      state = BucketState(repository: repository);
      final session = RealtimeSyncSession()
        ..userId = 42
        ..partnerId = 77
        ..partnershipId = 9001;
      handler = BucketRealtimeHandler(session: session, bucketState: state);
    });

    tearDown(() => state.clear());

    test('an insert lands in the list without any full refetch', () async {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(1),
        commitTimestamp: DateTime.utc(2026),
      ));
      await pumpEventQueue();

      expect(state.items.map((i) => i.id), [1]);
      expect(repository.fetchBucketListCalls, 0,
          reason: 'the granular strategy must not refetch the whole list');
    });

    test('an update toggles an already-known row in place', () async {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(1),
        commitTimestamp: DateTime.utc(2026),
      ));
      await pumpEventQueue();

      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.update,
        newRecord: _row(1, done: true),
        oldRecord: _row(1),
        commitTimestamp: DateTime.utc(2026, 1, 2),
      ));
      await pumpEventQueue();

      expect(state.items.single.done, isTrue);
      expect(state.items, hasLength(1), reason: 'update must not duplicate');
    });

    test('a delete removes the row', () async {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(1),
        commitTimestamp: DateTime.utc(2026),
      ));
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(2),
        commitTimestamp: DateTime.utc(2026, 1, 2),
      ));
      await pumpEventQueue();

      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.delete,
        oldRecord: {'id': 1},
        commitTimestamp: DateTime.utc(2026, 1, 3),
      ));
      await pumpEventQueue();

      expect(state.items.map((i) => i.id), [2]);
    });

    test('an update for an unknown row is ignored (self-echo of a stale list)',
        () async {
      handler.handle(realtimePayload(
        table: 'bucket_items',
        eventType: sb.PostgresChangeEvent.update,
        newRecord: _row(7, done: true),
        oldRecord: _row(7),
        commitTimestamp: DateTime.utc(2026),
      ));
      await pumpEventQueue();

      expect(state.items, isEmpty);
    });
  });
}