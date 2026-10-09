import 'dart:async';

/// Shared trailing-edge debounce scaffolding for the codebase's coalescers.
///
/// Mixed into a class that owns some buffered work and implements [flush]. The
/// host calls [schedule] whenever new work arrives; every call (re)starts the
/// [debounce] timer and the trailing edge runs [flush] once the quiet window
/// elapses. [drain] forces an immediate flush, while [cancelPending] cancels the
/// pending flush and lets the host drop any buffered work.
///
/// It is a mixin (not a base class) so the same timer lifecycle can back a
/// handler (`extends RealtimeHandler`), a state (`extends BaseState`) and a
/// plain class (`with WidgetsBindingObserver`) without duplicating the
/// `Timer`/cancel/restart scaffolding.
mixin TrailingEdgeDebounce {
  /// Quiet window that must elapse before the trailing-edge [flush] runs.
  Duration get debounce;

  Timer? _timer;

  /// (Re)starts the trailing-edge timer after new work was buffered.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Flushes every buffered item immediately, ignoring the timer.
  Future<void> drain() async {
    _timer?.cancel();
    _timer = null;
    await flush();
  }

  /// Cancels the pending flush and drops any buffered work.
  void cancelPending() {
    _timer?.cancel();
    _timer = null;
    discard();
  }

  /// Applies the buffered work on the trailing edge (and on [drain]).
  /// Implemented by the host.
  Future<void> flush();

  /// Drops buffered work without flushing. Defaults to a no-op for debouncers
  /// that only ever schedule a single action.
  void discard() {}
}
