import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 4.5 / F-SC8: feature caches and checkpoints must be
/// namespaced per-partnership and purged only when the partnership id actually
/// changes, so re-partnering never shows previous-partner data.
DriveItem _item(int id, String name, String updatedAt) {
  return DriveItem.fromJson({
    'id': id,
    'name': name,
    'type': 'image',
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': updatedAt,
    'is_favorite': 0,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('F-SC8: feature cache and checkpoint keys are namespaced by partnership',
      () async {
    StorageService.setActivePartnership(5);

    await StorageService.saveDriveItems(
        [_item(1, 'a.png', '2026-02-01T00:00:00.000Z')]);
    await StorageService.saveTotalMissYou(2);
    await StorageService.saveMood('me', 'happy');
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-02-01T00:00:00.000Z');

    final p = await prefs();
    expect(p.getString('drive_cache:5'), isNotNull);
    expect(p.getInt('miss_you:5'), 2);
    expect(p.getString('mood_me:5'), 'happy');
    expect(p.getString('chk_drive_items:5'), isNotNull);

    // Base (legacy unscoped) keys must NOT be written while scoped.
    expect(p.getString('drive_cache'), isNull);
    expect(p.getString('miss_you'), isNull);
    expect(p.getString('chk_drive_items'), isNull);

    expect((await StorageService.getDriveItems()).single.id, 1);
    expect(await StorageService.getTotalMissYou(), 2);
    expect(await StorageService.getMood('me'), 'happy');
    expect(await CacheService.getCheckpoint(CacheService.kDriveItems),
        '2026-02-01T00:00:00.000Z');
  });

  test('F-SC8: savePartnershipId does not purge when the id is unchanged',
      () async {
    await StorageService.savePartnershipId(5);
    await StorageService.saveDriveItems(
        [_item(1, 'a.png', '2026-02-01T00:00:00.000Z')]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-02-01T00:00:00.000Z');

    // Same partnership id re-written (cold-start / realtime refresh).
    await StorageService.savePartnershipId(5);

    expect((await StorageService.getDriveItems()).single.id, 1);
    expect(await CacheService.getCheckpoint(CacheService.kDriveItems),
        '2026-02-01T00:00:00.000Z');
  });

  test('F-SC8: re-partnering purges the old namespace and forces a refetch',
      () async {
    await StorageService.savePartnershipId(5);
    await StorageService.saveDriveItems(
        [_item(1, 'old.png', '2026-02-01T00:00:00.000Z')]);
    await StorageService.saveTotalMissYou(9);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-02-05T00:00:00.000Z');

    // A new partnership forms with a different id.
    await StorageService.savePartnershipId(9);

    final p = await prefs();
    expect(p.getString('drive_cache:5'), isNull);
    expect(p.getInt('miss_you:5'), isNull);
    expect(p.getString('chk_drive_items:5'), isNull);

    // The incoming scope is purged too, so a stale cache that pre-dates this
    // partnership cannot suppress its first fetch. The cache is written under
    // the *incoming* scope id on purpose: a key written under the old id is
    // dropped by the old-scope branch and would never reach the newScope path.
    StorageService.setActivePartnership(11);
    await StorageService.saveDriveItems(
        [_item(99, 'stale.png', '2026-02-04T00:00:00.000Z')]);
    expect(p.getString('drive_cache:11'), isNotNull,
        reason: 'precondition: the incoming scope holds a cache');

    await StorageService.savePartnershipId(11);
    expect(p.getString('drive_cache:11'), isNull,
        reason: 'a scope-change purge must drop the incoming scope as well');

    // No checkpoint under the new namespace -> hasChanges would be true.
    expect(await CacheService.getCheckpoint(CacheService.kDriveItems), isNull);
    expect(await StorageService.getDriveItems(), isEmpty);
    expect(await StorageService.getTotalMissYou(), isNull);

    // New writes land in the new namespace only.
    await StorageService.saveDriveItems(
        [_item(2, 'new.png', '2026-02-06T00:00:00.000Z')]);
    expect(p.getString('drive_cache:11'), isNotNull);
    expect(p.getString('drive_cache:5'), isNull);
    expect(p.getString('drive_cache'), isNull,
        reason: 'scoped writes must never fall back to the legacy key');
  });

  test('F-SC8: clearPartner purges caches/checkpoints and resets the namespace',
      () async {
    await StorageService.savePartnershipId(7);
    await StorageService.saveDriveItems(
        [_item(1, 'a.png', '2026-02-01T00:00:00.000Z')]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-02-01T00:00:00.000Z');

    await StorageService.clearPartner();

    final p = await prefs();
    expect(p.getString('drive_cache:7'), isNull);
    expect(p.getString('drive_cache'), isNull);
    expect(p.getString('chk_drive_items:7'), isNull);
    expect(await StorageService.getPartnershipId(), isNull);
    expect(await StorageService.getDriveItems(), isEmpty);

    // Unscoped writes go to base keys while single.
    await StorageService.saveDriveItems(
        [_item(1, 'a.png', '2026-02-01T00:00:00.000Z')]);
    expect(p.getString('drive_cache'), isNotNull);
  });

  test(
      'F-SC8: clearAppCache and clearAll reset the scope and clear both namespaces',
      () async {
    await StorageService.savePartnershipId(4);
    await StorageService.saveDriveItems(
        [_item(1, 'a.png', '2026-02-01T00:00:00.000Z')]);
    await CacheService.saveCheckpoint(
        CacheService.kDriveItems, '2026-02-01T00:00:00.000Z');

    await StorageService.clearAppCache();
    final p = await prefs();
    expect(p.getString('drive_cache:4'), isNull);
    expect(p.getString('drive_cache'), isNull);

    await StorageService.saveTotalMissYou(1);
    await StorageService.clearAll();
    expect(p.getString('miss_you:4'), isNull);
    expect(await StorageService.getPartnershipId(), isNull);
    expect(await StorageService.getDriveItems(), isEmpty);
  });
}
