import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Owns the Realtime channel, auth listener, and all connection-level state
/// (lifecycle, reconnect backoff, polling fallback).
///
/// Created and torn down by [RealtimeSyncService]; feature handlers are wired
/// via [bindings] and a shared [RealtimeSyncSession] supplies the identity and
/// processing-suppression flags.
class RealtimeSyncConnection with WidgetsBindingObserver {
  RealtimeSyncConnection({
    required sb.SupabaseClient client,
    required RealtimeSyncSession session,
    required List<RealtimeTableBinding> bindings,
    required Future<void> Function() refreshAll,
  })  : _client = client,
        _session = session,
        _bindings = List.unmodifiable(bindings),
        _refreshAll = refreshAll;

  final sb.SupabaseClient _client;
  final RealtimeSyncSession _session;
  final List<RealtimeTableBinding> _bindings;
  final Future<void> Function() _refreshAll;

  sb.RealtimeChannel? _channel;
  StreamSubscription<dynamic>? _authSubscription;
  Timer? _reconnectTimer;
  Timer? _lifecycleDebounceTimer;
  Timer? _pollingFallbackTimer;

  bool _disposed = false;
  bool _foreground = true;
  bool _subscribing = false;
  bool _usePollingFallback = false;
  int _generation = 0;
  int _reconnectAttempt = 0;
  int _consecutiveFailures = 0;

  bool get foreground => _foreground;
  bool get usePollingFallback => _usePollingFallback;

  /// Registers as a lifecycle observer and subscribes to auth token-refresh.
  void start() {
    if (_disposed) return;

    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _client.auth.onAuthStateChange.listen((authState) {
      AnsiLogger.realtime(
          'auth state changed: event=${authState.event} foreground=$_foreground userId=${_session.userId}');

      // Token refresh is handled internally by Supabase; just update the
      // JWT on the existing Realtime connection without disconnecting.
      if (authState.event == sb.AuthChangeEvent.tokenRefreshed) {
        final token = authState.session?.accessToken;
        if (token != null) {
          AnsiLogger.realtime('token refreshed -> realtime.setAuth()');
          unawaited(_client.realtime.setAuth(token));
        }
        return;
      }

      if (_foreground && _session.userId != null) {
        scheduleReconnect();
      }
    });
  }

  /// Resets backoff/failure counters (called by `configure()` even when
  /// nothing changed).
  void resetRetryCounters() {
    _reconnectAttempt = 0;
    _consecutiveFailures = 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    AnsiLogger.realtime(
        'lifecycle state=$state foreground=$_foreground userId=${_session.userId}');

    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        if (_session.userId != null) {
          _lifecycleDebounceTimer?.cancel();
          _lifecycleDebounceTimer =
              Timer(const Duration(milliseconds: 300), () {
            _lifecycleDebounceTimer = null;
            _reconnectAttempt = 0;
            scheduleReconnect(refreshAfterSubscribe: true);
          });
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        _lifecycleDebounceTimer?.cancel();
        _lifecycleDebounceTimer = null;
        unawaited(unsubscribe());
      case AppLifecycleState.inactive:
        break;
    }
  }

