import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';

void main() {
  MoodRefreshSink recordSink(List<List<int>> applied) {
    return (userIds) async {
      applied.add(userIds);
    };
  }

  group('MoodChangeBatch (F-RT2 distinct-user coalescing)', () {
    test('own + partner burst is coalesced into both distinct users', () {
      fakeAsync((async) {
        final applied = <List<int>>[];
        final batch = MoodChangeBatch(
          sink: recordSink(applied),
        );

        // F-RT2 scenario: own and partner mood events land within 120 ms.
        batch.add(42);
        async.elapse(const Duration(milliseconds: 50));
        batch.add(77);

        async.elapse(const Duration(milliseconds: 120));

        expect(applied, [
          containsAll(<int>[42, 77]),
        ]);
        expect(batch.pendingCount, 0);
      });
    });

    test('repeated events for the same user collapse to one entry', () {
      fakeAsync((async) {
        final applied = <List<int>>[];
        final batch = MoodChangeBatch(
          sink: recordSink(applied),
        );

        batch.add(42);
        async.elapse(const Duration(milliseconds: 10));
        batch.add(77);
        async.elapse(const Duration(milliseconds: 10));
        batch.add(42);

        async.elapse(const Duration(milliseconds: 120));

        expect(applied.length, 1);
        expect(applied.first.toSet(), {42, 77});
      });
    });

    test('trailing edge: every add restarts the flush timer', () {
      fakeAsync((async) {
        final applied = <List<int>>[];
        final batch = MoodChangeBatch(
          sink: recordSink(applied),
        );

        for (var i = 0; i < 4; i++) {
          batch.add(42 + i);
          async.elapse(const Duration(milliseconds: 50));
        }

        // After the loop t=200; last add (t=150) schedules flush at t=270.
        async.elapse(const Duration(milliseconds: 69));
        expect(applied, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(applied.length, 1);
        expect(applied.first.toSet(), {42, 43, 44, 45});
        expect(batch.pendingCount, 0);
      });
    });

    test('drain() flushes the distinct users immediately', () async {
      final applied = <List<int>>[];
      final batch = MoodChangeBatch(
        sink: recordSink(applied),
      );

      batch.add(42);
      batch.add(77);
      expect(batch.pendingCount, 2);

      await batch.drain();

      expect(applied.first.toSet(), {42, 77});
      expect(batch.pendingCount, 0);
    });

    test('clear() discards pending users and cancels the flush', () {
      fakeAsync((async) {
        final applied = <List<int>>[];
        final batch = MoodChangeBatch(
          sink: recordSink(applied),
        );

        batch.add(42);
        batch.clear();

        async.elapse(const Duration(milliseconds: 200));

        expect(applied, isEmpty);
        expect(batch.pendingCount, 0);
      });
    });

    test('a user arriving while the drain is in flight is not lost', () {
      fakeAsync((async) {
        final applied = <List<int>>[];
        final gate = Completer<void>();
        final batch = MoodChangeBatch(
          sink: (userIds) async {
            applied.add(userIds);
            await gate.future;
          },
        );

        batch.add(42);
        // The drain snapshots the pending set, then suspends in the sink.
        unawaited(batch.drain());
        expect(applied, [
          [42]
        ]);

        // A new distinct user lands while the drain is suspended.
        batch.add(77);

        gate.complete();
        async.flushMicrotasks();
        // The first drain already committed [42]; 77 is still pending.
        expect(applied, [
          [42]
        ]);

        async.elapse(const Duration(milliseconds: 120));
        async.flushMicrotasks();

        expect(applied, [
          [42],
          [77],
        ]);
        expect(batch.pendingCount, 0);
      });
    });
  });
}
