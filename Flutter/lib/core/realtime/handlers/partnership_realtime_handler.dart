import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Debounced (150 ms) partnership refresh: clears the repository cache, then
/// refetches into both `PartnerState` and `AuthState`.
class PartnershipRealtimeHandler {
  PartnershipRealtimeHandler({
    required RealtimeSyncSession session,
    required PartnerState partnerState,
    required AuthState authState,
  })  : _session = session,
        _partnerState = partnerState,
        _authState = authState;

  final RealtimeSyncSession _session;
  final PartnerState _partnerState;
  final AuthState _authState;

  Timer? _partnershipRefreshTimer;

  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handlePartnershipPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_session.suppressProcessing) return;
    if (!_session.isRelevantPartnership(payload) ||
        !_session.markSeen(payload)) {
      return;
    }

    _partnershipRefreshTimer?.cancel();
    _partnershipRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      AnsiLogger.realtime('_handlePartnershipPayload -> refreshFromRealtime()');
      BaseRepository.clearPartnershipCache();
      unawaited(Future.wait([
        _partnerState.refreshFromRealtime(),
        _authState.refreshPartnershipFromRealtime(),
      ]));
    });
  }

  void dispose() {
    _partnershipRefreshTimer?.cancel();
  }
}
