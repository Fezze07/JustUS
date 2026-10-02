import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/realtime_payload_factory.dart';

class _MockMoodState extends Mock implements MoodState {}

void main() {
  group('MoodRealtimeHandler (distinct-user coalescing, F-RT2)', () {
    late RealtimeSyncSession session;
    late _MockMoodState mood;
    late MoodRealtimeHandler handler;

    setUp(() {
      session = RealtimeSyncSession()
        ..userId = 42
        ..partnerId = 77;
      mood = _MockMoodState();
      when(() => mood.refreshFromRealtime(
          changedUserId: any(named: 'changedUserId'))).thenAnswer((_) async {});
      handler = MoodRealtimeHandler(session: session, moodState: mood);
    });

    test('burst for both distinct users refreshes both (nothing skipped)', () {
      fakeAsync((async) {
        handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 1, 'user_id': 42},
          commitTimestamp: DateTime.utc(2026),
        ));
        async.elapse(const Duration(milliseconds: 50));
        handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 2, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026, 1, 2),
        ));

        async.elapse(const Duration(milliseconds: 120));
        async.flushMicrotasks();

        verify(() => mood.refreshFromRealtime(changedUserId: 42)).called(1);
        verify(() => mood.refreshFromRealtime(changedUserId: 77)).called(1);
      });
    });

    test('repeated events for the same user are coalesced to one refresh', () {
      fakeAsync((async) {
        handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 1, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026),
        ));
        async.elapse(const Duration(milliseconds: 10));
        handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 2, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026, 1, 2),
        ));

        async.elapse(const Duration(milliseconds: 120));
        async.flushMicrotasks();

        verify(() => mood.refreshFromRealtime(changedUserId: 77)).called(1);
        verifyNever(() => mood.refreshFromRealtime(changedUserId: 42));
      });
    });

    test('null changedUserId is ignored (no refresh scheduled)', () {
      fakeAsync((async) {
        handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 9, 'user_id': null},
          commitTimestamp: DateTime.utc(2026, 1, 3),
        ));

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        verifyNever(() => mood.refreshFromRealtime(
            changedUserId: any(named: 'changedUserId')));
      });
    });

    test(
        'a null user_id is dropped by the handler itself, not only by the '
        'relevance filter', () {
      // `handle()` returns before `onNewEvent` when `isRelevantMood` rejects
      // the payload, so the `changedUserId == null` guard inside
      // `MoodRealtimeHandler.onNewEvent` is only reachable by calling
      // `onNewEvent` directly. Exercised here so the guard cannot silently rot.
      fakeAsync((async) {
        handler.onNewEvent(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: const {'id': 12},
          commitTimestamp: DateTime.utc(2026, 1, 6),
        ));

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        verifyNever(() => mood.refreshFromRealtime(
            changedUserId: any(named: 'changedUserId')));
      });
    });

    test('onNewEvent forwards a decoded user_id straight into the batch', () {
      fakeAsync((async) {
        handler.onNewEvent(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 13, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026, 1, 7),
        ));

        async.elapse(const Duration(milliseconds: 120));
        async.flushMicrotasks();

        verify(() => mood.refreshFromRealtime(changedUserId: 77)).called(1);
        verifyNever(() => mood.refreshFromRealtime(
            changedUserId: any(named: 'changedUserId')));
      });
    });

    test('foreign-user events are dropped by the relevance filter', () {
      fakeAsync((async) {
        handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 10, 'user_id': 999},
          commitTimestamp: DateTime.utc(2026, 1, 4),
        ));

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        verifyNever(() => mood.refreshFromRealtime(
            changedUserId: any(named: 'changedUserId')));
      });
    });

    test('clear() cancels a pending coalesced refresh', () {
      fakeAsync((async) {
        handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 11, 'user_id': 42},
          commitTimestamp: DateTime.utc(2026, 1, 5),
        ));
        handler.clear();

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        verifyNever(() => mood.refreshFromRealtime(
            changedUserId: any(named: 'changedUserId')));
      });
    });
  });
}
