import 'dart:async';

import 'package:justus/all_imports.dart';

/// Applies a coalesced mood refresh for a burst's distinct `changedUserId`
/// list to [sink] (F-RT2).
typedef MoodRefreshSink = Future<void> Function(List<int> changedUserIds);

/// Trailing-edge debounce that coalesces mood realtime events by distinct
/// `changedUserId`.
///
/// A mood event means "this user's mood changed". When own and partner mood
/// events land within the debounce window of each other, the refresh must cover
/// *both* distinct users — not just the last event's user (F-RT2). The full
/// distinct set is forwarded to [sink] when the debounce elapses.
class MoodChangeBatch with TrailingEdgeDebounce {
  MoodChangeBatch({
    required this.sink,
    this.debounce = const Duration(milliseconds: 120),
  });

  final MoodRefreshSink sink;

  @override
  final Duration debounce;

  final Set<int> _pending = <int>{};

  int get pendingCount => _pending.length;

  /// Records [changedUserId] and (trailing edge) restarts the flush timer.
  void add(int changedUserId) {
    _pending.add(changedUserId);
    schedule();
  }

  @override
  Future<void> flush() async {
    if (_pending.isEmpty) return;
    final userIds = _pending.toList();
    _pending.clear();
    await sink(userIds);
  }

  @override
  void discard() => _pending.clear();

  /// Cancels the pending flush and drops the buffered users.
  void clear() => cancelPending();
}
