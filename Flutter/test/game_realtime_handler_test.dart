import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/realtime_payload_factory.dart';

class _MockGameState extends Mock implements GameState {}

void main() {
  group('GameRealtimeHandler (immediate + FIFO routing, F-RT1)', () {
    late RealtimeSyncSession session;
    late _MockGameState game;
    late GameRealtimeHandler handler;

    setUp(() {
      session = RealtimeSyncSession()
        ..userId = 42
        ..partnerId = 77
        ..partnershipId = 9001;
      game = _MockGameState();
      when(() => game.handleQuestionInsert(any())).thenAnswer((_) async {});
      when(() => game.handleQuestionDelete(any())).thenAnswer((_) async {});
      when(() => game.handleQuestionUpdate(any())).thenAnswer((_) async {});
      when(() => game.handleAnswerInsert(any())).thenAnswer((_) async {});
      when(() => game.handleAnswerUpdate(any())).thenAnswer((_) async {});
      when(() => game.handleAnswerDelete(any())).thenAnswer((_) async {});
      handler = GameRealtimeHandler(session: session, gameState: game);
    });

    test('game_questions insert remains immediate (not buffered)', () {
      fakeAsync((async) {
        var inserted = 0;
        when(() => game.handleQuestionInsert(any()))
            .thenAnswer((_) async => inserted++);
        handler.handle(realtimePayload(
          table: 'game_questions',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 1, 'partnership_id': 9001},
          commitTimestamp: DateTime.utc(2026),
        ));

        // Dispatched synchronously — no debounce to elapse first.
        expect(inserted, 1);

        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Still exactly one dispatch: nothing was replayed through a buffer.
        expect(inserted, 1);
      });
    });

    test('game_questions delete remains immediate (not buffered)', () {
      fakeAsync((async) {
        var deleted = 0;
        when(() => game.handleQuestionDelete(any()))
            .thenAnswer((_) async => deleted++);
        handler.handle(realtimePayload(
          table: 'game_questions',
          eventType: sb.PostgresChangeEvent.delete,
          oldRecord: {'id': 2},
          commitTimestamp: DateTime.utc(2026, 1, 2),
        ));

        expect(deleted, 1);

        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        expect(deleted, 1);
      });
    });

    test('every other game event is buffered and flushed in FIFO order', () {
      fakeAsync((async) {
        final applied = <String>[];
        when(() => game.handleQuestionUpdate(any()))
            .thenAnswer((_) async => applied.add('questionUpdate'));
        when(() => game.handleAnswerInsert(any()))
            .thenAnswer((_) async => applied.add('answerInsert'));

        // The F-RT1 scenario: partner answers (game_answers INSERT) then the
        // `both_answered` game_questions UPDATE arrives inside the debounce.
        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 1, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026),
        ));
        handler.handle(realtimePayload(
          table: 'game_questions',
          eventType: sb.PostgresChangeEvent.update,
          newRecord: {'id': 2, 'partnership_id': 9001},
          commitTimestamp: DateTime.utc(2026, 1, 2),
        ));

        async.elapse(const Duration(milliseconds: 150));
        async.flushMicrotasks();

        // Delivery order preserved inside the single FIFO flush.
        expect(applied, ['answerInsert', 'questionUpdate']);
        verifyNever(() => game.handleAnswerUpdate(any()));
        verifyNever(() => game.handleAnswerDelete(any()));
      });
    });

    test('clear() cancels a pending buffered flush', () {
      fakeAsync((async) {
        var inserted = 0;
        when(() => game.handleAnswerInsert(any()))
            .thenAnswer((_) async => inserted++);
        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 1, 'user_id': 42},
          commitTimestamp: DateTime.utc(2026),
        ));
        handler.clear();

        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        expect(inserted, 0);
      });
    });

    test('answer UPDATE routes handleAnswerUpdate with the new record', () {
      fakeAsync((async) {
        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.update,
          newRecord: {'game_id': 1, 'user_id': 77, 'selected_option': 2},
          oldRecord: {'game_id': 1, 'user_id': 77, 'selected_option': 1},
          commitTimestamp: DateTime.utc(2026),
        ));

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        final captured = verify(() => game.handleAnswerUpdate(captureAny()))
            .captured
            .single as Map<String, dynamic>;
        expect(captured['selected_option'], 2,
            reason: 'the post-update row must be handed to the state');
        verifyNever(() => game.handleAnswerDelete(any()));
        verifyNever(() => game.handleAnswerInsert(any()));
      });
    });

    test('answer DELETE routes handleAnswerDelete with the old record', () {
      fakeAsync((async) {
        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.delete,
          oldRecord: {'game_id': 1, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026),
        ));

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        // A DELETE has no newRecord; the identity lives in oldRecord.
        final captured = verify(() => game.handleAnswerDelete(captureAny()))
            .captured
            .single as Map<String, dynamic>;
        expect(captured['game_id'], 1);
        expect(captured['user_id'], 77);
        verifyNever(() => game.handleAnswerUpdate(any()));
      });
    });

    test('a mixed answer/question burst dispatches every event once, in order',
        () {
      fakeAsync((async) {
        final applied = <String>[];
        when(() => game.handleAnswerUpdate(any()))
            .thenAnswer((_) async => applied.add('answerUpdate'));
        when(() => game.handleAnswerDelete(any()))
            .thenAnswer((_) async => applied.add('answerDelete'));
        when(() => game.handleAnswerInsert(any()))
            .thenAnswer((_) async => applied.add('answerInsert'));
        when(() => game.handleQuestionUpdate(any()))
            .thenAnswer((_) async => applied.add('questionUpdate'));

        // All four buffered paths inside one debounce window: the F-RT1
        // regression shape. The question insert/delete paths are immediate
        // and must not be dropped while the burst drains.
        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'game_id': 1, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026),
        ));
        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.update,
          newRecord: {'game_id': 1, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026, 2),
        ));
        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.delete,
          oldRecord: {'game_id': 2, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026, 2),
        ));
        handler.handle(realtimePayload(
          table: 'game_questions',
          eventType: sb.PostgresChangeEvent.update,
          newRecord: {'id': 3, 'partnership_id': 9001},
          commitTimestamp: DateTime.utc(2026, 3),
        ));

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        expect(applied, [
          'answerInsert',
          'answerUpdate',
          'answerDelete',
          'questionUpdate',
        ]);
        verify(() => game.handleAnswerInsert(any())).called(1);
        verify(() => game.handleAnswerUpdate(any())).called(1);
        verify(() => game.handleAnswerDelete(any())).called(1);
        verify(() => game.handleQuestionUpdate(any())).called(1);
      });
    });

    test('question DELETE stays immediate even mid-burst', () {
      fakeAsync((async) {
        var deleted = 0;
        var inserted = 0;
        when(() => game.handleQuestionDelete(any()))
            .thenAnswer((_) async => deleted++);
        when(() => game.handleAnswerInsert(any()))
            .thenAnswer((_) async => inserted++);

        handler.handle(realtimePayload(
          table: 'game_answers',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'game_id': 1, 'user_id': 77},
          commitTimestamp: DateTime.utc(2026),
        ));
        handler.handle(realtimePayload(
          table: 'game_questions',
          eventType: sb.PostgresChangeEvent.delete,
          oldRecord: {'id': 5, 'partnership_id': 9001},
          commitTimestamp: DateTime.utc(2026, 4),
        ));

        // Immediate, before the debounce drains.
        expect(deleted, 1);
        expect(inserted, 0);

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        expect(inserted, 1);
        expect(deleted, 1);
      });
    });
  });
}
