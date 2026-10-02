import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/realtime_payload_factory.dart';

void main() {
  group('RefetchRealtimeHandler (debounced full refetch)', () {
    test('burst inside the debounce produces exactly one refetch', () {
      fakeAsync((async) {
        var refetchCount = 0;
        final handler = RefetchRealtimeHandler(
          session: RealtimeSyncSession(),
          isRelevant: (_) => true,
          refetch: () async {
            refetchCount++;
          },
        );

        // Five distinct events inside 150 ms (spaced 30 ms apart), so the
        // trailing-edge debounce window is never allowed to expire mid-burst.
        for (var i = 0; i < 5; i++) {
          handler.handle(realtimePayload(
              eventType: sb.PostgresChangeEvent.insert,
              commitTimestamp: DateTime.utc(2026, 1, 1 + i)));
          async.elapse(const Duration(milliseconds: 30));
        }

        // Trailing edge: nothing fires until 150 ms after the LAST event (t=270
        // for the 5th event at t=120). At t=269 the count must still be 0.
        async.elapse(const Duration(milliseconds: 119));
        expect(refetchCount, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(refetchCount, 1);
      });
    });

    test('event arriving while a refetch is in flight schedules a follow-up',
        () {
      fakeAsync((async) {
        var refetchCount = 0;
        final inFlight = Completer<void>();
        final handler = RefetchRealtimeHandler(
          session: RealtimeSyncSession(),
          isRelevant: (_) => true,
          refetch: () {
            refetchCount++;
            return inFlight.future;
          },
        );

        handler.handle(realtimePayload(
            eventType: sb.PostgresChangeEvent.insert,
            commitTimestamp: DateTime.utc(2026)));
        async.elapse(const Duration(milliseconds: 150)); // refetch #1 runs
        expect(refetchCount, 1);
        expect(inFlight.isCompleted, isFalse); // still in flight

        // A new event lands while #1 is pending -> another trailing edge.
        handler.handle(realtimePayload(
            eventType: sb.PostgresChangeEvent.insert,
            commitTimestamp: DateTime.utc(2026, 1, 2)));
        async.elapse(const Duration(milliseconds: 150)); // refetch #2 runs
        expect(refetchCount, 2);

        inFlight.complete();
        async.flushMicrotasks();
      });
    });

    test('clear() cancels a pending trailing-edge refetch', () {
      fakeAsync((async) {
        var refetchCount = 0;
        final handler = RefetchRealtimeHandler(
          session: RealtimeSyncSession(),
          isRelevant: (_) => true,
          refetch: () async {
            refetchCount++;
          },
        );

        handler.handle(realtimePayload(
            eventType: sb.PostgresChangeEvent.insert,
            commitTimestamp: DateTime.utc(2026, 1, 3)));
        async.elapse(const Duration(milliseconds: 100));
        handler.clear();

        async.elapse(const Duration(milliseconds: 300));
        expect(refetchCount, 0);
      });
    });

    test('dispose() cancels pending refetch callbacks', () {
      fakeAsync((async) {
        var refetchCount = 0;
        final handler = RefetchRealtimeHandler(
          session: RealtimeSyncSession(),
          isRelevant: (_) => true,
          refetch: () async {
            refetchCount++;
          },
        );

        handler.handle(realtimePayload(
            eventType: sb.PostgresChangeEvent.insert,
            commitTimestamp: DateTime.utc(2026, 1, 4)));
        handler.dispose();

        async.elapse(const Duration(milliseconds: 300));
        expect(refetchCount, 0);
      });
    });

    test(
        'user_profiles update-only relevance path schedules exactly one '
        'refetch', () {
      fakeAsync((async) {
        final session = RealtimeSyncSession()
          ..userId = 42
          ..partnerId = 77;
        var refetchCount = 0;
        final handler = RefetchRealtimeHandler(
          session: session,
          // Mirrors the wire-up in RealtimeSyncService for user_profiles.
          isRelevant: (p) =>
              p.eventType.name == 'update' && session.isRelevantUserProfile(p),
          refetch: () async {
            refetchCount++;
          },
        );

        // Insert / delete / foreign-user update are all non-relevant.
        handler.handle(realtimePayload(
          table: 'user_profiles',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 1, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026),
        ));
        handler.handle(realtimePayload(
          table: 'user_profiles',
          eventType: sb.PostgresChangeEvent.delete,
          oldRecord: {'id': 2, 'user_id': 42},
          commitTimestamp: DateTime.utc(2026, 1, 2),
        ));
        handler.handle(realtimePayload(
          table: 'user_profiles',
          eventType: sb.PostgresChangeEvent.update,
          newRecord: {'id': 3, 'user_id': 999},
          commitTimestamp: DateTime.utc(2026, 1, 3),
        ));

        async.elapse(const Duration(milliseconds: 300));
        expect(refetchCount, 0);

        // A real partner-row UPDATE collapses to a single refetch.
        handler.handle(realtimePayload(
          table: 'user_profiles',
          eventType: sb.PostgresChangeEvent.update,
          newRecord: {'id': 4, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026, 1, 4),
        ));
        async.elapse(const Duration(milliseconds: 150));
        async.flushMicrotasks();

        expect(refetchCount, 1);
      });
    });
  });
}
