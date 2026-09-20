import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Debounced (150 ms) `drive_items` / `drive_item_reactions` refresh: one full
/// `DriveState.refreshFromRealtime()` re-fetch, guarded against stale reaction
/// events by the session relevance filter.
class DriveRealtimeHandler {
  DriveRealtimeHandler({
    required RealtimeSyncSession session,
    required DriveState driveState,
  })  : _session = session,
        _driveState = driveState;

  final RealtimeSyncSession _session;
  final DriveState _driveState;

  Timer? _driveRefreshTimer;

  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleDrivePayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_session.suppressProcessing) return;
    if (!_session.isRelevantDrive(payload,
            driveItems: _driveState.driveItems) ||
        !_session.markSeen(payload)) {
      return;
    }

    _driveRefreshTimer?.cancel();
    _driveRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      AnsiLogger.realtime('_handleDrivePayload -> refreshFromRealtime()');
      unawaited(_driveState.refreshFromRealtime());
    });
  }

  void dispose() {
    _driveRefreshTimer?.cancel();
  }
}
