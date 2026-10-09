import 'dart:async';
import 'dart:collection';

import 'package:justus/all_imports.dart';

/// Applies a decoded game realtime event to [sink] in FIFO order.
///
/// [table] / [eventType] mirror the Supabase payload (`game_questions` /
/// `game_answers`), [newRecord] is the post-write row and [oldRecord] the
/// pre-write row (empty for inserts).
typedef GameEventSink = Future<void> Function(
  String table,
  String eventType,
  Map<String, dynamic> newRecord,
  Map<String, dynamic> oldRecord,
);

class _BufferedGameEvent {
  const _BufferedGameEvent({
    required this.table,
    required this.eventType,
    required this.newRecord,
    required this.oldRecord,
  });

  final String table;
  final String eventType;
  final Map<String, dynamic> newRecord;
  final Map<String, dynamic> oldRecord;
}

/// Trailing-edge debounce FIFO for game realtime events.
///
/// A burst of game events (e.g. a partner's `game_answers` INSERT followed
/// within the debounce window by the `game_questions` UPDATE that marks
/// `both_answered`) is buffered instead of collapsing to the last event, so
/// no intermediate event is ever dropped (F-RT1). Every buffered event is
/// applied to [sink] in delivery order when the debounce elapses.
class GameEventBuffer with TrailingEdgeDebounce {
  GameEventBuffer({
    required this.sink,
    this.debounce = const Duration(milliseconds: 150),
  });

  final GameEventSink sink;

  @override
  final Duration debounce;

  final Queue<_BufferedGameEvent> _pending = Queue<_BufferedGameEvent>();

  int get pendingCount => _pending.length;

  /// Buffers [event] and (trailing edge) restarts the flush timer.
  void add({
    required String table,
    required String eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    _pending.addLast(_BufferedGameEvent(
      table: table,
      eventType: eventType,
      newRecord: newRecord,
      oldRecord: oldRecord,
    ));
    schedule();
  }

  @override
  Future<void> flush() async {
    while (_pending.isNotEmpty) {
      final event = _pending.removeFirst();
      await sink(
          event.table, event.eventType, event.newRecord, event.oldRecord);
    }
  }

  @override
  void discard() => _pending.clear();

  /// Cancels the pending flush and drops all buffered events.
  void clear() => cancelPending();
}
