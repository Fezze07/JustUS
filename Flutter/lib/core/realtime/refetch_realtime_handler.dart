import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Trailing-edge debounce that collapses a burst of events into **one** full
/// refetch.
///
/// This is the strategy of every order-insensitive full-refresh feature
/// (`partnerships`, `drive_items`/`drive_item_reactions`, `user_profiles`).
/// Those features were three near-identical handlers; this class replaces the
/// three so the timer lifecycle lives once. Construction in
/// [RealtimeSyncService] wires the per-feature pieces:
///
/// - [isRelevant] — the session relevance predicate (plus any event-type
///   restriction, e.g. `user_profiles` is `update`-only).
/// - [refetch] — the full-state reload, including any cache invalidation
///   (`BaseRepository.clearPartnershipCache`).
class RefetchRealtimeHandler extends RealtimeHandler {
  RefetchRealtimeHandler({
    required super.session,
    required bool Function(sb.PostgresChangePayload payload) isRelevant,
    required Future<void> Function() refetch,
    this.debounce = const Duration(milliseconds: 150),
  })  : _isRelevant = isRelevant,
        _refetch = refetch;

  final bool Function(sb.PostgresChangePayload) _isRelevant;
  final Future<void> Function() _refetch;

  /// Quiet window before the single refetch runs (trailing edge).
  final Duration debounce;

  Timer? _refreshTimer;

  @override
  bool isRelevant(sb.PostgresChangePayload payload) => _isRelevant(payload);

  @override
  void onNewEvent(sb.PostgresChangePayload payload) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(debounce, () {
      _refreshTimer = null;
      unawaited(_refetch());
    });
  }

  @override
  void clear() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() => clear();
}