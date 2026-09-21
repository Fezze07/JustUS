import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Coalesces `moods` events into a `MoodChangeBatch` (distinct `changedUserId`
/// union) and refreshes `MoodState` per distinct user on flush.
class MoodRealtimeHandler extends RealtimeHandler {
  MoodRealtimeHandler({
    required super.session,
    required MoodState moodState,
  }) : _moodState = moodState;

  final MoodState _moodState;

  late final MoodChangeBatch _batch = MoodChangeBatch(
    sink: _applyMoodRefresh,
  );

  @override
  bool isRelevant(sb.PostgresChangePayload payload) =>
      session.isRelevantMood(payload);

  @override
  void onNewEvent(sb.PostgresChangePayload payload) {
    final changedUserId =
        session.rowUserId(session.currentRecord(payload), 'user_id');
    if (changedUserId == null) return;

    _batch.add(changedUserId);
  }

  Future<void> _applyMoodRefresh(List<int> changedUserIds) async {
    AnsiLogger.realtime(
        '_applyMoodRefresh -> refreshFromRealtime(changedUserIds=$changedUserIds)');
    await Future.wait(changedUserIds.map(
        (userId) => _moodState.refreshFromRealtime(changedUserId: userId)));
  }

  @override
  void clear() {
    _batch.clear();
  }
}