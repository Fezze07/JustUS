import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

/// Repository whose first snapshot fetch is held open and then returns a STALE
/// total (as if the snapshot was read before a concurrent `missyou` insert
/// committed); every later call returns the authoritative post-insert total.
class _TwoStepMissYouRepository extends MissYouRepository {
  _TwoStepMissYouRepository({
    required this.gate,
    required this.firstTotal,
    required this.laterTotal,
  });

  final Completer<void> gate;
  final int firstTotal;
  final int laterTotal;

  int calls = 0;

  @override
  Future<ResultWrapper<MissYouResponse>> fetchMissYouTotal() async {
    calls += 1;
    if (calls == 1) {
      await gate.future;
    }
    return Success(MissYouResponse(
      success: true,
      total: calls == 1 ? firstTotal : laterTotal,
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  group('F-RT5 addMissYou idempotency (per missyou-row-key)', () {
    test('the same missyou row id counts exactly once', () {
      final state = HomepageState();

      state.addMissYou(rowId: 7);
      state.addMissYou(rowId: 7);
      expect(state.totalMissYou, 1);

      state.addMissYou(rowId: 8);
      expect(state.totalMissYou, 2);

      state.clear();
    });

    test('rowId-less increments stay unconditional (back-compat)', () {
      final state = HomepageState();

      state.addMissYou();
      state.addMissYou();
      expect(state.totalMissYou, 2);

      state.clear();
    });

    test('tracked keys are a bounded FIFO (200); evicted ids may replay', () {
      final state = HomepageState();

      for (var i = 0; i <= 200; i++) {
        state.addMissYou(rowId: i);
      }
      expect(state.totalMissYou, 201);

      // id 0 was evicted when id 200 entered (FIFO cap of 200): a replay of an
      // evicted id counts again (documented residual after the cap).
      state.addMissYou(rowId: 0);
      expect(state.totalMissYou, 202);

      // Re-adding 0 evicts id 1 from the front. id 2 is still tracked -> a
      // replay of 2 is ignored.
      state.addMissYou(rowId: 2);
      expect(state.totalMissYou, 202);

      state.clear();
    });

    test('clear() drops the dedup keys so the next session counts again', () {
      // Row ids are per-partnership: after a logout the incoming user's rows
      // must NOT be mistaken for replays of the previous session's rows.
      final state = HomepageState();

      state.addMissYou(rowId: 7);
      expect(state.totalMissYou, 1);

      // A replay within the same session is still swallowed.
      state.addMissYou(rowId: 7);
      expect(state.totalMissYou, 1);

      state.clear();
      expect(state.totalMissYou, 0);

      // The next account's row with the same numeric id must count.
      state.addMissYou(rowId: 7);
      expect(state.totalMissYou, 1,
          reason: 'clear() must reset the per-session dedup set');

      state.clear();
    });
  });

  group('F-RT5 fetchTotalMissYou staleness guard', () {
    test('an insert during the fetch triggers a refetch; stale total discarded',
        () async {
      final gate = Completer<void>();
      final repository = _TwoStepMissYouRepository(
        gate: gate,
        firstTotal: 0,
        laterTotal: 1,
      );
      final state = HomepageState(repository: repository);

      final fetchFuture = state.fetchTotalMissYou();

      // Realtime insert lands while the (stale) snapshot fetch is in flight.
      state.addMissYou(rowId: 5);
      expect(state.totalMissYou, 1);

      gate.complete();
      await fetchFuture;

      // The stale first snapshot (total 0) was discarded; the follow-up fetch
      // returned the authoritative post-insert total.
      expect(repository.calls, 2);
      expect(state.totalMissYou, 1);

      state.clear();
    });
  });
}
