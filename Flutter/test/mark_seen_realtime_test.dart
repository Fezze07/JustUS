import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/realtime_payload_factory.dart';

void main() {
  group('RealtimeSyncSession.markSeen (bounded LRU dedup)', () {
    test('duplicate events are rejected', () {
      final session = RealtimeSyncSession();
      final event = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'id': 1, 'user_id': 42},
        commitTimestamp: DateTime.utc(2026),
      );

      expect(session.markSeen(event), isTrue);
      expect(session.markSeen(event), isFalse);
    });

    test('same row with a different commit timestamp is a new event', () {
      final session = RealtimeSyncSession();
      final first = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'id': 1, 'user_id': 42},
        commitTimestamp: DateTime.utc(2026),
      );
      final second = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'id': 1, 'user_id': 42},
        commitTimestamp: DateTime.utc(2026, 1, 2),
      );

      expect(session.markSeen(first), isTrue);
      expect(session.markSeen(second), isTrue);
    });

    test('key is (table, eventType, row id, commitTs), not row content', () {
      final session = RealtimeSyncSession();
      final a = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'id': 5, 'user_id': 42},
        commitTimestamp: DateTime.utc(2026),
      );
      // Same table+event+id+ts but different content -> still a duplicate.
      final b = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'id': 5, 'user_id': 77},
        commitTimestamp: DateTime.utc(2026),
      );

      expect(session.markSeen(a), isTrue);
      expect(session.markSeen(b), isFalse);

      // A different event type on the same row at the same timestamp is a
      // distinct key.
      final c = realtimePayload(
        eventType: sb.PostgresChangeEvent.delete,
        oldRecord: {'id': 5, 'user_id': 77},
        commitTimestamp: DateTime.utc(2026),
      );
      expect(session.markSeen(c), isTrue);
    });

    test(
        'LRU eviction: within-window replays are dropped, replays after '
        'eviction are re-accepted', () {
      final session = RealtimeSyncSession();
      final events = List.generate(
          80,
          (i) => realtimePayload(
                eventType: sb.PostgresChangeEvent.insert,
                newRecord: {'id': i},
                commitTimestamp: DateTime.utc(2026).add(Duration(minutes: i)),
              ));

      for (final event in events) {
        expect(session.markSeen(event), isTrue);
      }

      // 81st distinct event pushes the window: the oldest key is evicted
      // (maxTrackedEvents = 80).
      final overflow = realtimePayload(
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'id': 1000},
        commitTimestamp: DateTime.utc(2026).add(const Duration(minutes: 1000)),
      );
      expect(session.markSeen(overflow), isTrue);

      // events[1] is still inside the 80-event window: replay is rejected.
      expect(session.markSeen(events[1]), isFalse);

      // events[0] was evicted: the replayed (old) event is treated as NEW.
      expect(session.markSeen(events[0]), isTrue);
    });
  });

  group('RealtimeSyncSession.markSeen (game_answers composite key, F-RT6)', () {
    test(
        'two answers by the same user in one transaction are distinct '
        'events (game_id in the dedup key)', () {
      final session = RealtimeSyncSession();
      sb.PostgresChangePayload answer(int gameId) => realtimePayload(
            table: 'game_answers',
            eventType: sb.PostgresChangeEvent.insert,
            newRecord: {
              'game_id': gameId,
              'user_id': 42,
              'selected_option': 1,
            },
            commitTimestamp: DateTime.utc(2026),
          );

      expect(session.markSeen(answer(1)), isTrue);
      // Same user + same commit timestamp + different game_id -> the key is
      // (game_id, user_id), so the second event is NOT a false duplicate.
      expect(session.markSeen(answer(2)), isTrue);
    });

    test('a replay of the SAME game answer is still rejected', () {
      final session = RealtimeSyncSession();
      final event = realtimePayload(
        table: 'game_answers',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'game_id': 3, 'user_id': 42, 'selected_option': 1},
        commitTimestamp: DateTime.utc(2026),
      );

      expect(session.markSeen(event), isTrue);
      expect(session.markSeen(event), isFalse);
    });

    test('other tables keep their previous single-column identity', () {
      final session = RealtimeSyncSession();
      final event = realtimePayload(
        table: 'missyou',
        eventType: sb.PostgresChangeEvent.insert,
        newRecord: {'id': 9, 'partnership_id': 4},
        commitTimestamp: DateTime.utc(2026),
      );

      expect(session.markSeen(event), isTrue);
      expect(session.markSeen(event), isFalse);
    });

    test('the non-game_answers identity is `id`, not a fallback column', () {
      final session = RealtimeSyncSession();
      final ts = DateTime.utc(2026, 5);

      // Same `id`, different `partnership_id`/`user_id`: still one row, so the
      // event is a duplicate. If identity fell back to a partner column this
      // would read as new.
      expect(
        session.markSeen(realtimePayload(
          table: 'missyou',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 9, 'partnership_id': 4, 'user_id': 1},
          commitTimestamp: ts,
        )),
        isTrue,
      );
      expect(
        session.markSeen(realtimePayload(
          table: 'missyou',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 9, 'partnership_id': 77, 'user_id': 88},
          commitTimestamp: ts,
        )),
        isFalse,
        reason:
            '`id` is the identity, so a changed partner column is the same row',
      );

      // Different `id`, everything else identical: a genuinely new row. If the
      // identity were `partnership_id` this would be a false duplicate.
      expect(
        session.markSeen(realtimePayload(
          table: 'missyou',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'id': 10, 'partnership_id': 4, 'user_id': 1},
          commitTimestamp: ts,
        )),
        isTrue,
        reason: 'a new `id` must not be deduped against the shared partnership',
      );
    });

    test('rows without `id` fall back to partnership_id, then user_id', () {
      final session = RealtimeSyncSession();
      final ts = DateTime.utc(2026, 6);

      // No `id` -> identity is `partnership_id`: different partnership ids are
      // distinct rows even at the same commit timestamp.
      expect(
        session.markSeen(realtimePayload(
          table: 'partnership_events',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'partnership_id': 4},
          commitTimestamp: ts,
        )),
        isTrue,
      );
      expect(
        session.markSeen(realtimePayload(
          table: 'partnership_events',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'partnership_id': 5},
          commitTimestamp: ts,
        )),
        isTrue,
        reason: 'fallback identity must separate distinct partnerships',
      );
      expect(
        session.markSeen(realtimePayload(
          table: 'partnership_events',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'partnership_id': 4},
          commitTimestamp: ts,
        )),
        isFalse,
        reason: 'the fallback must still dedup an identical replay',
      );

      // Neither `id` nor `partnership_id` -> identity falls back to `user_id`.
      expect(
        session.markSeen(realtimePayload(
          table: 'user_events',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'user_id': 42},
          commitTimestamp: ts,
        )),
        isTrue,
      );
      expect(
        session.markSeen(realtimePayload(
          table: 'user_events',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'user_id': 43},
          commitTimestamp: ts,
        )),
        isTrue,
        reason: 'the user_id fallback must separate distinct users',
      );
    });

    test('a row with no identity column at all collapses onto one key', () {
      // Documents a real limitation of the `id ?? partnership_id ?? user_id`
      // chain: when none of those columns exist the identity becomes '', so
      // every such row in the same table/type/timestamp dedupes to one event.
      // Pinned deliberately — if the fallback chain is ever given a content
      // digest this test is expected to change.
      final session = RealtimeSyncSession();
      final ts = DateTime.utc(2026, 7);

      expect(
        session.markSeen(realtimePayload(
          table: 'notes',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'content': 'first'},
          commitTimestamp: ts,
        )),
        isTrue,
      );
      expect(
        session.markSeen(realtimePayload(
          table: 'notes',
          eventType: sb.PostgresChangeEvent.insert,
          newRecord: {'content': 'second'},
          commitTimestamp: ts,
        )),
        isFalse,
        reason: 'known limitation: an empty identity dedupes distinct rows',
      );
    });
  });
}
