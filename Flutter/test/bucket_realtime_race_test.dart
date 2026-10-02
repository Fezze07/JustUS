import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

/// Repository whose snapshot fetch can be held open so the test can interleave
/// an incremental realtime insert in the middle of a full refresh.
class _GatedBucketRepository extends BucketRepository {
  _GatedBucketRepository({required this.gate, required this.snapshot});

  final Completer<void> gate;
  final List<Map<String, dynamic>> snapshot;

  @override
  Future<ResultWrapper<List<BucketItem>>> fetchBucketList() async {
    await gate.future;
    return Success(snapshot.map(BucketItem.fromJson).toList());
  }
}

Map<String, dynamic> _item(int id, String text) => {
      'id': id,
      'text': text,
      'done': false,
      'created_at': '2026-05-0${id}T00:00:00.000Z',
      'category': 'Personal',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test(
      'F-RT4 fixed: a stale full-refresh snapshot no longer clobbers a '
      'mid-flight incremental insert', () async {
    final gate = Completer<void>();
    final repository = _GatedBucketRepository(
      gate: gate,
      snapshot: [_item(1, 'already there')],
    );
    final state = BucketState(repository: repository);

    // Item A is known locally.
    await state.applyRealtimeEvent(
      eventType: 'insert',
      newRecord: _item(1, 'already there'),
      oldRecord: const {},
    );

    // A full refresh starts and is suspended at the (server) snapshot fetch —
    // the snapshot was read BEFORE item B committed.
    final refreshFuture = state.refreshFromRealtime();

    // Concurrent realtime event: item B is applied incrementally.
    await state.applyRealtimeEvent(
      eventType: 'insert',
      newRecord: _item(2, 'arrived mid-screen'),
      oldRecord: const {},
    );
    expect(state.items.map((i) => i.id), contains(2));

    // Release the stale snapshot (it does NOT contain item B). The version
    // token captured at fetch start now differs, so the snapshot is skipped
    // and the incremental insert survives.
    gate.complete();
    await refreshFuture;

    expect(state.items.map((i) => i.id), contains(2));
    expect(state.items.map((i) => i.id), [2, 1]);

    state.clear();
  });
}
