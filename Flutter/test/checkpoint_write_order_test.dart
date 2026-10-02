import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 4.11 / F-RT10 (R-1): an older-observed refresh must
/// not REGRESS a checkpoint already written by a newer refresh. The
/// `CheckpointMixin` token guard skips the stale writer (reuses the 4.10 epoch
/// pattern: a monotonic token captured at fetch start + checked at write).
class _CheckpointOwner with CheckpointMixin {
  int token = 0;

  int begin() => ++token;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  group('F-RT10 checkpoint write-order guard (CheckpointMixin)', () {
    test('a superseded writer is skipped; the current writer lands', () async {
      final owner = _CheckpointOwner();
      const key = CacheService.kMoods;
      const ts = '2026-05-01T00:00:00.000Z';

      // Refresh A begins (token 1), then refresh B begins (token 2): B
      // observed newer data and supersedes A.
      final tokenA = owner.begin();
      owner.begin();

      await owner.saveMaxTimestampCheckpoint(
        checkpointKey: key,
        timestamps: [ts],
        writerToken: tokenA,
        currentToken: owner.token,
      );
      // A is stale -> nothing written (no regression possible).
      expect(await CacheService.getCheckpoint(key), isNull);

      // B is still current -> its checkpoint lands.
      await owner.saveMaxTimestampCheckpoint(
        checkpointKey: key,
        timestamps: [ts],
        writerToken: owner.token,
        currentToken: owner.token,
      );
      expect(await CacheService.getCheckpoint(key), ts);
    });

    test('fromItems helper honours the same guard', () async {
      final owner = _CheckpointOwner();
      const key = CacheService.kGameAnswers;

      final tokenA = owner.begin();
      owner.begin();

      await owner.saveMaxTimestampCheckpointFromItems(
        checkpointKey: key,
        items: <dynamic>[
          BucketItem.fromJson({
            'id': 1,
            'text': 'x',
            'done': false,
            'created_at': '2026-05-01T00:00:00.000Z',
            'updated_at': '2026-05-01T00:00:00.000Z',
          }),
        ],
        timestampField: (item) => (item as BucketItem).updatedAt,
        writerToken: tokenA,
        currentToken: owner.token,
      );
      expect(await CacheService.getCheckpoint(key), isNull);
    });

    test('token-less writes are unaffected (guard is opt-in)', () async {
      final owner = _CheckpointOwner();
      const key = CacheService.kGameAnswers;

      await owner.saveMaxTimestampCheckpoint(
        checkpointKey: key,
        timestamps: ['2026-05-02T00:00:00.000Z'],
      );
      expect(await CacheService.getCheckpoint(key), isNotNull);
    });
  });
}
