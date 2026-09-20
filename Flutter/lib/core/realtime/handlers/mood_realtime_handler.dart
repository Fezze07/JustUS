import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Coalesces `moods` events into a `MoodChangeBatch` (distinct `changedUserId`
/// union) and refreshes `MoodState` per distinct user on flush.
class MoodRealtimeHandler {
  MoodRealtimeHandler({
    required RealtimeSyncSession session,
    required MoodState moodState,
  })  : _session = session,
        _moodState = moodState;

  final RealtimeSyncSession _session;
  final MoodState _moodState;

  late final MoodChangeBatch _batch = MoodChangeBatch(
    sink: _applyMoodRefresh,
  );

  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleMoodPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_session.suppressProcessing) return;
    if (!_session.isRelevantMood(payload) || !_session.markSeen(payload)) {
      return;
    }

    final changedUserId =
        _session.rowUserId(_session.currentRecord(payload), 'user_id');
    if (changedUserId == null) return;

    _batch.add(changedUserId);
  }

  Future<void> _applyMoodRefresh(List<int> changedUserIds) async {
    AnsiLogger.realtime(
        '_applyMoodRefresh -> refreshFromRealtime(changedUserIds=$changedUserIds)');
    await Future.wait(changedUserIds.map(
        (userId) => _moodState.refreshFromRealtime(changedUserId: userId)));
  }

  void clear() {
    _batch.clear();
  }
}
