import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/realtime_payload_factory.dart';

/// Session that records every `markSeen` invocation so the template's
/// evaluation order is observable from inside the shared preamble.
class _RecordingSession extends RealtimeSyncSession {
  _RecordingSession(this.trace);

  final List<String> trace;

  @override
  bool markSeen(sb.PostgresChangePayload payload) {
    trace.add('markSeen');
    return super.markSeen(payload);
  }
}

/// Minimal handler subclass used to exercise the base template without pulling
/// in a feature state. Shares a single [trace] list with the session so the
/// full template order can be asserted on one object.
class _RecordingHandler extends RealtimeHandler {
  _RecordingHandler({
    required super.session,
    this.relevant = true,
    List<String>? trace,
  }) : trace = trace ?? <String>[];

  final bool relevant;
  final List<String> trace;

  @override
  bool isRelevant(sb.PostgresChangePayload payload) {
    trace.add('isRelevant');
    return relevant;
  }

  @override
  void onNewEvent(sb.PostgresChangePayload payload) {
    trace.add('onNewEvent');
  }
}

void main() {
  group('RealtimeHandler template (unified preamble contract)', () {
    test('suppressProcessing drops the event', () {
      final trace = <String>[];
      final session = _RecordingSession(trace);
      final handler = _RecordingHandler(session: session, trace: trace);

      session.suppressProcessing = true;
      handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          commitTimestamp: DateTime.utc(2026)));

      // The trace is empty, so the event never even reached `isRelevant`.
      expect(trace, isEmpty);
      // `handle()` must not mutate the flag it reads — asserting `isTrue` here
      // would only restate the assignment two lines above.
      expect(session.suppressProcessing, isTrue,
          reason: 'handle() must leave the suppression flag untouched');
    });

    test('an event stops being suppressed once the flag is cleared', () {
      final trace = <String>[];
      final session = _RecordingSession(trace);
      final handler = _RecordingHandler(session: session, trace: trace);
      final payload = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        commitTimestamp: DateTime.utc(2026, 3),
      );

      session.suppressProcessing = true;
      handler.handle(payload);
      expect(trace, isEmpty);

      // Same payload, suppression lifted: it must flow all the way through.
      session.suppressProcessing = false;
      handler.handle(payload);
      expect(trace, ['isRelevant', 'markSeen', 'onNewEvent']);
    });

    test('irrelevant events are dropped before markSeen/dispatch', () {
      final trace = <String>[];
      final session = _RecordingSession(trace);
      final handler =
          _RecordingHandler(session: session, relevant: false, trace: trace);

      handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          commitTimestamp: DateTime.utc(2026, 1, 2)));

      // Relevance gates dedup and dispatch: markSeen is not even reached.
      expect(trace, ['isRelevant']);
    });

    test('relevant events are dispatched', () {
      final trace = <String>[];
      final session = _RecordingSession(trace);
      final handler = _RecordingHandler(session: session, trace: trace);

      handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          commitTimestamp: DateTime.utc(2026, 1, 3)));

      expect(trace, ['isRelevant', 'markSeen', 'onNewEvent']);
    });

    test('duplicate events are dropped at markSeen', () {
      final trace = <String>[];
      final session = _RecordingSession(trace);
      final handler = _RecordingHandler(session: session, trace: trace);

      final duplicate = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        commitTimestamp: DateTime.utc(2026, 1, 4),
      );
      handler.handle(duplicate);
      handler.handle(duplicate);

      // Second delivery runs suppress+relevance+markSeen but stops before
      // onNewEvent because markSeen reported it as already seen.
      expect(trace, [
        'isRelevant',
        'markSeen',
        'onNewEvent',
        'isRelevant',
        'markSeen',
      ]);
    });

    test('evaluation order: suppress -> relevance -> markSeen -> onNewEvent',
        () {
      final trace = <String>[];
      final session = _RecordingSession(trace);
      final handler = _RecordingHandler(session: session, trace: trace);

      // Unsuppressed, relevant, unique: the full pipeline runs in order.
      handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          commitTimestamp: DateTime.utc(2026, 2)));
      expect(trace, ['isRelevant', 'markSeen', 'onNewEvent']);

      // suppress short-circuits before relevance.
      trace.clear();
      session.suppressProcessing = true;
      handler.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          commitTimestamp: DateTime.utc(2026, 2, 2)));
      expect(trace, isEmpty);

      // relevance gates markSeen.
      session.suppressProcessing = false;
      final blocked =
          _RecordingHandler(session: session, relevant: false, trace: trace);
      blocked.handle(realtimePayload(
          eventType: sb.PostgresChangeEvent.insert,
          commitTimestamp: DateTime.utc(2026, 2, 3)));
      expect(trace, ['isRelevant']);

      // markSeen gates onNewEvent on a replayed (already-seen) event.
      trace.clear();
      final fresh = _RecordingHandler(session: session, trace: trace);
      final replayed = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        commitTimestamp: DateTime.utc(2026, 2, 4),
      );
      fresh.handle(replayed);
      final seen = List<String>.from(trace);
      fresh.handle(replayed);
      expect(seen, ['isRelevant', 'markSeen', 'onNewEvent']);
      expect(trace, [...seen, 'isRelevant', 'markSeen']);
    });
  });
}
