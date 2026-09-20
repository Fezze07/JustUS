import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Routes `game_questions` / `game_answers` events: insert/delete on
/// `game_questions` dispatch immediately, every other game event is buffered
/// FIFO in `GameEventBuffer` and flushed in delivery order (F-RT1).
class GameRealtimeHandler {
  GameRealtimeHandler({
    required RealtimeSyncSession session,
    required GameState gameState,
  })  : _session = session,
        _gameState = gameState;

  final RealtimeSyncSession _session;
  final GameState _gameState;

  late final GameEventBuffer _eventBuffer = GameEventBuffer(
    sink: _applyGameEvent,
  );

  void handle(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleGamePayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_session.suppressProcessing) return;
    if (!_session.isRelevantGame(payload) || !_session.markSeen(payload)) {
      return;
    }

    final table = payload.table;
    final eventType = payload.eventType.name;
    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;

    // Process insert/delete immediately so events aren't dropped by debounce
    if (table == 'game_questions' && eventType == 'insert') {
      AnsiLogger.realtime('_handleGamePayload -> handleQuestionInsert()');
      unawaited(_gameState.handleQuestionInsert(newRecord));
      return;
    }
    if (table == 'game_questions' && eventType == 'delete') {
      AnsiLogger.realtime('_handleGamePayload -> handleQuestionDelete()');
      unawaited(_gameState.handleQuestionDelete(oldRecord));
      return;
    }

    // Buffer every remaining game event FIFO. A burst (e.g. a partner's
    // `game_answers` INSERT followed within 150 ms by the `both_answered`
    // `game_questions` UPDATE) is applied entirely, in delivery order,
    // instead of keeping only the last event of the burst (F-RT1).
    AnsiLogger.realtime('_handleGamePayload -> buffered for FIFO flush');
    _eventBuffer.add(
      table: table,
      eventType: eventType,
      newRecord: newRecord,
      oldRecord: oldRecord,
    );
  }

  Future<void> _applyGameEvent(
    String table,
    String eventType,
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) async {
    if (table == 'game_questions' && eventType == 'update') {
      AnsiLogger.realtime('_handleGamePayload -> handleQuestionUpdate()');
      await _gameState.handleQuestionUpdate(newRecord);
    } else if (table == 'game_answers' && eventType == 'insert') {
      AnsiLogger.realtime('_handleGamePayload -> handleAnswerInsert()');
      await _gameState.handleAnswerInsert(newRecord);
    } else if (table == 'game_answers' && eventType == 'update') {
      AnsiLogger.realtime('_handleGamePayload -> handleAnswerUpdate()');
      await _gameState.handleAnswerUpdate(newRecord);
    } else if (table == 'game_answers' && eventType == 'delete') {
      AnsiLogger.realtime('_handleGamePayload -> handleAnswerDelete()');
      await _gameState.handleAnswerDelete(oldRecord);
    }
  }

  void clear() {
    _eventBuffer.clear();
  }
}
