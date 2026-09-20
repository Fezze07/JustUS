import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Immediate `bucket_items` application (no debounce): routes every event to
/// `BucketState.applyRealtimeEvent` in commit order.
class BucketRealtimeHandler {
  BucketRealtimeHandler({
    required RealtimeSyncSession session,
    required BucketState bucketState,
  })  : _session = session,
        _bucketState = bucketState;

  final RealtimeSyncSession _session;
  final BucketState _bucketState;

  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleBucketPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_session.suppressProcessing) return;
    if (!_session.isPartnershipRecord(payload) || !_session.markSeen(payload)) {
      return;
    }

    AnsiLogger.realtime('_handleBucketPayload -> applyRealtimeEvent()');
    unawaited(_bucketState.applyRealtimeEvent(
      eventType: payload.eventType.name,
      newRecord: payload.newRecord,
      oldRecord: payload.oldRecord,
    ));
  }
}
