import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/realtime_payload_factory.dart';

class _MockHomepageState extends Mock implements HomepageState {}

/// Returns a fixed server total and counts the calls, so "delete refetches"
/// and "insert never refetches" are both observable.
class _FakeMissYouRepository extends MissYouRepository {
  _FakeMissYouRepository({this.serverTotal = 0});

  final int serverTotal;
  int fetchMissYouTotalCalls = 0;

  @override
  Future<ResultWrapper<MissYouResponse>> fetchMissYouTotal() async {
    fetchMissYouTotalCalls++;
    return Success(MissYouResponse(success: true, total: serverTotal));
  }
}

Map<String, dynamic> _row(int id, {int? partnershipId = 9001}) => {
      'id': id,
      'partnership_id': partnershipId,
      'user_id': 77,
      'created_at': '2026-05-01T00:00:00.000Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  group('MissYouRealtimeHandler (immediate, no debounce)', () {
    late RealtimeSyncSession session;
    late _MockHomepageState home;
    late MissYouRealtimeHandler handler;

    setUp(() {
      session = RealtimeSyncSession()
        ..userId = 42
        ..partnerId = 77
        ..partnershipId = 9001;
      home = _MockHomepageState();
      when(() => home.refreshFromRealtime()).thenAnswer((_) async {});
      when(() => home.addMissYou(rowId: any(named: 'rowId')))
          .thenReturn(null);
      handler = MissYouRealtimeHandler(session: session, homepageState: home);
    });

    test('an insert bumps the counter with the decoded row id', () {
      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(7),
        commitTimestamp: DateTime.utc(2026),
      ));

      verify(() => home.addMissYou(rowId: 7)).called(1);
      verifyNever(() => home.refreshFromRealtime());
    });

    test('an insert without a row id still bumps (idempotency key absent)',
        () {
      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'partnership_id': 9001},
        commitTimestamp: DateTime.utc(2026),
      ));

      verify(() => home.addMissYou()).called(1);
    });

    test('a delete refetches instead of incrementing', () {
      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.delete,
        oldRecord: _row(7),
        commitTimestamp: DateTime.utc(2026, 1, 2),
      ));

      verify(() => home.refreshFromRealtime()).called(1);
      verifyNever(() => home.addMissYou(rowId: any(named: 'rowId')));
    });

    test('a sparse delete (primary key only) is still refetched', () {
      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.delete,
        oldRecord: {'id': 7},
        commitTimestamp: DateTime.utc(2026, 1, 3),
      ));

      verify(() => home.refreshFromRealtime()).called(1);
    });

    test('an update does neither: the count is server-derived, not event-derived',
        () {
      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.update,
        newRecord: _row(7),
        oldRecord: _row(7),
        commitTimestamp: DateTime.utc(2026, 1, 4),
      ));

      verifyNever(() => home.addMissYou(rowId: any(named: 'rowId')));
      verifyNever(() => home.refreshFromRealtime());
    });

    test("another partnership's row is dropped by the relevance filter", () {
      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(7, partnershipId: 4),
        commitTimestamp: DateTime.utc(2026, 1, 5),
      ));

      verifyNever(() => home.addMissYou(rowId: any(named: 'rowId')));
      verifyNever(() => home.refreshFromRealtime());
    });

    test('a replayed insert is dropped, so the counter moves once', () {
      final payload = realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(7),
        commitTimestamp: DateTime.utc(2026, 1, 6),
      );

      handler.handle(payload);
      handler.handle(payload);

      verify(() => home.addMissYou(rowId: 7)).called(1);
    });
  });

  group('MissYouRealtimeHandler into a real HomepageState', () {
    late _FakeMissYouRepository repository;
    late HomepageState state;
    late MissYouRealtimeHandler handler;

    setUp(() {
      repository = _FakeMissYouRepository(serverTotal: 5);
      state = HomepageState(repository: repository);
      final session = RealtimeSyncSession()
        ..userId = 42
        ..partnerId = 77
        ..partnershipId = 9001;
      handler = MissYouRealtimeHandler(session: session, homepageState: state);
    });

    tearDown(() => state.clear());

    test('an insert counts once and is persisted without a refetch', () async {
      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(7),
        commitTimestamp: DateTime.utc(2026),
      ));
      await pumpEventQueue();

      expect(state.totalMissYou, 1);
      expect(await StorageService.getTotalMissYou(), 1);
      expect(repository.fetchMissYouTotalCalls, 0,
          reason: 'the optimistic path must not also refetch');
    });

    test('a replayed insert does not double count (F-RT5 end to end)', () async {
      final payload = realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: _row(7),
        commitTimestamp: DateTime.utc(2026),
      );

      handler.handle(payload);
      await pumpEventQueue();
      handler.handle(payload);
      await pumpEventQueue();

      expect(state.totalMissYou, 1,
          reason: 'supabase may replay a commit after a resubscribe');
    });

    test('a delete replaces the counter with the server total', () async {
      await state.fetchTotalMissYou();
      expect(state.totalMissYou, 5, reason: 'precondition');
      final callsBefore = repository.fetchMissYouTotalCalls;

      handler.handle(realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.delete,
        oldRecord: _row(9),
        commitTimestamp: DateTime.utc(2026),
      ));
      await pumpEventQueue();

      expect(repository.fetchMissYouTotalCalls, callsBefore + 1);
      expect(state.totalMissYou, 5,
          reason: 'a delete is a full refetch, never a decrement');
    });
  });
}