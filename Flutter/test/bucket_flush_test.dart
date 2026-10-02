import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/settle_helpers.dart';

Map<String, dynamic> _item(int id, String text) => {
      'id': id,
      'text': text,
      'done': false,
      'created_at': '2026-05-0$id}T00:00:00.000Z',
      'updated_at': '2026-05-0$id}T00:00:00.000Z',
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
      'F-SC13: applying app-pause flushes the pending debounced cache write '
      'immediately', () async {
    final state = BucketState();

    await state.applyRealtimeEvent(
      eventType: 'insert',
      newRecord: _item(1, 'first'),
      oldRecord: const {},
    );

    // Debounce has not fired yet: nothing persisted.
    expect(await StorageService.getBucketList(), isEmpty);

    state.didChangeAppLifecycleState(AppLifecycleState.paused);

    await settleMicrotasks();
    expect(
      (await StorageService.getBucketList()).map((i) => i.id),
      [1],
    );

    state.clear();
  });

  test('F-SC13: dispose flushes the pending debounced cache write', () async {
    final state = BucketState();

    await state.applyRealtimeEvent(
      eventType: 'insert',
      newRecord: _item(2, 'second'),
      oldRecord: const {},
    );

    state.dispose();

    await settleMicrotasks();
    expect(
      (await StorageService.getBucketList()).map((i) => i.id),
      [2],
    );
  });
}
