import 'dart:async';

/// Applies a coalesced mood refresh for a burst's distinct `changedUserId`
/// list to [sink] (F-RT2).
typedef MoodRefreshSink = Future<void> Function(List<int> changedUserIds);

/// Trailing-edge debounce that coalesces mood realtime events by distinct
/// `changedUserId`.
///
/// A mood event means "this user's mood changed". When own and partner mood
/// events land within [debounce] of each other, the refresh must cover *both*
/// distinct users — not just the last event's user (F-RT2). The full distinct
/// set is forwarded to [sink] when the debounce elapses.
class MoodChangeBatch {
  MoodChangeBatch({
    required this.sink,
    this.debounce = const Duration(milliseconds: 120),
  });

  final MoodRefreshSink sink;
  final Duration debounce;

  final Set<int> _pending = <int>{};
  Timer? _timer;

  /// Number of distinct users still waiting to be refreshed (for tests).
  int get pendingCount => _pending.length;

  /// Records [changedUserId] and (trailing edge) restarts the flush timer.
  void add(int changedUserId) {
    _pending.add(changedUserId);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_drain());
    });
  }

  /// Flushes every distinct user immediately.
  Future<void> drain() async {
    _timer?.cancel();
    _timer = null;
    await _drain();
  }

  Future<void> _drain() async {
    if (_pending.isEmpty) return;
    final userIds = _pending.toList();
    _pending.clear();
    await sink(userIds);
  }

  /// Cancels the pending flush and drops the buffered users.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
