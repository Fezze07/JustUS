import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Minimal `PostgresChangePayload` factory for unit-contract tests.
///
/// Mirrors the payload shape delivered by `RealtimeSyncConnection` so handlers
/// can be exercised in isolation without a live channel.
sb.PostgresChangePayload realtimePayload({
  String table = 'moods',
  required sb.PostgresChangeEvent eventType,
  Map<String, dynamic> newRecord = const {},
  Map<String, dynamic> oldRecord = const {},
  required DateTime commitTimestamp,
}) {
  return sb.PostgresChangePayload(
    schema: 'public',
    table: table,
    commitTimestamp: commitTimestamp,
    eventType: eventType,
    newRecord: newRecord,
    oldRecord: oldRecord,
    errors: null,
  );
}
