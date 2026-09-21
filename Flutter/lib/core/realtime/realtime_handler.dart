import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Base for every feature handler in the Realtime stack.
///
/// Owning the shared preamble means a change to suppression, relevance or
/// dedup propagates to *all* features at once instead of being re-implemented
/// in each handler. Subclasses supply only two pieces of behavior:
///
/// - [isRelevant] — re-verify the payload against the session ids.
/// - [onNewEvent] — route the deduplicated payload (immediate, debounced,
///   buffered or coalesced; see the strategy presets).
///
/// [handle] is the template method applied to every delivered payload:
///
/// ```
/// log -> suppressProcessing? drop -> isRelevant? -> markSeen? -> onNewEvent
/// ```
abstract class RealtimeHandler {
  RealtimeHandler({required this.session});

  /// Shared identity/dedup/decoding context (ids set by
  /// [RealtimeSyncService.configure]).
  final RealtimeSyncSession session;

  /// Per-feature relevance predicate (must call `session.isRelevant*`).
  bool isRelevant(sb.PostgresChangePayload payload);

  /// Applies a relevant, non-duplicate event using this feature's strategy.
  void onNewEvent(sb.PostgresChangePayload payload);

  /// Template method: suppression guard, relevance filter, dedup, dispatch.
  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '$runtimeType.handle() - table=${payload.table} eventType=${payload.eventType.name}');
    if (session.suppressProcessing) return;
    if (!isRelevant(payload) || !session.markSeen(payload)) return;
    onNewEvent(payload);
  }

  /// Drops buffered/pending work (called by `configure()` on identity change
  /// and by `suppress()`). No-op unless the strategy buffers.
  void clear() {}

  /// Releases timers held by the strategy. No-op unless it owns timers.
  void dispose() {}
}