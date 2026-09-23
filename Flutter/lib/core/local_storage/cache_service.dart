import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static const kGameAnswers = 'chk_game_answers';
  static const kMoods = 'chk_moods';
  static const kBucketItems = 'chk_bucket_items';
  static const kDriveItems = 'chk_drive_items';
  static const kMissYou = 'chk_miss_you';
  static const kCheckpointEmpty = 'EMPTY';

  static const _allKeys = [
    kGameAnswers,
    kMoods,
    kBucketItems,
    kDriveItems,
    kMissYou,
  ];

  static int? _partnershipId;
  static int _checkpointEpoch = 0;

  /// Monotonic generation bumped whenever checkpoints are cleared
  /// (`clearAll`/`purge`/`clearCheckpoints`). Fetch roots capture the value at
  /// operation start and pass it to [saveCheckpoint]; a clear that lands while
  /// the fetch is in flight bumps the epoch, so the stale write-back is
  /// dropped instead of surviving the logout/wipe for the previous user
  /// (F-SM14).
  static int get checkpointEpoch => _checkpointEpoch;

  /// Partitions checkpoint keys per-partnership so a new partnership never
  /// reads checkpoints written under an earlier one (F-SC8). Mirrored by
  /// [StorageService.setActivePartnership]; kept here so checkpoint callers do
  /// not need to import StorageService.
  static void setPartnership(int? id) => _partnershipId = id;

  static String _scoped(String base) =>
      _partnershipId == null ? base : '$base:$_partnershipId';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> saveCheckpoint(
    String key,
    String isoTimestamp, {
    int? epoch,
  }) async {
    if (epoch != null && epoch != _checkpointEpoch) return;
    final p = await _prefs;
    await p.setString(_scoped(key), isoTimestamp);
  }

  static Future<String?> getCheckpoint(String key) async {
    final p = await _prefs;

    return p.getString(_scoped(key));
  }

  static Future<void> clearCheckpoints(List<String> keys) async {
    final p = await _prefs;
    for (final key in keys) {
      await p.remove(_scoped(key));
    }
    _checkpointEpoch++;
  }

  static Future<bool> needsRefresh(String key, {int minSeconds = 60}) async {
    final checkpoint = await getCheckpoint(key);
    if (checkpoint == null) return true;

    final lastRefresh = DateTime.tryParse(checkpoint);
    if (lastRefresh == null) return true;

    final elapsed = DateTime.now().toUtc().difference(lastRefresh.toUtc());

    return elapsed.inSeconds >= minSeconds;
  }

  static Future<void> clearAll() async {
    final p = await _prefs;
    final scope = _partnershipId?.toString();
    for (final key in _allKeys) {
      await p.remove(key);
      if (scope != null) await p.remove('$key:$scope');
    }
    _checkpointEpoch++;
  }

  /// Removes checkpoint variants for [oldId]/[newId] partnership scopes plus
  /// the unscoped legacy variant. Called during a partnership transition so a
  /// new partnership cannot be suppressed by an earlier checkpoint.
  static Future<void> purge({int? oldId, int? newId}) async {
    final p = await _prefs;
    final oldScope = oldId?.toString();
    final newScope = newId?.toString();
    for (final key in _allKeys) {
      await p.remove(key);
      if (oldScope != null) await p.remove('$key:$oldScope');
      if (newScope != null) await p.remove('$key:$newScope');
    }
    _checkpointEpoch++;
  }
}
