import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';

/// Direct contract tests for [CacheWriteQueue] (F-SC12).
///
/// This exercises the primitive on its own. The state-level test in
/// `drive_cache_serialization_test.dart` cannot prove the ordering on its own:
/// its writes are never in flight at the same time, so removing the queue
/// leaves it green (verified by mutation). These cases fail the moment the
/// serialization is dropped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes are applied in submission order even when the first is slow',
      () async {
    final queue = CacheWriteQueue();
    final gate = Completer<void>();
    final completed = <String>[];

    // The first write is held open; the second can only land after it if the
    // queue really serializes.
    final first = queue.enqueue(() async {
      await gate.future;
      completed.add('first');
    });
    final second = queue.enqueue(() async {
      completed.add('second');
    });

    // Let both submissions be registered, then release the first.
    await pumpEventQueue();
    expect(completed, isEmpty,
        reason: 'the second write must not overtake the held first one');

    gate.complete();
    await first;
    await second;

    expect(completed, ['first', 'second']);
  });

  test('a throwing write does not stall the rest of the chain', () async {
    final queue = CacheWriteQueue();
    final completed = <String>[];

    final failing = queue.enqueue(() async {
      throw StateError('boom');
    });
    final following = queue.enqueue(() async {
      completed.add('after-failure');
    });

    await expectLater(failing, throwsStateError);
    await following;

    expect(completed, ['after-failure'],
        reason: 'a failed write must not break the queue for later writes');
  });

  test('the queue keeps FIFO order across many interleaved writes', () async {
    final queue = CacheWriteQueue();
    final order = <int>[];

    final futures = <Future<void>>[];
    for (var i = 0; i < 10; i++) {
      final index = i;
      futures.add(queue.enqueue(() async {
        // Yield a varying number of turns so the writes would interleave if
        // they were not serialized.
        for (var turn = 0; turn < index; turn++) {
          await Future<void>.delayed(Duration.zero);
        }
        order.add(index);
      }));
    }

    await Future.wait(futures);

    expect(order, List<int>.generate(10, (i) => i));
  });
}
