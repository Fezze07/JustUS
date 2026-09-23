import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Immediate `missyou` handling (no debounce): `insert` optimistically bumps
/// `HomepageState.addMissYou()`, `delete` triggers a full refresh.
class MissYouRealtimeHandler extends RealtimeHandler {
  MissYouRealtimeHandler({
    required super.session,
    required HomepageState homepageState,
  }) : _homepageState = homepageState;

  final HomepageState _homepageState;

  @override
  bool isRelevant(sb.PostgresChangePayload payload) =>
      session.isRelevantMissYou(payload);

  @override
  void onNewEvent(sb.PostgresChangePayload payload) {
    if (payload.eventType.name == 'insert') {
      _homepageState.addMissYou(
        rowId: session.rowInt(payload.newRecord, 'id'),
      );
    } else if (payload.eventType.name == 'delete') {
      unawaited(_homepageState.refreshFromRealtime());
    }
  }
}