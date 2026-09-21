import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Routes `game_questions` / `game_answers` events: insert/delete on
/// `game_questions` dispatch immediately, every other game event is buffered
/// FIFO in `GameEventBuffer` and flushed in delivery order (F-RT1).
class GameRealtimeHandler extends RealtimeHandler {
  GameRealtimeHandler({
    required super.session,
    required GameState gameState,
  }) : _gameState = gameState;

  final GameState _gameState;

  late final GameEventBuffer _eventBuffer = GameEventBuffer(
    sink: _applyGameEvent,
  );

  @override
  bool isRelevant(sb.PostgresChangePayload payload) =>
      session.isRelevantGame(payload);

  @override
  void onNewEvent(sb.PostgresChangePayload payload) {
    final table = payload.table;
    final eventType = payload.eventType.name;
    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;

    // Process insert/delete immediately so events aren't dropped by debounce
    if (table == 'game_questions' && eventType == 'insert') {
      AnsiLogger.realtime('$runtimeType -> handleQuestionInsert()');
      unawaited(_gameState.handleQuestionInsert(newRecord));
      return;
    }
    if (table == 'game_questions' && eventType == 'delete') {
      AnsiLogger.realtime('$runtimeType -> handleQuestionDelete()');
      unawaited(_gameState.handleQuestionDelete(oldRecord));
      return;
    }

    // Buffer every remaining game event FIFO. A burst (e.g. a partner's
    // `game_answers` INSERT followed within 150 ms by the `both_answered`
    // `game_questions` UPDATE) is applied entirely, in delivery order,
    // instead of keeping only the last event of the burst (F-RT1).
    AnsiLogger.realtime('$runtimeType -> buffered for FIFO flush');
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
      AnsiLogger.realtime('$runtimeType -> handleQuestionUpdate()');
      await _gameState.handleQuestionUpdate(newRecord);
    } else if (table == 'game_answers' && eventType == 'insert') {
      AnsiLogger.realtime('$runtimeType -> handleAnswerInsert()');
      await _gameState.handleAnswerInsert(newRecord);
    } else if (table == 'game_answers' && eventType == 'update') {
      AnsiLogger.realtime('$runtimeType -> handleAnswerUpdate()');
      await _gameState.handleAnswerUpdate(newRecord);
    } else if (table == 'game_answers' && eventType == 'delete') {
      AnsiLogger.realtime('$runtimeType -> handleAnswerDelete()');
      await _gameState.handleAnswerDelete(oldRecord);
    }
  }

  @override
  void clear() {
    _eventBuffer.clear();
  }
}