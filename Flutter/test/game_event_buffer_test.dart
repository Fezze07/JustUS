import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';

/// One delivered event, recorded in full.
///
/// The payload maps are part of the contract: `GameRealtimeHandler` picks the
/// state method by *which* map it received (`newRecord` for an UPDATE,
/// `oldRecord` for a DELETE), so recording only `(table, eventType)` would let
/// a swapped new/old regression pass unnoticed.
typedef AppliedEvent = (
  String table,
  String eventType,
  Map<String, dynamic> newRecord,
  Map<String, dynamic> oldRecord,
);

void main() {
  GameEventSink recordSink(List<AppliedEvent> applied) {
    return (table, eventType, newRecord, oldRecord) async {
      applied.add((table, eventType, newRecord, oldRecord));
    };
  }

  group('GameEventBuffer (F-RT1 FIFO)', () {
    test('applies a sub-debounce burst in FIFO order, nothing dropped', () {
      fakeAsync((async) {
        final applied = <AppliedEvent>[];
        final buffer = GameEventBuffer(
          sink: recordSink(applied),
        );

        // The F-RT1 scenario: partner's answer INSERT lands within 150 ms
        // of the both_answered question UPDATE.
        buffer.add(
          table: 'game_answers',
          eventType: 'insert',
          newRecord: {'game_id': 101, 'user_id': 77, 'selected_option': 42},
          oldRecord: const {},
        );
        buffer.add(
          table: 'game_questions',
          eventType: 'update',
          newRecord: {'id': 101, 'status': 'both_answered'},
          oldRecord: const {'id': 101, 'status': 'pending'},
        );

        async.elapse(const Duration(milliseconds: 150));

        expect(applied.map((e) => (e.$1, e.$2)), [
          ('game_answers', 'insert'),
          ('game_questions', 'update'),
        ]);
        // Each event must arrive with its OWN payload attached, in the right
        // slot — this is what the downstream dispatch branches on.
        expect(applied[0].$3, {
          'game_id': 101,
          'user_id': 77,
          'selected_option': 42,
        });
        expect(applied[0].$4, isEmpty);
        expect(applied[1].$3, {'id': 101, 'status': 'both_answered'});
        expect(applied[1].$4, {'id': 101, 'status': 'pending'});
        expect(buffer.pendingCount, 0);
      });
    });

    test('an UPDATE keeps new/old in their correct slots', () {
      fakeAsync((async) {
        final applied = <AppliedEvent>[];
        final buffer = GameEventBuffer(sink: recordSink(applied));

        buffer.add(
          table: 'game_answers',
          eventType: 'update',
          newRecord: {'game_id': 101, 'user_id': 77, 'selected_option': 42},
          oldRecord: {'game_id': 101, 'user_id': 77, 'selected_option': null},
        );

        async.elapse(const Duration(milliseconds: 150));

        expect(applied.single.$3['selected_option'], 42,
            reason: 'the post-write row belongs in newRecord');
        expect(applied.single.$4['selected_option'], isNull,
            reason: 'the pre-write row belongs in oldRecord');
      });
    });

    test('a DELETE carries the row in oldRecord and an empty newRecord', () {
      fakeAsync((async) {
        final applied = <AppliedEvent>[];
        final buffer = GameEventBuffer(sink: recordSink(applied));

        buffer.add(
          table: 'game_answers',
          eventType: 'delete',
          newRecord: const {},
          oldRecord: {'game_id': 101, 'user_id': 77},
        );

        async.elapse(const Duration(milliseconds: 150));

        expect(applied.single.$3, isEmpty,
            reason: 'a DELETE has no post-write row');
        expect(applied.single.$4, {'game_id': 101, 'user_id': 77},
            reason: 'a DELETE must still carry the old row for the handler');
      });
    });

    test('trailing edge: every add restarts the flush timer', () {
      fakeAsync((async) {
        final applied = <AppliedEvent>[];
        final buffer = GameEventBuffer(
          sink: recordSink(applied),
        );

        for (var i = 0; i < 5; i++) {
          buffer.add(
            table: 'game_answers',
            eventType: 'update',
            newRecord: {'counter': i},
            oldRecord: const {},
          );
          async.elapse(const Duration(milliseconds: 50));
        }

        // Last add at t=200 schedules the flush for t=350.
        async.elapse(const Duration(milliseconds: 99));
        expect(applied, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(applied.length, 5);
        // The buffered payloads survive the debounce intact.
        expect(applied.map((e) => e.$3['counter']), [0, 1, 2, 3, 4]);
        expect(buffer.pendingCount, 0);
      });
    });

    test('drain() applies all pending events immediately, in order', () async {
      final applied = <AppliedEvent>[];
      final buffer = GameEventBuffer(
        sink: recordSink(applied),
      );

      buffer.add(
        table: 'game_answers',
        eventType: 'update',
        newRecord: const {},
        oldRecord: const {},
      );
      buffer.add(
        table: 'game_answers',
        eventType: 'delete',
        newRecord: const {},
        oldRecord: {'user_id': 7},
      );
      expect(buffer.pendingCount, 2);

      await buffer.drain();

      expect(applied.map((e) => (e.$1, e.$2)), [
        ('game_answers', 'update'),
        ('game_answers', 'delete'),
      ]);
      // drain() must not lose or swap the payloads either.
      expect(applied[1].$4, {'user_id': 7});
      expect(buffer.pendingCount, 0);
    });

    test('clear() discards pending events and cancels the flush', () {
      fakeAsync((async) {
        final applied = <AppliedEvent>[];
        final buffer = GameEventBuffer(
          sink: recordSink(applied),
        );

        buffer.add(
          table: 'game_answers',
          eventType: 'insert',
          newRecord: const {},
          oldRecord: const {},
        );
        buffer.clear();

        async.elapse(const Duration(milliseconds: 250));

        expect(applied, isEmpty);
        expect(buffer.pendingCount, 0);
      });
    });

    test('events arriving while the drain is in flight are not lost', () {
      fakeAsync((async) {
        final applied = <AppliedEvent>[];
        final gate = Completer<void>();
        final buffer = GameEventBuffer(
          sink: (table, eventType, newRecord, oldRecord) async {
            applied.add((table, eventType, newRecord, oldRecord));
            await gate.future;
          },
        );

        buffer.add(
          table: 'game_answers',
          eventType: 'insert',
          newRecord: const {'seq': 1},
          oldRecord: const {},
        );
        // Fire the trailing-edge flush; the sink suspends on the gate.
        async.elapse(const Duration(milliseconds: 150));
        expect(applied.map((e) => (e.$1, e.$2)), [('game_answers', 'insert')]);

        // A new event lands while the first sink call is still in flight.
        buffer.add(
          table: 'game_answers',
          eventType: 'update',
          newRecord: const {'seq': 2},
          oldRecord: const {},
        );

        gate.complete();
        async.flushMicrotasks();

        // The same drain picked up the late event: FIFO preserved, nothing lost.
        expect(applied.map((e) => (e.$1, e.$2)), [
          ('game_answers', 'insert'),
          ('game_answers', 'update'),
        ]);
        // Both payloads kept their identity through the interleaved drain.
        expect(applied.map((e) => e.$3['seq']), [1, 2]);
        expect(buffer.pendingCount, 0);

        // Let the now-redundant late timer fire so the zone is clean.
        async.elapse(const Duration(milliseconds: 200));
      });
    });

    test('no event is lost across multiple debounce bursts', () {
      fakeAsync((async) {
        final applied = <AppliedEvent>[];
        final buffer = GameEventBuffer(
          sink: recordSink(applied),
        );

        // Burst 1.
        buffer.add(
          table: 'game_answers',
          eventType: 'insert',
          newRecord: const {},
          oldRecord: const {},
        );
        async.elapse(const Duration(milliseconds: 50));
        buffer.add(
          table: 'game_answers',
          eventType: 'update',
          newRecord: const {},
          oldRecord: const {},
        );
        async.elapse(const Duration(milliseconds: 150));
        async.flushMicrotasks();

        expect(applied.map((e) => (e.$1, e.$2)), [
          ('game_answers', 'insert'),
          ('game_answers', 'update'),
        ]);

        // Quiet gap (no events), then burst 2.
        async.elapse(const Duration(milliseconds: 200));
        buffer.add(
          table: 'game_answers',
          eventType: 'delete',
          newRecord: const {},
          oldRecord: const {},
        );
        async.elapse(const Duration(milliseconds: 30));
        buffer.add(
          table: 'game_questions',
          eventType: 'update',
          newRecord: const {},
          oldRecord: const {},
        );
        async.elapse(const Duration(milliseconds: 150));
        async.flushMicrotasks();

        expect(applied.map((e) => (e.$1, e.$2)), [
          ('game_answers', 'insert'),
          ('game_answers', 'update'),
          ('game_answers', 'delete'),
          ('game_questions', 'update'),
        ]);
        expect(buffer.pendingCount, 0);
      });
    });
  });
}
