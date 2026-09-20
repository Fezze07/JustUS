import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Handles one Postgres change payload delivered on the Realtime channel.
typedef RealtimePayloadCallback = void Function(sb.PostgresChangePayload);

/// Declarative table -> handler wiring for the 9 `.onPostgresChanges`
/// bindings. The connection iterates the (order-preserving) list to build the
/// channel and route each table's payload to its feature handler.
class RealtimeTableBinding {
  const RealtimeTableBinding({
    required this.table,
    required this.callback,
  });

  final String table;
  final RealtimePayloadCallback callback;
}
