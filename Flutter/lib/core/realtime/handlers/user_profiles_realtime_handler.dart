import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Debounced (150 ms) `user_profiles` handling for `UPDATE` events only:
/// clears the partnership cache and refreshes `ProfileState` + `PartnerState`
/// + `AuthState` so self/partner profile edits propagate in realtime.
class UserProfilesRealtimeHandler {
  UserProfilesRealtimeHandler({
    required RealtimeSyncSession session,
    required ProfileState profileState,
    required PartnerState partnerState,
    required AuthState authState,
  })  : _session = session,
        _profileState = profileState,
        _partnerState = partnerState,
        _authState = authState;

  final RealtimeSyncSession _session;
  final ProfileState _profileState;
  final PartnerState _partnerState;
  final AuthState _authState;

  Timer? _userProfileRefreshTimer;

  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleUserProfilesPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_session.suppressProcessing) return;
    if (payload.eventType.name != 'update') return;
    if (!_session.isRelevantUserProfile(payload) ||
        !_session.markSeen(payload)) {
      return;
    }

    _userProfileRefreshTimer?.cancel();
    _userProfileRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      AnsiLogger.realtime(
          '_handleUserProfilesPayload -> refresh profiles (user/partner)');
      BaseRepository.clearPartnershipCache();
      unawaited(Future.wait([
        _profileState.loadProfile(force: true),
        _partnerState.refreshFromRealtime(),
        _authState.refreshPartnershipFromRealtime(),
      ]));
    });
  }

  void dispose() {
    _userProfileRefreshTimer?.cancel();
  }
}
