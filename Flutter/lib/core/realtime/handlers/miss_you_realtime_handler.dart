import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Immediate `missyou` handling (no debounce): `insert` optimistically bumps
/// `HomepageState.addMissYou()`, `delete` triggers a full refresh.
class MissYouRealtimeHandler {
  MissYouRealtimeHandler({
    required RealtimeSyncSession session,
    required HomepageState homepageState,
  })  : _session = session,
        _homepageState = homepageState;

  final RealtimeSyncSession _session;
  final HomepageState _homepageState;

  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleMissYouPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_session.suppressProcessing) return;
    if (!_session.isRelevantMissYou(payload) || !_session.markSeen(payload)) {
      return;
    }

    if (payload.eventType.name == 'insert') {
      _homepageState.addMissYou();
    } else if (payload.eventType.name == 'delete') {
      unawaited(_homepageState.refreshFromRealtime());
    }
  }
}
