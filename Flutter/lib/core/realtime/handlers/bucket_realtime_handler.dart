import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Immediate `bucket_items` application (no debounce): routes every event to
/// `BucketState.applyRealtimeEvent` in commit order.
class BucketRealtimeHandler extends RealtimeHandler {
  BucketRealtimeHandler({
    required super.session,
    required BucketState bucketState,
  }) : _bucketState = bucketState;

  final BucketState _bucketState;

  @override
  bool isRelevant(sb.PostgresChangePayload payload) =>
      session.isPartnershipRecord(payload);

  @override
  void onNewEvent(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime('$runtimeType -> applyRealtimeEvent()');
    unawaited(_bucketState.applyRealtimeEvent(
      eventType: payload.eventType.name,
      newRecord: payload.newRecord,
      oldRecord: payload.oldRecord,
    ));
  }
}