  void scheduleReconnect(
      {bool refreshAfterSubscribe = false, sb.RealtimeCloseEvent? closeEvent}) {
    if (_disposed || !_foreground || _session.userId == null) return;

    _reconnectAttempt++;
    _consecutiveFailures++;

    if (_consecutiveFailures >= 3 && !_usePollingFallback) {
      activatePollingFallback();
    }

    if (_reconnectAttempt > 20) {
      AnsiLogger.realtime(
          '_scheduleReconnect() - max retries (20) reached, giving up (will reset on next configure)');
      _reconnectAttempt = 0;
      return;
    }

    final shift = (_reconnectAttempt - 1).clamp(0, 7);

    var baseDelayMs = 1000;
    if (closeEvent != null && closeEvent.code == 1002) {
      baseDelayMs = 3000;
    }

    final delayMs = (baseDelayMs * (1 << shift)).clamp(1000, 60000);

    final jitter = (delayMs * 0.25).round();
    final finalDelay = delayMs +
        (DateTime.now().microsecondsSinceEpoch % (jitter * 2 + 1) - jitter);

    AnsiLogger.realtime(
        '_scheduleReconnect() - attempt=$_reconnectAttempt delay=${finalDelay}ms refreshAfterSubscribe=$refreshAfterSubscribe');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: finalDelay), () {
      AnsiLogger.realtime(
          '_scheduleReconnect() - timer fired, calling _subscribe');
      unawaited(subscribe(refreshAfterSubscribe: refreshAfterSubscribe));
    });
  }

  void activatePollingFallback() {
    if (_usePollingFallback || _disposed) return;
    _usePollingFallback = true;
    AnsiLogger.realtime(
        '_activatePollingFallback() - Realtime unstable, switching to polling');
    _pollingFallbackTimer?.cancel();
    _pollingFallbackTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (_disposed || !_foreground) {
          _pollingFallbackTimer?.cancel();
          return;
        }
        AnsiLogger.realtime('polling fallback: _refreshAll()');
        unawaited(_refreshAll());
      },
    );
    unawaited(_refreshAll());
  }

  void deactivatePollingFallback() {
    if (!_usePollingFallback) return;
    _usePollingFallback = false;
    _pollingFallbackTimer?.cancel();
    _pollingFallbackTimer = null;
    AnsiLogger.realtime(
        '_deactivatePollingFallback() - Realtime recovered, polling stopped');
  }

  Future<void> subscribe({required bool refreshAfterSubscribe}) async {
    if (_disposed || _subscribing || !_foreground || _session.userId == null) {
      AnsiLogger.realtime(
          '_subscribe() - SKIP: disposed=$_disposed subscribing=$_subscribing foreground=$_foreground userId=${_session.userId}');
      return;
    }

    _lifecycleDebounceTimer?.cancel();
    _lifecycleDebounceTimer = null;

    _subscribing = true;
    _session.suppressProcessing = false;
    try {
      _generation += 1;
      AnsiLogger.realtime(
          '_subscribe() - subscribing generation=$_generation userId=${_session.userId} refreshAfterSubscribe=$refreshAfterSubscribe');
      await unsubscribe();
      if (_disposed || !_foreground || _session.userId == null) return;

      var channel =
          _client.channel('justus-sync-${_session.userId}-$_generation');
      for (final binding in _bindings) {
        channel = channel.onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: binding.table,
          callback: binding.callback,
        );
      }

      _channel = channel;
      final int subscribedGeneration = _generation;
      try {
        channel.subscribe((status, error) {
          if (_disposed) return;

          if (subscribedGeneration != _generation) {
            AnsiLogger.realtime(
                'channel status=$status (stale gen=$subscribedGeneration, current=$_generation) - ignoring');
            return;
          }

          AnsiLogger.realtime(
              'channel status=$status${error != null ? ' error=$error' : ''}');

          if (status == sb.RealtimeSubscribeStatus.subscribed) {
            _reconnectAttempt = 0;
            _consecutiveFailures = 0;
            if (_usePollingFallback) {
              deactivatePollingFallback();
            }
            if (refreshAfterSubscribe) {
              unawaited(_refreshAll());
            }
            return;
          }

          if (status == sb.RealtimeSubscribeStatus.channelError &&
              error is sb.RealtimeCloseEvent) {
            AnsiLogger.error(
                'channel status $status: code=${error.code} reason=${error.reason}',
                tag: 'RealtimeSync');
            scheduleReconnect(closeEvent: error);
          } else if (status == sb.RealtimeSubscribeStatus.closed ||
              status == sb.RealtimeSubscribeStatus.channelError ||
              status == sb.RealtimeSubscribeStatus.timedOut) {
            if (error != null) {
              AnsiLogger.error('channel status $status: $error',
                  tag: 'RealtimeSync');
            }
            scheduleReconnect();
          }
        });
      } catch (e) {
        AnsiLogger.error('channel.subscribe() threw: $e', tag: 'RealtimeSync');
        if (!_disposed && _foreground) {
          scheduleReconnect();
        }
      }
    } catch (e) {
      AnsiLogger.error('_subscribe() failed: $e', tag: 'RealtimeSync');
      if (!_disposed && _foreground) {
        scheduleReconnect();
      }
    } finally {
      _subscribing = false;
    }
  }

  Future<void> unsubscribe() async {
    _reconnectTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel == null) {
      AnsiLogger.realtime('_unsubscribe() - no active channel');
      return;
    }

    AnsiLogger.realtime('_unsubscribe() - removing channel');
    try {
      await _client.removeChannel(channel);
      AnsiLogger.realtime('_unsubscribe() - channel removed');
    } catch (e) {
      AnsiLogger.error('removeChannel failed: $e', tag: 'RealtimeSync');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleDebounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _pollingFallbackTimer?.cancel();
    await _authSubscription?.cancel();
    await unsubscribe();
  }
}
