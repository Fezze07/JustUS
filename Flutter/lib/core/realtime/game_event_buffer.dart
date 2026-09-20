import 'dart:async';
import 'dart:collection';

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
/// within [debounce] by the `game_questions` UPDATE that marks
/// `both_answered`) is buffered instead of collapsing to the last event, so
/// no intermediate event is ever dropped (F-RT1). Every buffered event is
/// applied to [sink] in delivery order when the debounce elapses.
class GameEventBuffer {
  GameEventBuffer({
    required this.sink,
    this.debounce = const Duration(milliseconds: 150),
  });

  final GameEventSink sink;
  final Duration debounce;

  final Queue<_BufferedGameEvent> _pending = Queue<_BufferedGameEvent>();
  Timer? _timer;

  /// Number of events still waiting to be applied (for tests/inspection).
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
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_drain());
    });
  }

  /// Applies every buffered event immediately, in FIFO order.
  Future<void> drain() async {
    _timer?.cancel();
    _timer = null;
    await _drain();
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final event = _pending.removeFirst();
      await sink(
          event.table, event.eventType, event.newRecord, event.oldRecord);
    }
  }

  /// Cancels the pending flush and drops all buffered events.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
